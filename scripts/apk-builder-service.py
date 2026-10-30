#!/usr/bin/env python3
import base64
import hashlib
import hmac
import json
import os
import shutil
import stat
import subprocess
import tempfile
import threading
import uuid
import zipfile
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


WORKSPACE = Path("/workspace/mobile")
APK_PATH = Path("/output/app-release.apk")
METADATA_PATH = Path("/output/app-release.json")
CA_PATH = Path(os.environ.get("MELODISCAN_CA_PATH", "/run/secrets/caddy-root.crt"))
API_KEY = os.environ.get("API_KEY", "")
HOST = os.environ.get("MELODISCAN_HOST", "")
STATE_LOCK = threading.Lock()
BUILD_STATE = {"status": "idle"}
MAX_LOG_LENGTH = 6000
BUILD_ENVIRONMENT = "ghcr.io/cirruslabs/flutter:3.44.0"
GENERATED_DIRECTORIES = {".dart_tool", ".gradle", ".idea", ".git"}
GENERATED_BUILD_DIRECTORIES = {"build", "android/build", "android/app/build"}
GENERATED_FILES = {".flutter-plugins", ".flutter-plugins-dependencies", "local.properties"}


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def build_input_fingerprint() -> str:
    digest = hashlib.sha256()
    ca_bytes = CA_PATH.read_bytes()
    config = {
        "api_url": f"https://{HOST}",
        "api_key": API_KEY,
        "ca_sha256": hashlib.sha256(ca_bytes).hexdigest(),
        "build_environment": BUILD_ENVIRONMENT,
    }
    digest.update(json.dumps(config, sort_keys=True).encode("utf-8"))
    digest.update(Path(__file__).read_bytes())

    for root, directories, filenames in os.walk(WORKSPACE):
        kept_directories = []
        for name in directories:
            relative_directory = (Path(root) / name).relative_to(WORKSPACE).as_posix()
            if name in GENERATED_DIRECTORIES or relative_directory in GENERATED_BUILD_DIRECTORIES:
                continue
            kept_directories.append(name)
        directories[:] = sorted(kept_directories)
        for filename in sorted(filenames):
            if filename in GENERATED_FILES:
                continue
            path = Path(root) / filename
            relative_path = path.relative_to(WORKSPACE).as_posix()
            digest.update(relative_path.encode("utf-8"))
            with path.open("rb") as source_file:
                for block in iter(lambda: source_file.read(1024 * 1024), b""):
                    digest.update(block)
    return digest.hexdigest()


def artifact_info() -> dict:
    if not APK_PATH.is_file():
        return {"available": False}

    metadata = {}
    try:
        metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        digest = hashlib.sha256()
        with APK_PATH.open("rb") as apk_file:
            for block in iter(lambda: apk_file.read(1024 * 1024), b""):
                digest.update(block)
        metadata = {"sha256": digest.hexdigest()}

    details = APK_PATH.stat()
    return {
        "available": True,
        "size_bytes": details.st_size,
        "sha256": metadata.get("sha256"),
        "signature_verified": metadata.get("signature_verified", False),
        "input_fingerprint": metadata.get("input_fingerprint"),
        "generated_at": metadata.get(
            "generated_at",
            datetime.fromtimestamp(details.st_mtime, timezone.utc).isoformat(),
        ),
    }


def current_status() -> dict:
    with STATE_LOCK:
        state = dict(BUILD_STATE)
    state["apk"] = artifact_info()
    return state


def set_build_state(build_id: str, **updates) -> None:
    with STATE_LOCK:
        if BUILD_STATE.get("build_id") == build_id:
            BUILD_STATE.update(updates)


def build_apk(build_id: str) -> None:
    defines_path = None
    staged_apk = None
    staged_metadata = None
    try:
        input_fingerprint = build_input_fingerprint()
        ca_base64 = base64.b64encode(CA_PATH.read_bytes()).decode("ascii")
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", prefix="melodiscan-dart-defines-", suffix=".json", delete=False
        ) as defines_file:
            json.dump({
                "MELODISCAN_API_URL": f"https://{HOST}",
                "MELODISCAN_API_KEY": API_KEY,
                "MELODISCAN_ROOT_CA_BASE64": ca_base64,
            }, defines_file)
            defines_path = Path(defines_file.name)
        defines_path.chmod(stat.S_IRUSR | stat.S_IWUSR)

        if not (WORKSPACE / "pubspec.yaml").is_file():
            raise RuntimeError("Le projet Flutter mobile est introuvable dans le conteneur de génération.")

        steps = (
            (
                "Vérification des dépendances Flutter verrouillées",
                ["flutter", "pub", "get", "--enforce-lockfile"],
            ),
            (
                "Compilation de l’APK Android Release",
                [
                    "flutter", "build", "apk", "--release", "--no-pub",
                    f"--dart-define-from-file={defines_path}",
                ],
            ),
        )
        for progress, command in steps:
            set_build_state(build_id, progress=progress)
            result = subprocess.run(
                command,
                cwd=WORKSPACE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                timeout=3600,
                check=False,
            )
            if result.returncode:
                details = "\n".join(result.stdout.splitlines()[-30:])[-MAX_LOG_LENGTH:]
                raise RuntimeError(f"{progress} échouée (code {result.returncode}).\n{details}")

        built_apk = WORKSPACE / "build/app/outputs/flutter-apk/app-release.apk"
        if not built_apk.is_file() or built_apk.stat().st_size == 0:
            raise RuntimeError("La compilation Flutter n’a pas produit l’APK attendu.")
        with zipfile.ZipFile(built_apk) as archive:
            if archive.testzip() is not None or "AndroidManifest.xml" not in archive.namelist():
                raise RuntimeError("L’APK compilé est corrompu ou ne contient pas AndroidManifest.xml.")

        android_home = Path(os.environ.get("ANDROID_HOME", "/opt/android-sdk-linux"))
        signer_candidates = sorted((android_home / "build-tools").glob("*/apksigner"))
        signer = shutil.which("apksigner") or (str(signer_candidates[-1]) if signer_candidates else "")
        if not signer:
            raise RuntimeError("L’outil Android apksigner est introuvable dans le SDK du générateur.")
        signature = subprocess.run(
            [signer, "verify", "--verbose", str(built_apk)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=60,
            check=False,
        )
        if signature.returncode:
            details = "\n".join(signature.stdout.splitlines()[-20:])[-MAX_LOG_LENGTH:]
            raise RuntimeError(f"La signature Android de l’APK est invalide.\n{details}")

        digest = hashlib.sha256()
        with built_apk.open("rb") as apk_file:
            for block in iter(lambda: apk_file.read(1024 * 1024), b""):
                digest.update(block)

        APK_PATH.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=APK_PATH.parent, prefix=".app-release-", suffix=".tmp", delete=False
        ) as staged_apk_file:
            staged_path = Path(staged_apk_file.name)
        shutil.copyfile(built_apk, staged_path)
        staged_path.chmod(0o644)
        staged_apk = staged_path
        metadata = {
            "sha256": digest.hexdigest(),
            "signature_verified": True,
            "input_fingerprint": input_fingerprint,
            "generated_at": now(),
        }
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=METADATA_PATH.parent,
            prefix=".app-release-metadata-", suffix=".tmp", delete=False
        ) as metadata_file:
            json.dump(metadata, metadata_file)
            staged_metadata = Path(metadata_file.name)
        staged_metadata.chmod(0o644)
        os.replace(staged_apk, APK_PATH)
        staged_apk = None
        os.replace(staged_metadata, METADATA_PATH)
        staged_metadata = None
        set_build_state(
            build_id,
            status="completed",
            progress="APK généré et vérifié",
            signature_verified=True,
            completed_at=now(),
            error=None,
        )
    except (OSError, subprocess.SubprocessError, RuntimeError, zipfile.BadZipFile) as exc:
        set_build_state(
            build_id,
            status="failed",
            progress="Échec de la génération",
            completed_at=now(),
            error=str(exc)[-MAX_LOG_LENGTH:],
        )
    finally:
        if defines_path is not None:
            try:
                defines_path.unlink()
            except FileNotFoundError:
                pass
        for staged_file in (staged_apk, staged_metadata):
            if staged_file is not None:
                try:
                    staged_file.unlink()
                except FileNotFoundError:
                    pass


class Handler(BaseHTTPRequestHandler):
    server_version = "MelodiScanApkBuilder/1.0"

    def log_message(self, _format, *_args):
        return

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            ready = (
                shutil.which("flutter") is not None
                and WORKSPACE.is_dir()
                and bool(API_KEY)
                and bool(HOST)
                and CA_PATH.is_file()
                and CA_PATH.stat().st_size > 0
            )
            self.send_json(200 if ready else 503, {"status": "ok" if ready else "degraded"})
            return
        if self.path == "/status":
            self.send_json(200, current_status())
            return
        if self.path == "/fingerprint":
            self.send_json(200, {
                "input_fingerprint": build_input_fingerprint(),
                "apk": artifact_info(),
            })
            return
        if self.path.startswith("/build/"):
            build_id = self.path.removeprefix("/build/")
            with STATE_LOCK:
                exists = BUILD_STATE.get("build_id") == build_id
            if exists:
                self.send_json(200, current_status())
            else:
                self.send_json(404, {"detail": "Build not found."})
            return
        self.send_json(404, {"detail": "Not found."})

    def do_POST(self):
        if self.path != "/build":
            self.send_json(404, {"detail": "Not found."})
            return
        provided_key = self.headers.get("X-API-Key", "")
        if not API_KEY or not hmac.compare_digest(provided_key, API_KEY):
            self.send_json(401, {"detail": "A valid API key is required."})
            return

        parsed_host = urlsplit(f"https://{HOST}")
        if (
            not HOST
            or parsed_host.hostname is None
            or parsed_host.path
            or parsed_host.query
            or parsed_host.fragment
            or not CA_PATH.is_file()
        ):
            self.send_json(503, {"detail": "APK build configuration is incomplete."})
            return

        with STATE_LOCK:
            if BUILD_STATE.get("status") == "building":
                self.send_json(409, dict(BUILD_STATE))
                return
            build_id = str(uuid.uuid4())
            BUILD_STATE.clear()
            BUILD_STATE.update({
                "build_id": build_id,
                "status": "building",
                "progress": "Build démarré",
                "started_at": now(),
                "completed_at": None,
                "error": None,
            })

        thread = threading.Thread(target=build_apk, args=(build_id,), daemon=True)
        thread.start()
        self.send_json(202, current_status())


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8090), Handler).serve_forever()
