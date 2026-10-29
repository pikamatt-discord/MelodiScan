import os
import sys
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.main import app, set_task_state, get_task_state
from app.omr_engine import OMREngine, convert_musicxml_to_midi

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

def test_scan_score():
    os.makedirs("data/temp", exist_ok=True)
    test_file_path = "data/temp/test_score.png"
    with open(test_file_path, "wb") as f:
        f.write(b"fake image data")

    with open(test_file_path, "rb") as f:
        response = client.post(
            "/api/v1/scan",
            files={"file": ("test_score.png", f, "image/png")},
            data={"title": "Test Piece"}
        )

    assert response.status_code == 200
    data = response.json()
    assert "task_id" in data
    assert data["status"] == "STATUS_PROCESSING_IMAGE"

def test_omr_engine_fallback():
    engine = OMREngine(primary_engine="non_existent")
    output_dir = "data/temp"
    os.makedirs(output_dir, exist_ok=True)
    xml_path, conf = engine.process_image("data/temp/test_score.png", output_dir)
    assert os.path.exists(xml_path)
    assert conf > 0.0

    midi_path = os.path.join(output_dir, "test_out.mid")
    convert_musicxml_to_midi(xml_path, midi_path)
    assert os.path.exists(midi_path)

def test_get_result():
    task_id = "test_task_123"
    set_task_state(task_id, {
        "task_id": task_id,
        "title": "Test Task",
        "status": "STATUS_COMPLETED"
    })
    response = client.get(f"/api/v1/result/{task_id}")
    assert response.status_code == 200
    assert response.headers["content-type"] in ["audio/midi", "application/octet-stream", "audio/sp-midi"]
