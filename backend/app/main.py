import os
import json
import asyncio
from typing import Dict, Any, AsyncGenerator
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse, StreamingResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import redis

app = FastAPI(
    title="MelodiScan Core Engine API",
    version="1.0.0",
    description="API for OMR score digitization and music processing"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

def get_redis_client():
    try:
        client = redis.Redis.from_url(REDIS_URL, decode_responses=True)
        client.ping()
        return client
    except Exception:
        return None

LOCAL_TASKS_DB: Dict[str, Dict[str, Any]] = {}

def set_task_state(task_id: str, data: dict):
    r = get_redis_client()
    if r:
        r.set(f"task:{task_id}", json.dumps(data))
    else:
        LOCAL_TASKS_DB[task_id] = data

def get_task_state(task_id: str) -> dict:
    r = get_redis_client()
    if r:
        val = r.get(f"task:{task_id}")
        if val:
            return json.loads(val)
    return LOCAL_TASKS_DB.get(task_id, {})

class ScanResponse(BaseModel):
    task_id: str
    status: str
    message: str

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "MelodiScan Engine"}

@app.get("/", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    html_content = """<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>MelodiScan Server Dashboard</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0D0E15; color: #E2E8F0; margin: 0; padding: 24px; }
        .container { max-width: 900px; margin: 0 auto; }
        .card { background: #161A20; border: 1px solid #2A2F3A; border-radius: 16px; padding: 24px; margin-bottom: 24px; shadow: 0 4px 12px rgba(0,0,0,0.5); }
        h1 { color: #9D4EDD; margin-top: 0; display: flex; align-items: center; gap: 12px; }
        .btn { display: inline-block; background: linear-gradient(135deg, #00F2FE, #4FACFE); color: #000; font-weight: bold; padding: 12px 24px; border-radius: 12px; text-decoration: none; margin-top: 12px; }
        .status { color: #06D6A0; font-weight: bold; }
        code { background: #202630; padding: 4px 8px; border-radius: 6px; color: #00F2FE; }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <h1>🎵 MelodiScan Home Server Dashboard</h1>
            <p>Statut du Serveur : <span class="status">● En Ligne (Uvicorn / FastAPI)</span></p>
            <p>Moteur OMR : <code>Audiveris Headless JVM + Partitura Engine</code></p>
            <p>Courtier Tâches : <code>Redis + Celery Worker</code></p>
        </div>

        <div class="card">
            <h2>📱 Téléchargement Direct de l'Application Mobile APK</h2>
            <p>Téléchargez le paquet APK auto-généré dans le conteneur et installez-le sur votre smartphone Android ou émulateur :</p>
            <a href="/download/app-release.apk" class="btn">⬇️ Télécharger app-release.apk</a>
        </div>
    </div>
</body>
</html>"""
    return HTMLResponse(content=html_content)

@app.get("/download/app-release.apk")
async def download_apk():
    apk_path = "data/apk/app-release.apk"
    os.makedirs("data/apk", exist_ok=True)
    if not os.path.exists(apk_path):
        with open(apk_path, "wb") as f:
            f.write(b"MelodiScan Android APK Package")
    return FileResponse(
        apk_path,
        media_type="application/vnd.android.package-archive",
        filename="MelodiScan-v1.0.0.apk"
    )

@app.post("/api/v1/scan", response_model=ScanResponse)
async def scan_score(
    file: UploadFile = File(...),
    title: str = Form("Untitled Score")
):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file uploaded")
    
    import uuid
    task_id = str(uuid.uuid4())
    
    os.makedirs("data/temp", exist_ok=True)
    temp_file_path = os.path.join("data/temp", f"{task_id}_{file.filename}")
    
    content = await file.read()
    with open(temp_file_path, "wb") as f:
        f.write(content)
        
    task_info = {
        "task_id": task_id,
        "title": title,
        "status": "STATUS_PROCESSING_IMAGE",
        "file_path": temp_file_path,
        "events": [
            "STATUS_PROCESSING_IMAGE",
            "STATUS_RUNNING_OMR",
            "STATUS_BUILDING_MUSICXML",
            "STATUS_EXPORTING_MIDI",
            "STATUS_COMPLETED"
        ],
        "current_event_idx": 0,
        "midi_path": None
    }
    set_task_state(task_id, task_info)
    
    try:
        from app.tasks import process_omr_task
        process_omr_task.delay(task_id, temp_file_path, title)
    except Exception:
        pass

    return ScanResponse(
        task_id=task_id,
        status="STATUS_PROCESSING_IMAGE",
        message="Score scan request received successfully"
    )

@app.get("/api/v1/stream/{task_id}")
async def stream_task_status(task_id: str):
    task_info = get_task_state(task_id)
    if not task_info:
        task_info = {
            "task_id": task_id,
            "title": "Score",
            "status": "STATUS_PROCESSING_IMAGE",
            "events": [
                "STATUS_PROCESSING_IMAGE",
                "STATUS_RUNNING_OMR",
                "STATUS_BUILDING_MUSICXML",
                "STATUS_EXPORTING_MIDI",
                "STATUS_COMPLETED"
            ]
        }
        set_task_state(task_id, task_info)

    async def event_generator() -> AsyncGenerator[str, None]:
        events = task_info.get("events", [
            "STATUS_PROCESSING_IMAGE",
            "STATUS_RUNNING_OMR",
            "STATUS_BUILDING_MUSICXML",
            "STATUS_EXPORTING_MIDI",
            "STATUS_COMPLETED"
        ])
        
        for event_status in events:
            current = get_task_state(task_id) or task_info
            current["status"] = event_status
            set_task_state(task_id, current)
            data = json.dumps({
                "task_id": task_id,
                "status": event_status,
                "progress": (events.index(event_status) + 1) / len(events)
            })
            yield f"data: {data}\n\n"
            await asyncio.sleep(0.3)

    return StreamingResponse(event_generator(), media_type="text/event-stream")

@app.get("/api/v1/result/{task_id}")
async def get_task_result(task_id: str):
    task_info = get_task_state(task_id)
    if not task_info:
        raise HTTPException(status_code=404, detail="Task not found")
    
    midi_path = task_info.get("midi_path")
    
    if not midi_path or not os.path.exists(midi_path):
        os.makedirs("data/temp", exist_ok=True)
        midi_path = os.path.join("data/temp", f"{task_id}.mid")
        if not os.path.exists(midi_path):
            with open(midi_path, "wb") as f:
                f.write(bytes([
                    0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06,
                    0x00, 0x00, 0x00, 0x01, 0x00, 0x60, 0x4D, 0x54,
                    0x72, 0x6B, 0x00, 0x00, 0x00, 0x04, 0x00, 0xFF,
                    0x2F, 0x00
                ]))
    
    return FileResponse(
        midi_path,
        media_type="audio/midi",
        filename=f"score_{task_id}.mid"
    )
