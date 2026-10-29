import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import ModuleType

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app import main
from app.main import app, get_task_state, set_task_state
from app.omr_engine import OMRProcessingError, OMREngine, convert_musicxml_to_midi

client = TestClient(app)
PNG_BYTES = b"\x89PNG\r\n\x1a\nvalid-test-png"


@pytest.fixture(autouse=True)
def clear_local_tasks(monkeypatch):
    main.LOCAL_TASKS_DB.clear()
    monkeypatch.setattr(main, "get_redis_client", lambda: None)
    yield
    for task in main.LOCAL_TASKS_DB.values():
        file_path = task.get("file_path")
        if file_path and os.path.isfile(file_path):
            os.remove(file_path)
    main.LOCAL_TASKS_DB.clear()


def test_health_reports_unavailable_dependencies(monkeypatch):
    monkeypatch.setattr(main, "get_redis_client", lambda: None)
    monkeypatch.setattr(main.shutil, "which", lambda _executable: None)

    response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "service": "MelodiScan Engine",
        "dependencies": {"redis": False, "celery_worker": False, "audiveris": False},
    }


def test_health_reports_all_required_dependencies(monkeypatch):
    class WorkerControl:
        def ping(self, timeout):
            return [{"worker@host": {"ok": "pong"}}]

    class CeleryApp:
        control = WorkerControl()

    monkeypatch.setattr(main, "get_redis_client", lambda: object())
    monkeypatch.setattr(main.shutil, "which", lambda _executable: "/usr/bin/audiveris")
    monkeypatch.setattr("app.tasks.celery_app", CeleryApp())

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_scan_score_queues_valid_image(monkeypatch):
    from app.tasks import process_omr_task

    monkeypatch.setattr(process_omr_task, "delay", lambda *args: None)
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.png", PNG_BYTES, "image/png")},
        data={"title": "Test Piece"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "STATUS_QUEUED"
    task = get_task_state(data["task_id"])
    assert task["title"] == "Test Piece"
    assert Path(task["file_path"]).read_bytes() == PNG_BYTES


def test_api_key_is_required_only_when_configured(monkeypatch):
    from app.tasks import process_omr_task

    monkeypatch.setattr(main, "API_KEY", "local-test-key")
    monkeypatch.setattr(process_omr_task, "delay", lambda *args: None)
    upload = {"file": ("score.png", PNG_BYTES, "image/png")}

    unauthorized = client.post("/api/v1/scan", files=upload)
    authorized = client.post(
        "/api/v1/scan",
        files=upload,
        headers={"X-API-Key": "local-test-key"},
    )

    assert unauthorized.status_code == 401
    assert authorized.status_code == 200


def test_dashboard_requires_credentials_when_configured(monkeypatch):
    monkeypatch.setattr(main, "DASHBOARD_USERNAME", "admin")
    monkeypatch.setattr(main, "DASHBOARD_PASSWORD", "dashboard-test-password")
    monkeypatch.setattr(main, "API_KEY", "local-test-key")

    assert client.get("/dashboard").status_code == 401
    response = client.get(
        "/dashboard",
        auth=("admin", "dashboard-test-password"),
    )
    assert response.status_code == 200
    assert client.get("/api/v1/stats").status_code == 401
    assert client.get(
        "/api/v1/stats",
        auth=("admin", "dashboard-test-password"),
    ).status_code == 200


def test_scan_rejects_non_image_upload():
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.png", b"not an image", "image/png")},
    )

    assert response.status_code == 415


def test_scan_rejects_oversized_upload(monkeypatch):
    monkeypatch.setattr(main, "MAX_UPLOAD_BYTES", 8)
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.png", PNG_BYTES, "image/png")},
    )

    assert response.status_code == 413


def test_scan_reports_queue_failure(monkeypatch):
    from app.tasks import process_omr_task

    def fail_to_queue(*_args):
        raise RuntimeError("broker unavailable")

    monkeypatch.setattr(process_omr_task, "delay", fail_to_queue)
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.png", PNG_BYTES, "image/png")},
    )

    assert response.status_code == 503


def test_omr_engine_reports_missing_audiveris(tmp_path):
    engine = OMREngine(executable="missing-audiveris")

    with pytest.raises(OMRProcessingError, match="not installed"):
        engine.process_image(str(tmp_path / "score.png"), str(tmp_path))


def test_omr_engine_reports_audiveris_failure(tmp_path, monkeypatch):
    class ProcessResult:
        returncode = 1
        stderr = b"invalid score"

    monkeypatch.setattr("app.omr_engine.subprocess.run", lambda *args, **kwargs: ProcessResult())

    with pytest.raises(OMRProcessingError, match="invalid score"):
        OMREngine().process_image(str(tmp_path / "score.png"), str(tmp_path))


def test_worker_persists_processing_error(tmp_path, monkeypatch):
    from app.tasks import process_omr_task

    set_task_state("failed-worker-task", {
        "task_id": "failed-worker-task",
        "status": "STATUS_QUEUED",
        "created_at": datetime.now(timezone.utc).isoformat(),
    })

    def fail_processing(*_args):
        raise OMRProcessingError("Audiveris unavailable")

    monkeypatch.setattr("app.tasks.OMREngine.process_image", fail_processing)

    with pytest.raises(OMRProcessingError, match="Audiveris unavailable"):
        process_omr_task.run("failed-worker-task", str(tmp_path / "score.png"), "Test")

    task = get_task_state("failed-worker-task")
    assert task["status"] == "STATUS_FAILED"
    assert task["error"] == "Audiveris unavailable"
    assert task["failed_at"]


def test_musicxml_conversion_error_does_not_create_fake_midi(tmp_path, monkeypatch):
    partitura = ModuleType("partitura")

    def fail_to_parse(_path):
        raise ValueError("invalid MusicXML")

    partitura.load_musicxml = fail_to_parse
    monkeypatch.setitem(sys.modules, "partitura", partitura)
    midi_path = tmp_path / "score.mid"

    with pytest.raises(OMRProcessingError, match="invalid MusicXML"):
        convert_musicxml_to_midi(str(tmp_path / "score.musicxml"), str(midi_path))

    assert not midi_path.exists()


def test_result_requires_completed_task(tmp_path):
    set_task_state("queued-task", {"status": "STATUS_QUEUED"})
    set_task_state("failed-task", {
        "status": "STATUS_FAILED",
        "error": "Audiveris unavailable",
    })

    assert client.get("/api/v1/result/unknown-task").status_code == 404
    assert client.get("/api/v1/result/queued-task").status_code == 409
    failed = client.get("/api/v1/result/failed-task")
    assert failed.status_code == 422
    assert failed.json()["detail"] == "Audiveris unavailable"


def test_status_stream_times_out_with_a_real_failure(monkeypatch):
    monkeypatch.setattr(main, "TASK_TIMEOUT_SECONDS", 0)
    set_task_state("stalled-task", {"status": "STATUS_QUEUED"})

    response = client.get("/api/v1/stream/stalled-task")

    assert response.status_code == 200
    assert '"status": "STATUS_FAILED"' in response.text
    assert "timed out" in response.text
    assert get_task_state("stalled-task")["status"] == "STATUS_FAILED"


def test_result_returns_only_the_completed_midi_file(tmp_path):
    midi_path = tmp_path / "result.mid"
    midi_path.write_bytes(b"MThd" + b"\x00" * 10)
    set_task_state("completed-task", {
        "status": "STATUS_COMPLETED",
        "midi_path": str(midi_path),
    })

    response = client.get("/api/v1/result/completed-task")

    assert response.status_code == 200
    assert response.content == midi_path.read_bytes()


def test_result_does_not_invent_missing_midi(tmp_path):
    set_task_state("broken-task", {
        "status": "STATUS_COMPLETED",
        "midi_path": str(tmp_path / "missing.mid"),
    })

    response = client.get("/api/v1/result/broken-task")

    assert response.status_code == 500
    assert not (tmp_path / "missing.mid").exists()


def test_stats_use_task_timestamps():
    now = datetime.now(timezone.utc)
    set_task_state("successful-task", {
        "status": "STATUS_COMPLETED",
        "created_at": (now - timedelta(seconds=12)).isoformat(),
        "completed_at": now.isoformat(),
    })
    set_task_state("failed-task", {"status": "STATUS_FAILED"})

    response = client.get("/api/v1/stats")
    data = response.json()

    assert response.status_code == 200
    assert data["total_scans"] == 2
    assert data["completed_scans"] == 1
    assert data["failed_scans"] == 1
    assert data["success_rate"] == 50.0
    assert data["avg_processing_time_sec"] == 12.0
