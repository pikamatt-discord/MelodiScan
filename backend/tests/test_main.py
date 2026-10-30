import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import ModuleType
from zipfile import ZIP_DEFLATED, ZipFile

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app import main
from app.main import app, get_task_state, set_task_state
from app.omr_engine import OMRProcessingError, OMREngine, convert_musicxml_to_midi

client = TestClient(app)
PNG_BYTES = b"\x89PNG\r\n\x1a\nvalid-test-png"
PDF_BYTES = b"%PDF-1.7\nvalid-test-pdf"


@pytest.fixture(autouse=True)
def clear_local_tasks(monkeypatch):
    main.LOCAL_TASKS_DB.clear()
    monkeypatch.setattr(main, "get_redis_client", lambda: None)
    yield
    for task in main.LOCAL_TASKS_DB.values():
        for path_key in ("file_path", "logs_path"):
            file_path = task.get(path_key)
            if file_path and os.path.isfile(file_path):
                os.remove(file_path)
    main.LOCAL_TASKS_DB.clear()


def test_health_reports_unavailable_dependencies(monkeypatch):
    monkeypatch.setattr(main, "get_redis_client", lambda: None)
    monkeypatch.setattr(main.shutil, "which", lambda _executable: None)

    async def builder_unavailable(_method, _path):
        return 503, {"status": "degraded"}

    monkeypatch.setattr(main, "request_apk_builder", builder_unavailable)
    response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {
        "status": "degraded",
        "service": "MelodiScan Engine",
        "dependencies": {
            "redis": False,
            "celery_worker": False,
            "audiveris": False,
            "apk_builder": False,
        },
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

    async def builder_ready(_method, _path):
        return 200, {"status": "ok"}

    monkeypatch.setattr(main, "request_apk_builder", builder_ready)
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
    assert "score.png" in Path(task["logs_path"]).read_text()


def test_scan_score_queues_pdf_document(monkeypatch):
    from app.tasks import process_omr_task

    monkeypatch.setattr(process_omr_task, "delay", lambda *args: None)
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.pdf", PDF_BYTES, "application/pdf")},
        data={"title": "PDF Score"},
    )

    assert response.status_code == 200
    task = get_task_state(response.json()["task_id"])
    assert task["title"] == "PDF Score"
    assert task["file_path"].endswith(".pdf")
    assert Path(task["file_path"]).read_bytes() == PDF_BYTES
    assert "score.pdf" in Path(task["logs_path"]).read_text()


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
    assert client.get("/dashboard/logs").status_code == 401
    assert client.get(
        "/dashboard/logs",
        auth=("admin", "dashboard-test-password"),
    ).status_code == 200
    assert client.get("/api/v1/stats").status_code == 401
    assert client.get(
        "/api/v1/stats",
        auth=("admin", "dashboard-test-password"),
    ).status_code == 200


def test_dashboard_exposes_management_views_and_apk_generation():
    response = client.get("/dashboard")

    assert response.status_code == 200
    assert 'id="stat-completed"' in response.text
    assert 'id="service-apk_builder-dot"' in response.text
    assert "Historique des numérisations" in response.text
    assert "Générer l’APK" in response.text
    assert "/api/v1/apk/build" in response.text
    assert "/dashboard/logs" in response.text


def test_dashboard_logs_page_and_task_log_endpoint(tmp_path):
    input_path = tmp_path / "failed-log-task.png"
    logs_path = tmp_path / "failed-log-task.log"
    input_path.write_bytes(PNG_BYTES)
    complete_logs = "INFO start\n" + ("Audiveris processing detail\n" * 1000)
    logs_path.write_text(complete_logs, encoding="utf-8")
    set_task_state("failed-log-task", {
        "task_id": "failed-log-task",
        "title": "Export test",
        "status": "STATUS_FAILED",
        "error": "Detailed Audiveris export error",
        "file_path": str(input_path),
        "logs_path": str(logs_path),
        "created_at": datetime.now(timezone.utc).isoformat(),
    })

    page = client.get("/dashboard/logs")
    logs = client.get("/api/v1/tasks/failed-log-task/logs")
    received = client.get("/api/v1/tasks/failed-log-task/input")

    assert page.status_code == 200
    assert "Logs complets" in page.text
    assert "Traitements récents" in page.text
    assert "Fichier reçu par le serveur" in page.text
    assert logs.status_code == 200
    assert logs.json()["logs"] == complete_logs
    assert logs.json()["summary"] == main.TASK_FAILURE_SUMMARY
    assert logs.json()["input_preview"]["media_type"] == "image/png"
    assert received.status_code == 200
    assert received.content == PNG_BYTES
    assert received.headers["content-type"] == "image/png"


def test_task_logs_are_available_while_processing_and_without_preview(tmp_path):
    logs_path = tmp_path / "running-log-task.log"
    logs_path.write_text("Audiveris is processing\n", encoding="utf-8")
    set_task_state("running-log-task", {
        "task_id": "running-log-task",
        "status": "STATUS_RUNNING_OMR",
        "logs_path": str(logs_path),
    })
    set_task_state("failed-log-task-without-input", {
        "task_id": "failed-log-task-without-input",
        "status": "STATUS_FAILED",
    })

    assert client.get("/api/v1/tasks/missing/logs").status_code == 404
    running_logs = client.get("/api/v1/tasks/running-log-task/logs")
    assert running_logs.status_code == 200
    assert running_logs.json()["logs"] == "Audiveris is processing\n"
    assert running_logs.json()["input_preview"] is None
    assert client.get("/api/v1/tasks/running-log-task/input").status_code == 409
    assert client.get(
        "/api/v1/tasks/failed-log-task-without-input/input"
    ).status_code == 404


def test_scan_rejects_non_image_upload():
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.png", b"not an image", "image/png")},
    )

    assert response.status_code == 415


def test_scan_rejects_pdf_without_pdf_signature():
    response = client.post(
        "/api/v1/scan",
        files={"file": ("score.pdf", b"not a PDF", "application/pdf")},
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
        stdout = b""

    monkeypatch.setattr("app.omr_engine.subprocess.run", lambda *args, **kwargs: ProcessResult())

    with pytest.raises(OMRProcessingError) as error:
        OMREngine().process_image(str(tmp_path / "score.png"), str(tmp_path))
    assert str(error.value) == "Audiveris failed with exit code 1."
    assert "invalid score" in error.value.diagnostics


def test_omr_engine_passes_pdf_document_to_audiveris(tmp_path, monkeypatch):
    pdf_path = tmp_path / "score.pdf"
    pdf_path.write_bytes(PDF_BYTES)
    output_path = tmp_path / "score.musicxml"
    calls = []

    class ProcessResult:
        returncode = 0
        stderr = b""
        stdout = b""

    def run(command, **_kwargs):
        calls.append(command)
        output_path.write_text("<score-partwise/>")
        return ProcessResult()

    monkeypatch.setattr("app.omr_engine.subprocess.run", run)

    result = OMREngine().process_score(str(pdf_path), str(tmp_path))

    assert result == str(output_path)
    assert calls[0][-1] == str(pdf_path)
    assert "-batch" in calls[0]
    assert "-export" in calls[0]


def test_omr_engine_converts_audiveris_mxl_export_to_musicxml(tmp_path, monkeypatch):
    output_mxl = tmp_path / "score.mxl"
    output_musicxml = tmp_path / "score.musicxml"
    musicxml = b'<?xml version="1.0"?><score-partwise><part-list/></score-partwise>'
    container = (
        b'<?xml version="1.0"?><container><rootfiles>'
        b'<rootfile full-path="scores/score.xml" '
        b'media-type="application/vnd.recordare.musicxml+xml"/>'
        b"</rootfiles></container>"
    )

    class ProcessResult:
        returncode = 0
        stderr = b""
        stdout = b"Score exported to score.mxl"

    def run(_command, **_kwargs):
        with ZipFile(output_mxl, "w", ZIP_DEFLATED) as archive:
            archive.writestr("META-INF/container.xml", container)
            archive.writestr("scores/score.xml", musicxml)
        return ProcessResult()

    monkeypatch.setattr("app.omr_engine.subprocess.run", run)

    result = OMREngine().process_score(
        str(tmp_path / "score.png"), str(tmp_path)
    )

    assert result == str(output_musicxml)
    assert output_musicxml.read_bytes() == musicxml


def test_omr_engine_rejects_mxl_without_musicxml_container(tmp_path, monkeypatch):
    output_mxl = tmp_path / "score.mxl"

    class ProcessResult:
        returncode = 0
        stderr = b""
        stdout = b"Score exported to score.mxl"

    def run(_command, **_kwargs):
        with ZipFile(output_mxl, "w", ZIP_DEFLATED) as archive:
            archive.writestr("score.xml", "<score-partwise/>")
        return ProcessResult()

    monkeypatch.setattr("app.omr_engine.subprocess.run", run)

    with pytest.raises(OMRProcessingError, match="Could not read MusicXML from Audiveris MXL export"):
        OMREngine().process_score(str(tmp_path / "score.png"), str(tmp_path))


def test_omr_engine_includes_audiveris_output_when_musicxml_is_missing(
    tmp_path, monkeypatch
):
    class ProcessResult:
        returncode = 0
        stderr = b"WARN No scores detected"
        stdout = b"Created scores: []"

    monkeypatch.setattr(
        "app.omr_engine.subprocess.run",
        lambda *args, **kwargs: ProcessResult(),
    )

    with pytest.raises(OMRProcessingError) as error:
        OMREngine().process_image(str(tmp_path / "score.png"), str(tmp_path))

    message = str(error.value)
    assert "score.musicxml" in message
    assert "WARN No scores detected" in error.value.diagnostics
    assert "Created scores: []" in error.value.diagnostics


def test_omr_engine_includes_stdout_when_audiveris_stderr_is_empty(tmp_path, monkeypatch):
    class ProcessResult:
        returncode = 1
        stderr = b""
        stdout = b"Could not read the input score"

    monkeypatch.setattr("app.omr_engine.subprocess.run", lambda *args, **kwargs: ProcessResult())

    with pytest.raises(OMRProcessingError) as error:
        OMREngine().process_image(str(tmp_path / "score.png"), str(tmp_path))
    assert "Could not read the input score" in error.value.diagnostics


def test_omr_engine_preserves_all_long_diagnostics(tmp_path, monkeypatch):
    class ProcessResult:
        returncode = 1
        stderr = b"Initial export context\n" + b"x" * 5000
        stdout = b"Final export failure"

    monkeypatch.setattr("app.omr_engine.subprocess.run", lambda *args, **kwargs: ProcessResult())

    with pytest.raises(OMRProcessingError) as error:
        OMREngine().process_image(str(tmp_path / "score.png"), str(tmp_path))

    diagnostics = error.value.diagnostics
    assert "Initial export context" in diagnostics
    assert "Final export failure" in diagnostics
    assert len(diagnostics) > 5000


def test_omr_engine_streams_complete_output_to_log_file(tmp_path, monkeypatch):
    log_path = tmp_path / "score.log"
    expected_output = b"First line\n" + b"detail\n" * 1000
    output_path = tmp_path / "score.musicxml"

    class ProcessResult:
        returncode = 0

    def run(_command, stdout, stderr, **_kwargs):
        assert stderr == subprocess.STDOUT
        stdout.write(expected_output)
        output_path.write_text("<score-partwise/>")
        return ProcessResult()

    monkeypatch.setattr("app.omr_engine.subprocess.run", run)

    result = OMREngine().process_score(
        str(tmp_path / "score.png"), str(tmp_path), str(log_path)
    )

    assert result == str(output_path)
    assert log_path.read_bytes() == expected_output


def test_worker_persists_processing_error(tmp_path, monkeypatch):
    from app.tasks import process_omr_task

    logs_path = tmp_path / "failed-worker-task.log"
    logs_path.write_text("worker log start\n", encoding="utf-8")
    set_task_state("failed-worker-task", {
        "task_id": "failed-worker-task",
        "status": "STATUS_QUEUED",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "logs_path": str(logs_path),
    })

    def fail_processing(*_args):
        raise OMRProcessingError("Audiveris unavailable")

    monkeypatch.setattr("app.tasks.OMREngine.process_score", fail_processing)

    with pytest.raises(OMRProcessingError, match="Audiveris unavailable"):
        process_omr_task.run("failed-worker-task", str(tmp_path / "score.png"), "Test")

    task = get_task_state("failed-worker-task")
    assert task["status"] == "STATUS_FAILED"
    assert task["error"] == "Audiveris unavailable"
    assert task["failed_at"]
    logs = logs_path.read_text(encoding="utf-8")
    assert "Lancement de la reconnaissance Audiveris." in logs
    assert "Échec du traitement : Audiveris unavailable" in logs


def test_worker_explains_audiveris_low_interline_failure(tmp_path, monkeypatch):
    from app.tasks import process_omr_task

    logs_path = tmp_path / "low-interline-task.log"
    logs_path.write_text("Fichier reçu\n", encoding="utf-8")
    set_task_state("low-interline-task", {
        "task_id": "low-interline-task",
        "status": "STATUS_QUEUED",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "logs_path": str(logs_path),
    })
    input_path = tmp_path / "score.png"
    input_path.write_bytes(PNG_BYTES)

    diagnostic = (
        "With a too low interline value of 6 pixels. "
        "Created scores: [] Could not export since transcription did not complete successfully"
    )
    monkeypatch.setattr(
        "app.tasks.OMREngine.process_score",
        lambda *_args: (_ for _ in ()).throw(OMRProcessingError(diagnostic)),
    )

    with pytest.raises(OMRProcessingError, match="too low interline value"):
        process_omr_task.run(
            "low-interline-task", str(input_path), "Test"
        )

    task = get_task_state("low-interline-task")
    assert "6 pixels" in task["error_summary"]
    assert "photo peut être nette" in task["error_summary"]
    assert task["error"] == diagnostic
    assert input_path.read_bytes() == PNG_BYTES
    assert "Lancement de la reconnaissance Audiveris." in logs_path.read_text(
        encoding="utf-8"
    )
    stream = client.get("/api/v1/stream/low-interline-task").text
    assert task["error_summary"] in json.loads(stream[6:])["error"]
    assert client.get(
        "/api/v1/tasks/low-interline-task/logs"
    ).json()["summary"] == task["error_summary"]


def test_worker_summarizes_missing_musicxml_error(tmp_path, monkeypatch):
    from app.tasks import process_omr_task

    logs_path = tmp_path / "missing-musicxml-task.log"
    logs_path.write_text("Fichier reçu\n", encoding="utf-8")
    set_task_state("missing-musicxml-task", {
        "task_id": "missing-musicxml-task",
        "status": "STATUS_QUEUED",
        "logs_path": str(logs_path),
    })
    input_path = tmp_path / "score.png"
    input_path.write_bytes(PNG_BYTES)
    diagnostic = (
        "Audiveris completed without producing a non-empty MusicXML file "
        "at the expected path 'data/temp/score.musicxml'. Output: Created scores: []"
    )
    monkeypatch.setattr(
        "app.tasks.OMREngine.process_score",
        lambda *_args: (_ for _ in ()).throw(OMRProcessingError(diagnostic)),
    )

    with pytest.raises(OMRProcessingError):
        process_omr_task.run(
            "missing-musicxml-task", str(input_path), "Test"
        )

    task = get_task_state("missing-musicxml-task")
    assert "n’a pas généré le fichier MusicXML attendu" in task["error_summary"]
    assert "Created scores: []" in task["error"]
    assert input_path.exists()


def test_worker_keeps_full_logs_for_successful_processing(tmp_path, monkeypatch):
    from app.tasks import process_omr_task

    input_path = tmp_path / "score.png"
    logs_path = tmp_path / "successful-task.log"
    input_path.write_bytes(PNG_BYTES)
    logs_path.write_text("Fichier reçu\n", encoding="utf-8")
    set_task_state("successful-log-task", {
        "task_id": "successful-log-task",
        "status": "STATUS_QUEUED",
        "logs_path": str(logs_path),
    })
    full_audiveris_output = "INFO processing\n" + ("complete detail\n" * 1000)

    def process_score(_engine, _score_path, _output_dir, received_log_path):
        with open(received_log_path, "a", encoding="utf-8") as log_file:
            log_file.write(full_audiveris_output)
        return "score.musicxml"

    monkeypatch.setattr("app.tasks.OMREngine.process_score", process_score)
    monkeypatch.setattr(
        "app.tasks.convert_musicxml_to_midi",
        lambda *_args: "successful-task.mid",
    )

    task = process_omr_task.run(
        "successful-log-task", str(input_path), "Successful score"
    )

    assert task["status"] == "STATUS_COMPLETED"
    assert not input_path.exists()
    logs_response = client.get("/api/v1/tasks/successful-log-task/logs")
    logs = logs_response.json()["logs"]
    assert logs_response.status_code == 200
    assert full_audiveris_output in logs
    assert "Traitement terminé avec succès." in logs
    assert "Audiveris" not in (logs_response.json()["summary"] or "")


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


def test_musicxml_conversion_uses_partitura_score_midi_export(tmp_path, monkeypatch):
    partitura = ModuleType("partitura")
    score = object()
    midi_path = tmp_path / "score.mid"
    midi_content = (
        b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60"
        b"MTrk\x00\x00\x00\x04\x00\xff\x2f\x00"
    )
    saved_scores = []

    partitura.load_musicxml = lambda _path: score

    def save_score_midi(received_score, output_path):
        saved_scores.append(received_score)
        with open(output_path, "wb") as midi_file:
            midi_file.write(midi_content)

    partitura.save_score_midi = save_score_midi
    monkeypatch.setitem(sys.modules, "partitura", partitura)

    result = convert_musicxml_to_midi(
        str(tmp_path / "score.musicxml"), str(midi_path)
    )

    assert result == str(midi_path)
    assert saved_scores == [score]
    assert midi_path.read_bytes() == midi_content


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
    assert "dashboard" in response.text
    assert "timed out" not in response.text
    assert get_task_state("stalled-task")["error"] == "Image processing timed out after 0 seconds."


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


def test_musicxml_result_returns_the_completed_musicxml_file(tmp_path):
    musicxml_path = tmp_path / "result.musicxml"
    musicxml_path.write_text("<score-partwise/>", encoding="utf-8")
    set_task_state("completed-musicxml-task", {
        "status": "STATUS_COMPLETED",
        "musicxml_path": str(musicxml_path),
    })

    response = client.get("/api/v1/result/completed-musicxml-task/musicxml")

    assert response.status_code == 200
    assert response.content == b"<score-partwise/>"
    assert response.headers["content-type"].startswith(
        "application/vnd.recordare.musicxml+xml"
    )


def test_musicxml_result_rejects_missing_or_incomplete_tasks(tmp_path):
    set_task_state("queued-musicxml-task", {"status": "STATUS_QUEUED"})
    set_task_state("broken-musicxml-task", {
        "status": "STATUS_COMPLETED",
        "musicxml_path": str(tmp_path / "missing.musicxml"),
    })

    assert client.get(
        "/api/v1/result/unknown-musicxml-task/musicxml"
    ).status_code == 404
    assert client.get(
        "/api/v1/result/queued-musicxml-task/musicxml"
    ).status_code == 409
    assert client.get(
        "/api/v1/result/broken-musicxml-task/musicxml"
    ).status_code == 500


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
    assert data["today_scans"] == 1
    assert data["avg_processing_time_sec"] == 12.0


def test_stats_exclude_running_tasks_from_success_rate_and_hide_internal_paths():
    now = datetime.now(timezone.utc).isoformat()
    set_task_state("completed", {
        "task_id": "completed",
        "status": "STATUS_COMPLETED",
        "title": "Good score",
        "created_at": now,
        "file_path": "/private/upload.png",
    })
    set_task_state("failed", {
        "task_id": "failed",
        "status": "STATUS_FAILED",
        "error": "private detailed diagnostic",
        "created_at": now,
    })
    set_task_state("queued", {
        "task_id": "queued",
        "status": "STATUS_QUEUED",
        "created_at": now,
    })

    response = client.get("/api/v1/stats")
    data = response.json()

    assert response.status_code == 200
    assert data["success_rate"] == 50.0
    assert data["running_scans"] == 1
    assert data["recent_tasks"][0]["task_id"] == "queued"
    failed_task = next(task for task in data["recent_tasks"] if task["task_id"] == "failed")
    assert failed_task["error_summary"] == main.TASK_FAILURE_SUMMARY
    assert "error" not in failed_task
    assert all("file_path" not in task for task in data["recent_tasks"])


def test_apk_build_routes_proxy_to_builder(monkeypatch):
    monkeypatch.setattr(main, "API_KEY", "configured-test-key")
    monkeypatch.setattr(main, "MELODISCAN_HOST", "192.168.1.25")
    calls = []

    async def builder_request(method, path):
        calls.append((method, path))
        status = 202 if method == "POST" else 200
        return (status, {"build_id": "a9bcedd0-cb64-4c62-9b2d-5d06c0e7f32a", "status": "building"})

    monkeypatch.setattr(main, "request_apk_builder", builder_request)

    started = client.post("/api/v1/apk/build", headers={"X-API-Key": "configured-test-key"})
    status = client.get("/api/v1/apk/status", headers={"X-API-Key": "configured-test-key"})
    fingerprint = client.get("/api/v1/apk/fingerprint", headers={"X-API-Key": "configured-test-key"})
    progress = client.get(
        "/api/v1/apk/build/a9bcedd0-cb64-4c62-9b2d-5d06c0e7f32a",
        headers={"X-API-Key": "configured-test-key"},
    )

    assert started.status_code == 202
    assert status.status_code == 200
    assert fingerprint.status_code == 200
    assert progress.status_code == 200
    assert calls == [
        ("POST", "/build"),
        ("GET", "/status"),
        ("GET", "/fingerprint"),
        ("GET", "/build/a9bcedd0-cb64-4c62-9b2d-5d06c0e7f32a"),
    ]


def test_apk_build_requires_deployment_configuration(monkeypatch):
    monkeypatch.setattr(main, "API_KEY", "")
    monkeypatch.setattr(main, "MELODISCAN_HOST", "")

    response = client.post("/api/v1/apk/build")

    assert response.status_code == 503
    assert "requires a configured API key" in response.json()["detail"]
