import os
import json
import asyncio
import base64
import binascii
import hmac
import logging
import shutil
import statistics
from datetime import datetime, timezone
from typing import Dict, Any, AsyncGenerator
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import FileResponse, StreamingResponse, HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import redis

app = FastAPI(
    title="MelodiScan Core Engine API",
    version="1.0.0",
    description="API for OMR score digitization and music processing"
)

logger = logging.getLogger(__name__)
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
AUDIVERIS_EXECUTABLE = os.getenv("AUDIVERIS_EXECUTABLE", "audiveris")
API_KEY = os.getenv("API_KEY", "")
DASHBOARD_USERNAME = os.getenv("DASHBOARD_USERNAME", "")
DASHBOARD_PASSWORD = os.getenv("DASHBOARD_PASSWORD", "")
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", 20 * 1024 * 1024))
TASK_TIMEOUT_SECONDS = int(os.getenv("TASK_TIMEOUT_SECONDS", 600))
CORS_ALLOW_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOW_ORIGINS", "").split(",")
    if origin.strip()
]
if bool(DASHBOARD_USERNAME) != bool(DASHBOARD_PASSWORD):
    raise RuntimeError("DASHBOARD_USERNAME and DASHBOARD_PASSWORD must both be configured.")

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOW_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def authenticate_request(request: Request, call_next):
    path = request.url.path
    if request.method != "OPTIONS" and (path.startswith("/api/") or path.startswith("/download/")):
        provided_key = request.headers.get("X-API-Key", "")
        if API_KEY and not hmac.compare_digest(provided_key, API_KEY) and not _has_dashboard_credentials(
            request.headers.get("Authorization", "")
        ):
            return JSONResponse(
                status_code=401,
                content={"detail": "A valid API key is required."},
                headers={"WWW-Authenticate": "ApiKey"},
            )

    if path in {"/", "/dashboard"} and DASHBOARD_USERNAME and not _has_dashboard_credentials(
        request.headers.get("Authorization", "")
    ):
        return JSONResponse(
            status_code=401,
            content={"detail": "Dashboard credentials are required."},
            headers={"WWW-Authenticate": 'Basic realm="MelodiScan Dashboard"'},
        )

    return await call_next(request)


def _has_dashboard_credentials(authorization: str) -> bool:
    if not DASHBOARD_USERNAME:
        return False
    try:
        scheme, encoded_credentials = authorization.split(" ", 1)
        credentials = base64.b64decode(encoded_credentials, validate=True).decode("utf-8")
        username, password = credentials.split(":", 1)
    except (ValueError, UnicodeDecodeError, binascii.Error):
        return False
    return (
        scheme.lower() == "basic"
        and hmac.compare_digest(username, DASHBOARD_USERNAME)
        and hmac.compare_digest(password, DASHBOARD_PASSWORD)
    )


def get_redis_client():
    try:
        client = redis.Redis.from_url(REDIS_URL, decode_responses=True)
        client.ping()
        return client
    except redis.RedisError:
        logger.warning("Redis is unavailable; task state will not be shared with workers.")
        return None


LOCAL_TASKS_DB: Dict[str, Dict[str, Any]] = {}


def set_task_state(task_id: str, data: dict):
    r = get_redis_client()
    if r:
        r.set(f"task:{task_id}", json.dumps(data))
        r.sadd("task_ids", task_id)
    else:
        LOCAL_TASKS_DB[task_id] = data

def get_task_state(task_id: str) -> dict:
    r = get_redis_client()
    if r:
        val = r.get(f"task:{task_id}")
        if val:
            return json.loads(val)
    return LOCAL_TASKS_DB.get(task_id, {})

def get_all_tasks() -> list:
    r = get_redis_client()
    tasks = []
    if r:
        task_ids = r.smembers("task_ids")
        for tid in task_ids:
            value = r.get(f"task:{tid}")
            if value:
                task = json.loads(value)
                tasks.append(task)
    else:
        tasks = list(LOCAL_TASKS_DB.values())
    return sorted(tasks, key=lambda task: task.get("created_at", ""))


def _parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


class ScanResponse(BaseModel):
    task_id: str
    status: str
    message: str


@app.get("/health")
async def health_check():
    redis_online = get_redis_client() is not None
    audiveris_available = shutil.which(AUDIVERIS_EXECUTABLE) is not None
    worker_online = False
    if redis_online:
        try:
            from app.tasks import celery_app

            worker_online = bool(await asyncio.to_thread(celery_app.control.ping, timeout=1))
        except Exception:
            logger.exception("Could not check Celery worker health.")

    dependencies = {
        "redis": redis_online,
        "celery_worker": worker_online,
        "audiveris": audiveris_available,
    }
    status = "ok" if all(dependencies.values()) else "degraded"
    return JSONResponse(
        status_code=200 if status == "ok" else 503,
        content={
            "status": status,
            "service": "MelodiScan Engine",
            "dependencies": dependencies,
        },
    )


@app.get("/api/v1/stats")
async def get_system_stats():
    tasks = get_all_tasks()
    total_scans = len(tasks)
    completed_scans = sum(1 for t in tasks if t.get("status") == "STATUS_COMPLETED")
    failed_scans = sum(1 for t in tasks if t.get("status") == "STATUS_FAILED")
    running_scans = sum(
        1 for t in tasks
        if t.get("status") in {
            "STATUS_QUEUED",
            "STATUS_PROCESSING_IMAGE",
            "STATUS_RUNNING_OMR",
            "STATUS_BUILDING_MUSICXML",
            "STATUS_EXPORTING_MIDI",
        }
    )
    success_rate = (completed_scans / total_scans * 100) if total_scans else 0.0
    durations = []
    for task in tasks:
        started = _parse_timestamp(task.get("created_at"))
        completed = _parse_timestamp(task.get("completed_at"))
        if started and completed and completed >= started:
            durations.append((completed - started).total_seconds())

    redis_online = get_redis_client() is not None

    return {
        "total_scans": total_scans,
        "completed_scans": completed_scans,
        "failed_scans": failed_scans,
        "running_scans": running_scans,
        "success_rate": round(success_rate, 1),
        "avg_processing_time_sec": round(statistics.mean(durations), 2) if durations else None,
        "redis_online": redis_online,
        "primary_omr_engine": "Audiveris v5.10.0",
        "recent_tasks": tasks[-5:] if tasks else [],
    }

@app.get("/", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    html_content = """<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MelodiScan Enterprise Dashboard</title>
    <style>
        :root {
            --bg: #0D0E15;
            --surface: #161A20;
            --surface-elevated: #202630;
            --primary: #9D4EDD;
            --secondary: #06D6A0;
            --accent-cyan: #00F2FE;
            --text: #F8F9FA;
            --text-muted: #94A3B8;
            --border: #2A2F3A;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 32px 16px;
        }
        .container {
            max-width: 1100px;
            margin: 0 auto;
        }
        .header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 32px;
            padding-bottom: 20px;
            border-bottom: 1px solid var(--border);
        }
        .logo-title {
            display: flex;
            align-items: center;
            gap: 16px;
        }
        h1 {
            font-size: 26px;
            margin: 0;
            background: linear-gradient(135deg, var(--primary), var(--accent-cyan));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 32px;
        }
        .card {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 22px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.4);
            transition: transform 0.2s;
        }
        .card:hover {
            transform: translateY(-2px);
        }
        .metric-title {
            color: var(--text-muted);
            font-size: 13px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .metric-value {
            font-size: 32px;
            font-weight: 800;
            color: var(--secondary);
            margin-top: 10px;
        }
        .btn {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            background: linear-gradient(135deg, var(--accent-cyan), #4FACFE);
            color: #000;
            font-weight: bold;
            padding: 14px 28px;
            border-radius: 12px;
            text-decoration: none;
            transition: opacity 0.2s, transform 0.2s;
        }
        .btn:hover {
            opacity: 0.9;
            transform: translateY(-2px);
        }
        .badge {
            display: inline-block;
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            background: rgba(6, 214, 160, 0.15);
            color: var(--secondary);
            border: 1px solid rgba(6, 214, 160, 0.3);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
        }
        th, td {
            text-align: left;
            padding: 14px;
            border-bottom: 1px solid var(--border);
        }
        th {
            color: var(--text-muted);
            font-size: 12px;
            text-transform: uppercase;
        }
        code {
            background: var(--surface-elevated);
            padding: 4px 8px;
            border-radius: 6px;
            color: var(--accent-cyan);
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo-title">
                <svg width="48" height="48" viewBox="0 0 512 512">
                    <rect width="512" height="512" rx="115" fill="#0D0E15"/>
                    <g stroke="#00F2FE" stroke-width="20" fill="none">
                        <path d="M 116 176 L 116 136 Q 116 116 136 116 L 176 116"/>
                        <path d="M 336 116 L 376 116 Q 396 116 396 136 L 396 176"/>
                        <path d="M 116 336 L 116 376 Q 116 396 136 396 L 176 396"/>
                        <path d="M 336 396 L 376 396 Q 396 396 396 376 L 396 336"/>
                    </g>
                    <g fill="#9D4EDD">
                        <rect x="160" y="226" width="18" height="60" rx="9"/>
                        <rect x="196" y="186" width="18" height="140" rx="9"/>
                        <rect x="232" y="156" width="18" height="200" rx="9"/>
                        <rect x="268" y="136" width="18" height="240" rx="9" fill="#00F2FE"/>
                        <rect x="304" y="176" width="18" height="160" rx="9"/>
                        <rect x="340" y="206" width="18" height="100" rx="9"/>
                    </g>
                </svg>
                <div>
                    <h1>MelodiScan Enterprise</h1>
                    <div style="color: var(--text-muted); font-size: 14px;">Tableau de Bord & Statistiques OMR Temps Réel</div>
                </div>
            </div>
            <span class="badge" id="server-badge">● SERVEUR CONNECTÉ</span>
        </div>

        <div class="grid">
            <div class="card">
                <div class="metric-title">Partitions Numérisées</div>
                <div class="metric-value" id="stat-total">0</div>
                <div style="font-size: 12px; margin-top: 6px; color: var(--text-muted);">Total Demandes OMR</div>
            </div>

            <div class="card">
                <div class="metric-title">Taux de Succès</div>
                <div class="metric-value" style="color: #00F2FE;" id="stat-rate">100%</div>
                <div style="font-size: 12px; margin-top: 6px; color: var(--text-muted);">Traitements terminés sans erreur</div>
            </div>

            <div class="card">
                <div class="metric-title">Temps Moyen Traitement</div>
                <div class="metric-value" style="color: var(--primary);" id="stat-time">—</div>
                <div style="font-size: 12px; margin-top: 6px; color: var(--text-muted);">Mesuré depuis les tâches terminées</div>
            </div>

            <div class="card">
                <div class="metric-title">Redis</div>
                <div class="metric-value" style="color: #06D6A0;" id="stat-redis">Vérification...</div>
                <div style="font-size: 12px; margin-top: 6px; color: var(--text-muted);">Stockage des tâches</div>
            </div>
        </div>

        <div class="card">
            <h2>📜 Dernières Tâches Numérisées (Live Tasks Feed)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Task ID</th>
                        <th>Titre Score</th>
                        <th>Statut OMR</th>
                        <th>Fichier Synthèse</th>
                    </tr>
                </thead>
                <tbody id="tasks-table-body">
                    <tr>
                        <td colspan="4" style="color: var(--text-muted); text-align: center;">Chargement des statistiques...</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <script>
        async function fetchStats() {
            try {
                const res = await fetch('/api/v1/stats');
                if (!res.ok) throw new Error('Impossible de charger les statistiques.');
                const data = await res.json();

                document.getElementById('stat-total').innerText = data.total_scans;
                document.getElementById('stat-rate').innerText = data.success_rate + '%';
                document.getElementById('stat-time').innerText =
                    data.avg_processing_time_sec == null ? '—' : data.avg_processing_time_sec + 's';
                document.getElementById('stat-redis').innerText = data.redis_online ? 'En ligne' : 'Indisponible';

                const tbody = document.getElementById('tasks-table-body');
                if (data.recent_tasks && data.recent_tasks.length > 0) {
                    const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({
                        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
                    })[character]);
                    tbody.innerHTML = data.recent_tasks.map(t => `
                        <tr>
                            <td><code>${escapeHtml((t.task_id || '').substring(0, 12))}...</code></td>
                            <td><strong>${escapeHtml(t.title || 'Untitled')}</strong></td>
                            <td><span class="badge">${escapeHtml(t.status)}</span>${t.error ? `<div>${escapeHtml(t.error)}</div>` : ''}</td>
                            <td>${t.status === 'STATUS_COMPLETED'
                                ? `<a href="/api/v1/result/${encodeURIComponent(t.task_id)}" style="color: #00F2FE;">Télécharger MIDI</a>`
                                : '—'}</td>
                        </tr>
                    `).join('');
                } else {
                    tbody.innerHTML = '<tr><td colspan="4" style="color: var(--text-muted); text-align: center;">Aucune tâche en cours pour le moment. Envoyez une partition via l&apos;application mobile.</td></tr>';
                }
            } catch (e) {
                console.error('Stats update error', e);
            }
        }

        async function fetchHealth() {
            const badge = document.getElementById('server-badge');
            try {
                const response = await fetch('/health');
                const data = await response.json();
                badge.innerText = data.status === 'ok' ? '● SERVICES DISPONIBLES' : '● SERVICE DÉGRADÉ';
            } catch (_) {
                badge.innerText = '● SERVEUR INDISPONIBLE';
            }
        }

        fetchStats();
        fetchHealth();
        setInterval(fetchStats, 3000);
        setInterval(fetchHealth, 5000);
    </script>
</body>
</html>"""
    return HTMLResponse(content=html_content)

@app.get("/download/app-release.apk")
async def download_apk():
    apk_path = "data/apk/app-release.apk"
    if not os.path.exists(apk_path):
        compiled_apk = "mobile/build/app/outputs/flutter-apk/app-release.apk"
        if os.path.exists(compiled_apk):
            apk_path = compiled_apk
        else:
            raise HTTPException(status_code=404, detail="No release APK is available on this server.")

    return FileResponse(
        apk_path,
        media_type="application/vnd.android.package-archive",
        filename="MelodiScan-v1.0.0.apk"
    )

@app.post("/api/v1/scan", response_model=ScanResponse)
async def scan_score(
    file: UploadFile = File(...),
    title: str = Form("Untitled Score", max_length=200)
):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file uploaded")

    content = await file.read(MAX_UPLOAD_BYTES + 1)
    await file.close()
    if not content:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"Image exceeds the {MAX_UPLOAD_BYTES}-byte upload limit.")

    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        extension = ".png"
    elif content.startswith(b"\xff\xd8\xff"):
        extension = ".jpg"
    elif len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        extension = ".webp"
    else:
        raise HTTPException(status_code=415, detail="Only valid PNG, JPEG, or WebP images are supported.")

    import uuid
    task_id = str(uuid.uuid4())
    os.makedirs("data/temp", exist_ok=True)
    temp_file_path = os.path.join("data/temp", f"{task_id}{extension}")

    with open(temp_file_path, "wb") as f:
        f.write(content)

    now = datetime.now(timezone.utc).isoformat()
    task_info = {
        "task_id": task_id,
        "title": title.strip() or "Untitled Score",
        "status": "STATUS_QUEUED",
        "created_at": now,
        "file_path": temp_file_path,
        "midi_path": None
    }
    set_task_state(task_id, task_info)

    try:
        from app.tasks import process_omr_task
        process_omr_task.delay(task_id, temp_file_path, title)
    except Exception as exc:
        logger.exception("Could not enqueue scan task %s.", task_id)
        task_info.update({
            "status": "STATUS_FAILED",
            "error": f"Could not queue image processing: {exc}",
            "failed_at": datetime.now(timezone.utc).isoformat(),
        })
        set_task_state(task_id, task_info)
        try:
            os.remove(temp_file_path)
        except OSError:
            logger.exception("Could not remove rejected upload for task %s.", task_id)
        raise HTTPException(status_code=503, detail="Image processing service is unavailable.") from exc

    return ScanResponse(
        task_id=task_id,
        status="STATUS_QUEUED",
        message="Score scan request received successfully"
    )


@app.get("/api/v1/stream/{task_id}")
async def stream_task_status(task_id: str):
    if not get_task_state(task_id):
        raise HTTPException(status_code=404, detail="Task not found")

    async def event_generator() -> AsyncGenerator[str, None]:
        last_status = None
        loop = asyncio.get_running_loop()
        started = loop.time()
        last_heartbeat = started
        progress_by_status = {
            "STATUS_QUEUED": 0.0,
            "STATUS_PROCESSING_IMAGE": 0.1,
            "STATUS_RUNNING_OMR": 0.4,
            "STATUS_BUILDING_MUSICXML": 0.65,
            "STATUS_EXPORTING_MIDI": 0.85,
            "STATUS_COMPLETED": 1.0,
        }

        while True:
            task_info = get_task_state(task_id)
            if not task_info:
                task_info = {
                    "status": "STATUS_FAILED",
                    "error": "Task state is no longer available.",
                }
            current_status = task_info.get("status", "STATUS_QUEUED")

            if current_status != last_status:
                last_status = current_status
                data = json.dumps({
                    "task_id": task_id,
                    "status": current_status,
                    "progress": progress_by_status.get(current_status, 0.0),
                    "error": task_info.get("error"),
                })
                yield f"data: {data}\n\n"

            if current_status in {"STATUS_COMPLETED", "STATUS_FAILED"}:
                break

            now = loop.time()
            if now - started >= TASK_TIMEOUT_SECONDS:
                task_info.update({
                    "status": "STATUS_FAILED",
                    "error": f"Image processing timed out after {TASK_TIMEOUT_SECONDS} seconds.",
                    "failed_at": datetime.now(timezone.utc).isoformat(),
                })
                set_task_state(task_id, task_info)
                data = json.dumps({
                    "task_id": task_id,
                    "status": "STATUS_FAILED",
                    "progress": 0.0,
                    "error": task_info["error"],
                })
                yield f"data: {data}\n\n"
                break

            if now - last_heartbeat >= 15:
                yield ": keep-alive\n\n"
                last_heartbeat = now
            await asyncio.sleep(0.4)

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/api/v1/result/{task_id}")
async def get_task_result(task_id: str):
    task_info = get_task_state(task_id)
    if not task_info:
        raise HTTPException(status_code=404, detail="Task not found")

    if task_info.get("status") == "STATUS_FAILED":
        raise HTTPException(status_code=422, detail=task_info.get("error", "Image processing failed."))
    if task_info.get("status") != "STATUS_COMPLETED":
        raise HTTPException(status_code=409, detail="Image processing has not completed.")

    midi_path = task_info.get("midi_path")
    if not midi_path or not os.path.isfile(midi_path) or os.path.getsize(midi_path) == 0:
        raise HTTPException(status_code=500, detail="Completed task has no valid MIDI result.")

    return FileResponse(
        midi_path,
        media_type="audio/midi",
        filename=f"score_{task_id}.mid"
    )
