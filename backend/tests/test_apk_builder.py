import hashlib
import base64
import importlib.util
import json
import sys
import zipfile
from pathlib import Path
from subprocess import CompletedProcess


ROOT = Path(__file__).resolve().parents[2]
SERVICE_PATH = ROOT / "scripts" / "apk-builder-service.py"
if not SERVICE_PATH.is_file():
    SERVICE_PATH = Path("/scripts/apk-builder-service.py")
SPEC = importlib.util.spec_from_file_location("melodiscan_apk_builder", SERVICE_PATH)
apk_builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = apk_builder
SPEC.loader.exec_module(apk_builder)


def prepare_builder(tmp_path, monkeypatch):
    workspace = tmp_path / "mobile"
    built_apk = workspace / "build/app/outputs/flutter-apk/app-release.apk"
    built_apk.parent.mkdir(parents=True)
    (workspace / "pubspec.yaml").write_text("name: test", encoding="utf-8")
    (workspace / "lib").mkdir()
    (workspace / "lib" / "main.dart").write_text("void main() {}", encoding="utf-8")
    output = tmp_path / "output"
    output.mkdir()
    ca_file = tmp_path / "root.crt"
    ca_file.write_bytes(b"test-root-certificate")

    monkeypatch.setattr(apk_builder, "WORKSPACE", workspace)
    monkeypatch.setattr(apk_builder, "APK_PATH", output / "app-release.apk")
    monkeypatch.setattr(apk_builder, "METADATA_PATH", output / "app-release.json")
    monkeypatch.setattr(apk_builder, "CA_PATH", ca_file)
    monkeypatch.setattr(apk_builder, "API_KEY", "test-api-key")
    monkeypatch.setattr(apk_builder, "HOST", "192.168.1.25")
    with apk_builder.STATE_LOCK:
        apk_builder.BUILD_STATE.clear()
        apk_builder.BUILD_STATE.update({"build_id": "test-build", "status": "building"})
    return workspace, built_apk, output


def test_build_creates_signed_release_artifact_with_deployment_defines(tmp_path, monkeypatch):
    workspace, built_apk, output = prepare_builder(tmp_path, monkeypatch)
    commands = []
    defines = {}

    def run(command, **_kwargs):
        commands.append(command)
        defines_arg = next(
            (argument for argument in command if argument.startswith("--dart-define-from-file=")),
            None,
        )
        if defines_arg:
            defines.update(json.loads(Path(defines_arg.split("=", 1)[1]).read_text(encoding="utf-8")))
        if command[1:4] == ["build", "apk", "--release"]:
            with zipfile.ZipFile(built_apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
        if command[0] == "apksigner":
            return CompletedProcess(command, 0, "Verifies\n", None)
        return CompletedProcess(command, 0, "Success\n", None)

    monkeypatch.setattr(apk_builder.subprocess, "run", run)
    monkeypatch.setattr(apk_builder.shutil, "which", lambda executable: "apksigner")
    apk_builder.build_apk("test-build")

    state = apk_builder.current_status()
    assert state["status"] == "completed"
    assert state["signature_verified"] is True
    assert state["apk"]["available"] is True
    assert state["apk"]["signature_verified"] is True
    assert state["apk"]["input_fingerprint"]
    assert state["apk"]["sha256"] == hashlib.sha256((output / "app-release.apk").read_bytes()).hexdigest()
    assert zipfile.is_zipfile(output / "app-release.apk")

    defines_arg = next(
        argument for command in commands for argument in command
        if argument.startswith("--dart-define-from-file=")
    )
    defines_path = Path(defines_arg.split("=", 1)[1])
    assert not defines_path.exists()
    assert defines == {
        "MELODISCAN_API_URL": "https://192.168.1.25",
        "MELODISCAN_API_KEY": "test-api-key",
        "MELODISCAN_ROOT_CA_BASE64": base64.b64encode(b"test-root-certificate").decode("ascii"),
    }


def test_build_input_fingerprint_tracks_mobile_and_deployment_inputs(tmp_path, monkeypatch):
    workspace, _built_apk, _output = prepare_builder(tmp_path, monkeypatch)

    initial = apk_builder.build_input_fingerprint()
    assert apk_builder.build_input_fingerprint() == initial

    (workspace / "build").mkdir(exist_ok=True)
    (workspace / "build" / "generated.dart").write_text("generated", encoding="utf-8")
    assert apk_builder.build_input_fingerprint() == initial

    assets = workspace / "assets" / "build"
    assets.mkdir(parents=True)
    (assets / "input.txt").write_text("asset", encoding="utf-8")
    assets_fingerprint = apk_builder.build_input_fingerprint()
    assert assets_fingerprint != initial

    (workspace / "lib" / "main.dart").write_text("void main() { print('updated'); }", encoding="utf-8")
    source_changed = apk_builder.build_input_fingerprint()
    assert source_changed != assets_fingerprint

    monkeypatch.setattr(apk_builder, "HOST", "192.168.1.26")
    host_changed = apk_builder.build_input_fingerprint()
    assert host_changed != source_changed

    monkeypatch.setattr(apk_builder, "API_KEY", "updated-api-key")
    key_changed = apk_builder.build_input_fingerprint()
    assert key_changed != host_changed

    apk_builder.CA_PATH.write_bytes(b"updated-root-certificate")
    assert apk_builder.build_input_fingerprint() != key_changed


def test_failed_flutter_build_reports_error_and_preserves_no_success_state(tmp_path, monkeypatch):
    _workspace, _built_apk, output = prepare_builder(tmp_path, monkeypatch)

    def fail(command, **_kwargs):
        return CompletedProcess(command, 1, "Gradle failed", None)

    monkeypatch.setattr(apk_builder.subprocess, "run", fail)
    apk_builder.build_apk("test-build")

    state = apk_builder.current_status()
    assert state["status"] == "failed"
    assert "Gradle failed" in state["error"]
    assert state["apk"]["available"] is False
    assert not list(output.glob(".app-release-*.tmp"))
    assert not list(output.glob(".app-release-metadata-*.tmp"))
