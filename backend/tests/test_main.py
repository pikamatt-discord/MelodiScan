import io
import os
from PIL import Image, ImageDraw
from fastapi.testclient import TestClient
from backend.main import app, analyze_image_and_extract_notes

client = TestClient(app)


def create_dummy_image(format_name="png"):
    """Helper to create a multi-staff score image in memory."""
    file = io.BytesIO()
    image = Image.new("RGB", (300, 200), color="white")
    draw = ImageDraw.Draw(image)
    
    # Draw Staff Line Band 1
    for y in [30, 45, 60, 75, 90]:
        draw.line([(20, y), (280, y)], fill="black", width=2)
        
    # Draw Staff Line Band 2
    for y in [120, 135, 150, 165, 180]:
        draw.line([(20, y), (280, y)], fill="black", width=2)
        
    # Draw noteheads with varied widths (rhythms)
    for x, y in [(50, 45), (100, 60), (150, 135), (200, 150)]:
        draw.ellipse([(x - 8, y - 6), (x + 8, y + 6)], fill="black")
        
    image.save(file, format_name)
    file.seek(0)
    return file


def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "MelodiScan API is running"}


def test_analyze_image_and_extract_notes():
    img_bytes = create_dummy_image("png")
    temp_path = "/tmp/test_score_image_rhythm.png"
    with open(temp_path, "wb") as f:
        f.write(img_bytes.getbuffer())
        
    extracted = analyze_image_and_extract_notes(temp_path)
    assert len(extracted) >= 3
    for pitch, duration in extracted:
        assert isinstance(pitch, str)
        assert isinstance(duration, float)
        assert duration in [0.5, 1.0, 2.0, 4.0]
        
    if os.path.exists(temp_path):
        os.remove(temp_path)


def test_scan_partition_jpeg_success():
    img_bytes = create_dummy_image("jpeg")
    response = client.post(
        "/scan",
        files={"file": ("test.jpg", img_bytes, "image/jpeg")}
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/midi"
    assert len(response.content) > 0


def test_scan_partition_png_success():
    img_bytes = create_dummy_image("png")
    response = client.post(
        "/scan",
        files={"file": ("test.png", img_bytes, "image/png")}
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/midi"
    assert len(response.content) > 0


def test_scan_partition_octet_stream_image_fallback_success():
    img_bytes = create_dummy_image("png")
    response = client.post(
        "/scan",
        files={"file": ("test.png", img_bytes, "application/octet-stream")}
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/midi"
    assert len(response.content) > 0


def test_scan_partition_invalid_corrupted_image():
    corrupted_bytes = io.BytesIO(b"Not a real jpeg or png header")
    response = client.post(
        "/scan",
        files={"file": ("corrupted.png", corrupted_bytes, "image/png")}
    )
    assert response.status_code == 422
    assert "Impossible de lire la partition" in response.json()["detail"]
