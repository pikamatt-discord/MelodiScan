#!/usr/bin/env python3
import base64
import hashlib
import io
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from uuid import UUID


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = Path(os.environ.get("MELODISCAN_TEST_ENV_FILE", ROOT / ".env"))
CERT_FILE = Path(os.environ.get("MELODISCAN_TEST_CERT_FILE", ROOT / "data" / "caddy-root.crt"))
APK_FILE = Path(os.environ.get("MELODISCAN_TEST_APK_FILE", ROOT / "data" / "apk" / "app-release.apk"))
API_URL = os.environ.get("MELODISCAN_TEST_API_URL", "http://127.0.0.1:8080")


def report(name: str, ok: bool, detail: str = "") -> bool:
    status = "PASS" if ok else "FAIL"
    suffix = f" — {detail}" if detail else ""
    print(f"[{status}] E2E {name}{suffix}", flush=True)
    return ok


def read_environment() -> dict[str, str]:
    values = {}
    if not ENV_FILE.is_file():
        return values
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def request(url: str, *, headers=None, auth=None, data=None, context=None, timeout=15):
    request_headers = dict(headers or {})
    if auth is not None:
        token = base64.b64encode(f"{auth[0]}:{auth[1]}".encode()).decode()
        request_headers["Authorization"] = f"Basic {token}"
    req = urllib.request.Request(url, data=data, headers=request_headers)
    try:
        with urllib.request.urlopen(req, context=context, timeout=timeout) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, error.read(), dict(error.headers)


def make_multipart(boundary: str, filename: str, content_type: str, body: bytes) -> bytes:
    return (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode() + body + f"\r\n--{boundary}--\r\n".encode()


def remove_e2e_task(task_id: str) -> bool:
    try:
        task_id = str(UUID(task_id))
    except ValueError:
        return False

    commands = (
        ("DEL", f"task:{task_id}"),
        ("SREM", "task_ids", task_id),
    )
    compose = ["docker", "compose"]
    if ENV_FILE.is_file():
        compose.extend(["--env-file", str(ENV_FILE)])
    cleanup_script = """
from pathlib import Path
import sys

task_id = sys.argv[1]
directory = Path("data/temp")
if directory.is_dir():
    for path in directory.iterdir():
        suffix = path.name[len(task_id):] if path.name.startswith(task_id) else ""
        if path.is_file() and suffix.startswith((".", "-")):
            path.unlink()
"""
    cleanup_files = subprocess.run(
        [
            *compose,
            "exec",
            "-T",
            "melodiscan-worker",
            "python",
            "-c",
            cleanup_script,
            task_id,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    success = cleanup_files.returncode == 0
    for command in commands:
        result = subprocess.run(
            [*compose, "exec", "-T", "melodiscan-redis", "redis-cli", *command],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        success = success and result.returncode == 0
    return success


def main() -> int:
    env = read_environment()
    api_key = env.get("API_KEY", "")
    username = env.get("DASHBOARD_USERNAME", "")
    password = env.get("DASHBOARD_PASSWORD", "")
    host = env.get("MELODISCAN_HOST", "")
    checks = []

    checks.append(report("deployment configuration", bool(api_key and username and password and host),
                         "expected API/dashboard credentials and HTTPS host in .env"))
    checks.append(report("Caddy root certificate", CERT_FILE.is_file() and CERT_FILE.stat().st_size > 0,
                         "data/caddy-root.crt is required"))
    if not all((api_key, username, password, host)) or not CERT_FILE.is_file():
        return 1

    https_url = f"https://{host}"
    try:
        status, body, _ = request(
            f"{https_url}/health",
            context=ssl.create_default_context(cafile=str(CERT_FILE)),
        )
        health = json.loads(body)
        dependencies = health.get("dependencies", {})
        checks.append(report(
            "HTTPS certificate and health",
            status == 200 and health.get("status") == "ok",
            f"HTTP {status}; dependencies: {dependencies}",
        ))
    except Exception as error:
        checks.append(report("HTTPS certificate and health", False, str(error)))
        return 1

    headers = {"X-API-Key": api_key}
    try:
        status, _, _ = request(f"{API_URL}/api/v1/stats")
        checks.append(report("API rejects missing key", status == 401, f"HTTP {status}"))

        status, _, _ = request(
            f"{API_URL}/api/v1/stats",
            headers={"X-API-Key": "invalid-e2e-key"},
        )
        checks.append(report("API rejects invalid key", status == 401, f"HTTP {status}"))

        status, body, _ = request(f"{API_URL}/api/v1/stats", headers=headers)
        stats = json.loads(body) if status == 200 else {}
        checks.append(report("API accepts configured key", status == 200 and "total_scans" in stats,
                             f"HTTP {status}"))

        status, _, _ = request(f"{API_URL}/dashboard")
        checks.append(report("dashboard rejects missing credentials", status == 401, f"HTTP {status}"))

        status, _, _ = request(
            f"{API_URL}/dashboard",
            auth=(username, "invalid-e2e-password"),
        )
        checks.append(report("dashboard rejects invalid credentials",
                             status == 401, f"HTTP {status}"))

        status, body, _ = request(
            f"{https_url}/dashboard",
            auth=(username, password),
            context=ssl.create_default_context(cafile=str(CERT_FILE)),
        )
        checks.append(report("dashboard accepts configured credentials",
                             status == 200 and b"MelodiScan" in body, f"HTTP {status}"))

        status, _, _ = request(f"{API_URL}/download/app-release.apk")
        checks.append(report("APK download rejects missing key", status == 401, f"HTTP {status}"))

        status, _, _ = request(
            f"{API_URL}/download/app-release.apk",
            headers={"X-API-Key": "invalid-e2e-key"},
        )
        checks.append(report("APK download rejects invalid key", status == 401, f"HTTP {status}"))

        status, apk_bytes, _ = request(f"{API_URL}/download/app-release.apk", headers=headers)
        try:
            with zipfile.ZipFile(APK_FILE) as apk_file:
                apk_integrity_ok = apk_file.testzip() is None
                apk_has_manifest = "AndroidManifest.xml" in apk_file.namelist()
            valid_apk = (
                status == 200
                and apk_bytes.startswith(b"PK")
                and apk_integrity_ok
                and apk_has_manifest
                and hashlib.sha256(apk_bytes).digest()
                == hashlib.sha256(APK_FILE.read_bytes()).digest()
            )
            if valid_apk:
                with zipfile.ZipFile(io.BytesIO(apk_bytes)) as downloaded_apk:
                    valid_apk = downloaded_apk.testzip() is None
        except (OSError, zipfile.BadZipFile):
            valid_apk = False
        checks.append(report("APK download returns a valid Android package",
                             valid_apk, f"HTTP {status}; downloaded {len(apk_bytes)} bytes"))

        boundary = "melodiscan-e2e-boundary"
        invalid_payload = make_multipart(boundary, "invalid.txt", "text/plain", b"not an image")
        status, _, _ = request(
            f"{API_URL}/api/v1/scan",
            headers={**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
            data=invalid_payload,
        )
        checks.append(report("scan rejects unsupported image type", status == 415, f"HTTP {status}"))

        malformed_png = make_multipart(
            boundary,
            "malformed.png",
            "image/png",
            b"\x89PNG\r\n\x1a\nnot-a-decodable-png",
        )
        status, body, _ = request(
            f"{API_URL}/api/v1/scan",
            headers={**headers, "Content-Type": f"multipart/form-data; boundary={boundary}"},
            data=malformed_png,
        )
        try:
            task_id = json.loads(body).get("task_id") if status == 200 else None
        except json.JSONDecodeError:
            task_id = None
        checks.append(report("malformed image request is queued for explicit OMR failure",
                             status == 200 and bool(task_id), f"HTTP {status}"))

        if task_id:
            stream_req = urllib.request.Request(
                f"{API_URL}/api/v1/stream/{task_id}",
                headers=headers,
            )
            final_event = None
            try:
                with urllib.request.urlopen(stream_req, timeout=180) as stream:
                    for raw_line in stream:
                        line = raw_line.decode("utf-8", errors="replace").strip()
                        if line.startswith("data: "):
                            event = json.loads(line[6:])
                            if event.get("status") in {"STATUS_COMPLETED", "STATUS_FAILED"}:
                                final_event = event
                                break
                expected_failure = (
                    final_event is not None
                    and final_event.get("status") == "STATUS_FAILED"
                    and bool(final_event.get("error"))
                )
                checks.append(report("worker SSE surfaces real OMR failure",
                                     expected_failure,
                                     f"final status: {(final_event or {}).get('status', 'no terminal event')}"))
                if expected_failure:
                    result_status, _, _ = request(
                        f"{API_URL}/api/v1/result/{task_id}",
                        headers=headers,
                    )
                    checks.append(report("failed task exposes no MIDI result",
                                         result_status == 422, f"HTTP {result_status}"))
                    stats_status, stats_body, _ = request(
                        f"{API_URL}/api/v1/stats",
                        headers=headers,
                    )
                    updated_stats = json.loads(stats_body) if stats_status == 200 else {}
                    recent_ids = {
                        task.get("task_id")
                        for task in updated_stats.get("recent_tasks", [])
                    }
                    checks.append(report(
                        "statistics include the failed E2E scan",
                        stats_status == 200
                        and updated_stats.get("failed_scans", 0) >= 1
                        and task_id in recent_ids,
                        f"HTTP {stats_status}",
                    ))
            except Exception as error:
                checks.append(report("worker SSE surfaces real OMR failure", False, str(error)))
            checks.append(report(
                "remove generated E2E task from scan history",
                remove_e2e_task(task_id),
            ))

    except Exception as error:
        checks.append(report("HTTP/API integration", False, str(error)))

    return 0 if all(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
