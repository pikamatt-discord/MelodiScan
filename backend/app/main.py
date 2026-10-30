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
import httpx
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
APK_BUILDER_URL = os.getenv("APK_BUILDER_URL", "http://melodiscan-apk-builder:8090")
MELODISCAN_HOST = os.getenv("MELODISCAN_HOST", "")
SCORE_MEDIA_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}
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

    if (path == "/" or path.startswith("/dashboard")) and DASHBOARD_USERNAME and not _has_dashboard_credentials(
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
TASK_FAILURE_SUMMARY = "Échec du traitement. Consultez les diagnostics dans le dashboard."


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


async def request_apk_builder(method: str, path: str) -> tuple[int, dict]:
    headers = {"X-API-Key": API_KEY} if API_KEY else {}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.request(
                method,
                f"{APK_BUILDER_URL}{path}",
                headers=headers,
            )
    except httpx.RequestError as exc:
        logger.warning("APK builder request failed: %s", exc)
        raise HTTPException(status_code=503, detail="APK builder is unavailable.") from exc

    try:
        payload = response.json()
    except ValueError as exc:
        logger.error("APK builder returned a non-JSON response (HTTP %s).", response.status_code)
        raise HTTPException(status_code=502, detail="APK builder returned an invalid response.") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="APK builder returned an invalid response.")
    return response.status_code, payload


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

    try:
        builder_status, builder = await request_apk_builder("GET", "/health")
        apk_builder_online = builder_status == 200 and builder.get("status") == "ok"
    except HTTPException as exc:
        logger.warning("APK builder health check failed: %s", exc.detail)
        apk_builder_online = False

    dependencies = {
        "redis": redis_online,
        "celery_worker": worker_online,
        "audiveris": audiveris_available,
        "apk_builder": apk_builder_online,
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
    finished_scans = completed_scans + failed_scans
    success_rate = (completed_scans / finished_scans * 100) if finished_scans else 0.0
    today = datetime.now(timezone.utc).date()
    today_scans = sum(
        1 for task in tasks
        if (created := _parse_timestamp(task.get("created_at"))) is not None
        and created.astimezone(timezone.utc).date() == today
    )
    durations = []
    for task in tasks:
        started = _parse_timestamp(task.get("created_at"))
        completed = _parse_timestamp(task.get("completed_at"))
        if started and completed and completed >= started:
            durations.append((completed - started).total_seconds())

    redis_online = get_redis_client() is not None

    return {
        "total_scans": total_scans,
        "today_scans": today_scans,
        "completed_scans": completed_scans,
        "failed_scans": failed_scans,
        "running_scans": running_scans,
        "success_rate": round(success_rate, 1),
        "avg_processing_time_sec": round(statistics.mean(durations), 2) if durations else None,
        "redis_online": redis_online,
        "primary_omr_engine": "Audiveris v5.10.0",
        "recent_tasks": [
            {
                "task_id": task.get("task_id"),
                "title": task.get("title"),
                "status": task.get("status"),
                "error_summary": (
                    task.get("error_summary") or TASK_FAILURE_SUMMARY
                    if task.get("status") == "STATUS_FAILED"
                    else None
                ),
                "created_at": task.get("created_at"),
                "completed_at": task.get("completed_at"),
                "failed_at": task.get("failed_at"),
            }
            for task in reversed(tasks[-50:])
        ],
    }


@app.get("/api/v1/tasks/{task_id}/logs")
async def get_task_logs(task_id: str):
    task = get_task_state(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found.")

    input_path = task.get("file_path")
    extension = os.path.splitext(input_path or "")[1].lower()
    input_preview = None
    if (
        task.get("status") == "STATUS_FAILED"
        and extension in SCORE_MEDIA_TYPES
        and input_path
        and os.path.isfile(input_path)
    ):
        input_preview = {
            "url": f"/api/v1/tasks/{task_id}/input",
            "filename": os.path.basename(input_path),
            "media_type": SCORE_MEDIA_TYPES[extension],
            "size_bytes": os.path.getsize(input_path),
        }

    logs_path = task.get("logs_path")
    if logs_path and os.path.isfile(logs_path):
        with open(logs_path, encoding="utf-8", errors="replace") as log_file:
            logs = log_file.read()
    else:
        logs = task.get("error") or "Aucun log n’est disponible pour ce traitement."

    return {
        "task_id": task_id,
        "title": task.get("title") or "Partition sans titre",
        "status": task.get("status"),
        "created_at": task.get("created_at"),
        "failed_at": task.get("failed_at"),
        "summary": task.get("error_summary") or (
            TASK_FAILURE_SUMMARY if task.get("status") == "STATUS_FAILED" else None
        ),
        "logs": logs,
        "input_preview": input_preview,
    }


@app.get("/api/v1/tasks/{task_id}/input")
async def get_task_input(task_id: str):
    task = get_task_state(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found.")
    if task.get("status") != "STATUS_FAILED":
        raise HTTPException(status_code=409, detail="Uploaded input is retained only for failed tasks.")

    input_path = task.get("file_path")
    extension = os.path.splitext(input_path or "")[1].lower()
    if extension not in SCORE_MEDIA_TYPES or not input_path or not os.path.isfile(input_path):
        raise HTTPException(status_code=404, detail="The received file is no longer available.")

    return FileResponse(
        input_path,
        media_type=SCORE_MEDIA_TYPES[extension],
        headers={
            "Content-Disposition": "inline",
            "Cache-Control": "no-store",
        },
    )


@app.get("/api/v1/apk/status")
async def get_apk_status():
    status, payload = await request_apk_builder("GET", "/status")
    return JSONResponse(status_code=status, content=payload)


@app.get("/api/v1/apk/fingerprint")
async def get_apk_fingerprint():
    status, payload = await request_apk_builder("GET", "/fingerprint")
    return JSONResponse(status_code=status, content=payload)


@app.post("/api/v1/apk/build")
async def start_apk_build():
    if not API_KEY or not MELODISCAN_HOST:
        raise HTTPException(
            status_code=503,
            detail="APK generation requires a configured API key and server host.",
        )
    status, payload = await request_apk_builder("POST", "/build")
    return JSONResponse(status_code=status, content=payload)


@app.get("/api/v1/apk/build/{build_id}")
async def get_apk_build_status(build_id: str):
    try:
        from uuid import UUID

        normalized_build_id = str(UUID(build_id))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid APK build ID.") from exc
    status, payload = await request_apk_builder("GET", f"/build/{normalized_build_id}")
    return JSONResponse(status_code=status, content=payload)


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
        .section-heading, .section-tools, .apk-actions, .service-grid {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
        }
        .section-heading { margin-bottom: 18px; }
        .section-heading h2, .card h2 { margin: 0; font-size: 19px; }
        .section-tools select, .section-tools input, .btn-secondary {
            color: var(--text);
            background: var(--surface-elevated);
            border: 1px solid var(--border);
            border-radius: 9px;
            padding: 10px 12px;
        }
        .section-tools input { min-width: 180px; }
        .btn-secondary {
            cursor: pointer;
            font-weight: 700;
        }
        .btn:disabled, .btn-secondary:disabled { opacity: .55; cursor: wait; transform: none; }
        .service-grid { justify-content: flex-start; flex-wrap: wrap; margin-top: 16px; }
        .service { display: flex; align-items: center; gap: 8px; padding: 10px 13px;
            border: 1px solid var(--border); background: var(--surface-elevated); border-radius: 10px; }
        .dot { width: 9px; height: 9px; border-radius: 50%; background: #64748b; }
        .dot.online { background: var(--secondary); box-shadow: 0 0 12px rgba(6,214,160,.45); }
        .dot.offline { background: #ff6577; }
        .apk-layout { display: flex; align-items: center; justify-content: space-between; gap: 24px; flex-wrap: wrap; }
        .apk-meta, .muted, .error-text { color: var(--text-muted); font-size: 13px; }
        .apk-actions { justify-content: flex-start; flex-wrap: wrap; margin-top: 16px; }
        .error-text { color: #ff8795; white-space: pre-wrap; }
        .status-pill { display: inline-flex; padding: 5px 9px; border-radius: 99px;
            background: rgba(148,163,184,.12); color: var(--text-muted); font-size: 12px; }
        .status-pill.success { color: var(--secondary); background: rgba(6,214,160,.12); }
        .status-pill.failed { color: #ff8795; background: rgba(255,101,119,.12); }
        .status-pill.running { color: var(--accent-cyan); background: rgba(0,242,254,.1); }
        .task-error { color: #ff8795; margin-top: 5px; max-width: 420px; white-space: normal; }
        .task-error:hover { color: #ffb6c0; }
        .last-updated { color: var(--text-muted); font-size: 12px; }
        @media (max-width: 650px) {
            body { padding: 18px 12px; }
            .header, .section-heading, .apk-layout { align-items: flex-start; flex-direction: column; }
            .section-tools { width: 100%; }
            .section-tools input { min-width: 0; width: 100%; }
            th, td { padding: 10px 7px; }
            table { font-size: 12px; }
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
            <a class="btn-secondary" href="/dashboard/logs">Logs complets</a>
            <span class="badge" id="server-badge">Vérification des services…</span>
        </div>

        <div class="grid">
            <div class="card">
                <div class="metric-title">Partitions Numérisées</div>
                <div class="metric-value" id="stat-total">0</div>
                <div style="font-size: 12px; margin-top: 6px; color: var(--text-muted);">Total Demandes OMR</div>
            </div>

            <div class="card">
                <div class="metric-title">Réussies</div>
                <div class="metric-value" id="stat-completed">0</div>
                <div class="muted">Résultats MIDI disponibles</div>
            </div>

            <div class="card">
                <div class="metric-title">En échec</div>
                <div class="metric-value" style="color: #ff8795;" id="stat-failed">0</div>
                <div class="muted">Reconnaissance ou conversion échouée</div>
            </div>

            <div class="card">
                <div class="metric-title">En cours</div>
                <div class="metric-value" style="color: var(--accent-cyan);" id="stat-running">0</div>
                <div class="muted">Tâches en attente ou traitement</div>
            </div>

            <div class="card">
                <div class="metric-title">Aujourd’hui</div>
                <div class="metric-value" style="color: var(--primary);" id="stat-today">0</div>
                <div class="muted">Demandes reçues depuis minuit UTC</div>
            </div>

            <div class="card">
                <div class="metric-title">Taux de réussite</div>
                <div class="metric-value" style="color: #00F2FE;" id="stat-rate">—</div>
                <div class="muted">Calculé sur les tâches terminées</div>
            </div>

            <div class="card">
                <div class="metric-title">Temps moyen</div>
                <div class="metric-value" style="color: var(--primary);" id="stat-time">—</div>
                <div class="muted">Durée des traitements réussis</div>
            </div>

            <div class="card">
                <div class="metric-title">Redis</div>
                <div class="metric-value" style="color: #06D6A0;" id="stat-redis">—</div>
                <div class="muted">File et historique des tâches</div>
            </div>
        </div>

        <div class="card" style="margin-bottom: 20px;">
            <div class="section-heading">
                <h2>État des services</h2>
                <span class="last-updated" id="last-updated">Actualisation automatique</span>
            </div>
            <div class="service-grid">
                <div class="service"><span class="dot" id="service-api-dot"></span>API</div>
                <div class="service"><span class="dot" id="service-redis-dot"></span>Redis</div>
                <div class="service"><span class="dot" id="service-worker-dot"></span>Worker Celery</div>
                <div class="service"><span class="dot" id="service-audiveris-dot"></span>Audiveris</div>
                <div class="service"><span class="dot" id="service-apk_builder-dot"></span>Générateur Android</div>
            </div>
        </div>

        <div class="card" style="margin-bottom: 20px;">
            <div class="apk-layout">
                <div>
                    <h2>Application Android</h2>
                    <div class="apk-meta" id="apk-status" style="margin-top: 8px;">Vérification de l’APK…</div>
                    <div class="error-text" id="apk-error" role="status" style="margin-top: 8px;"></div>
                </div>
                <div class="apk-actions">
                    <button class="btn" id="build-apk-button" type="button">Générer l’APK</button>
                    <a class="btn-secondary" id="download-apk-link" href="/download/app-release.apk"
                       style="display:none; text-decoration:none;">Télécharger l’APK</a>
                </div>
            </div>
            <div class="muted" style="margin-top: 12px;">
                La compilation utilise l’adresse HTTPS du serveur, la clé API configurée et sa CA Caddy.
            </div>
        </div>

        <div class="card">
            <div class="section-heading">
                <h2>Historique des numérisations</h2>
                <div class="section-tools">
                    <select id="task-filter" aria-label="Filtrer les tâches">
                        <option value="all">Tous les statuts</option>
                        <option value="STATUS_COMPLETED">Réussies</option>
                        <option value="STATUS_FAILED">En échec</option>
                        <option value="running">En cours</option>
                    </select>
                    <input id="task-search" type="search" placeholder="Rechercher un titre ou ID"
                           aria-label="Rechercher dans les tâches">
                </div>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Tâche</th>
                        <th>Partition</th>
                        <th>État</th>
                        <th>Créée</th>
                        <th>Résultat</th>
                    </tr>
                </thead>
                <tbody id="tasks-table-body">
                    <tr>
                        <td colspan="5" style="color: var(--text-muted); text-align: center;">Chargement des tâches…</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <script>
        const runningStatuses = new Set([
            'STATUS_QUEUED', 'STATUS_PROCESSING_IMAGE', 'STATUS_RUNNING_OMR',
            'STATUS_BUILDING_MUSICXML', 'STATUS_EXPORTING_MIDI'
        ]);
        let currentTasks = [];

        async function apiRequest(url, options = {}) {
            const response = await fetch(url, { cache: 'no-store', ...options });
            let payload = {};
            try { payload = await response.json(); } catch (_) {}
            if (!response.ok) {
                throw new Error(payload.detail || `Erreur HTTP ${response.status}`);
            }
            return payload;
        }

        function escapeHtml(value) {
            return String(value ?? '').replace(/[&<>"']/g, character => ({
                '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
            })[character]);
        }

        function formatDate(value) {
            if (!value) return '—';
            const date = new Date(value);
            return Number.isNaN(date.getTime()) ? '—' : date.toLocaleString('fr-FR');
        }

        function renderTasks() {
            const tbody = document.getElementById('tasks-table-body');
            const filter = document.getElementById('task-filter').value;
            const query = document.getElementById('task-search').value.trim().toLocaleLowerCase();
            const tasks = currentTasks.filter(task => {
                const statusMatch = filter === 'all' ||
                    (filter === 'running' ? runningStatuses.has(task.status) : task.status === filter);
                const searchMatch = !query ||
                    `${task.title || ''} ${task.task_id || ''}`.toLocaleLowerCase().includes(query);
                return statusMatch && searchMatch;
            });
            if (!tasks.length) {
                tbody.innerHTML = '<tr><td colspan="5" class="muted" style="text-align:center;">Aucune tâche pour ces filtres.</td></tr>';
                return;
            }
            tbody.innerHTML = tasks.map(task => {
                const failed = task.status === 'STATUS_FAILED';
                const completed = task.status === 'STATUS_COMPLETED';
                const running = runningStatuses.has(task.status);
                const className = failed ? 'failed' : completed ? 'success' : running ? 'running' : '';
                const statusLabel = failed ? 'Échec' : completed ? 'Terminée' :
                    running ? 'En cours' : (task.status || 'Inconnue');
                const result = completed
                    ? `<a href="/api/v1/result/${encodeURIComponent(task.task_id)}">Télécharger MIDI</a>`
                    : '—';
                const logsLink =
                    `<a class="task-error" href="/dashboard/logs?task_id=${encodeURIComponent(task.task_id)}">Voir les logs</a>`;
                return `<tr>
                    <td><code>${escapeHtml((task.task_id || '').slice(0, 12))}</code></td>
                    <td><strong>${escapeHtml(task.title || 'Partition sans titre')}</strong></td>
                    <td><span class="status-pill ${className}">${escapeHtml(statusLabel)}</span>
                        ${logsLink}</td>
                    <td>${escapeHtml(formatDate(task.created_at))}</td>
                    <td>${result}</td>
                </tr>`;
            }).join('');
        }

        async function fetchStats() {
            try {
                const data = await apiRequest('/api/v1/stats');
                document.getElementById('stat-total').innerText = data.total_scans;
                document.getElementById('stat-completed').innerText = data.completed_scans;
                document.getElementById('stat-failed').innerText = data.failed_scans;
                document.getElementById('stat-running').innerText = data.running_scans;
                document.getElementById('stat-today').innerText = data.today_scans;
                document.getElementById('stat-rate').innerText = data.success_rate + '%';
                document.getElementById('stat-time').innerText =
                    data.avg_processing_time_sec == null ? '—' : `${data.avg_processing_time_sec}s`;
                document.getElementById('stat-redis').innerText = data.redis_online ? 'En ligne' : 'Indisponible';
                currentTasks = data.recent_tasks || [];
                renderTasks();
                document.getElementById('last-updated').innerText =
                    `Mis à jour à ${new Date().toLocaleTimeString('fr-FR')}`;
            } catch (e) {
                document.getElementById('last-updated').innerText = `Statistiques indisponibles : ${e.message}`;
            }
        }

        async function fetchHealth() {
            const badge = document.getElementById('server-badge');
            try {
                const response = await fetch('/health', { cache: 'no-store' });
                const data = await response.json();
                const dependencies = data.dependencies || {};
                for (const service of ['redis', 'celery_worker', 'audiveris', 'apk_builder']) {
                    const indicator = document.getElementById(`service-${service}-dot`);
                    indicator.className = `dot ${dependencies[service] ? 'online' : 'offline'}`;
                }
                document.getElementById('service-api-dot').className =
                    response.ok ? 'dot online' : 'dot offline';
                badge.innerText = data.status === 'ok' ? 'Tous les services opérationnels' : 'Service dégradé';
                badge.style.color = data.status === 'ok' ? 'var(--secondary)' : '#ff8795';
            } catch (error) {
                badge.innerText = `API indisponible : ${error.message}`;
                badge.style.color = '#ff8795';
            }
        }

        function renderApk(data) {
            const apk = data.apk || {};
            const building = data.status === 'building';
            const button = document.getElementById('build-apk-button');
            const download = document.getElementById('download-apk-link');
            const detail = apk.available
                ? `APK réel prêt · ${(apk.size_bytes / 1048576).toFixed(1)} Mio · généré le ${formatDate(apk.generated_at)} · SHA-256 ${escapeHtml((apk.sha256 || '').slice(0, 16))}…`
                : 'Aucun APK généré sur ce serveur.';
            document.getElementById('apk-status').innerText =
                building ? `${data.progress || 'Génération en cours…'} · ${detail}` : detail;
            document.getElementById('apk-error').textContent = data.status === 'failed' ? (data.error || 'Échec de compilation.') : '';
            button.disabled = building;
            button.innerText = building ? 'Génération en cours…' : 'Générer l’APK';
            download.style.display = apk.available ? 'inline-flex' : 'none';
        }

        async function fetchApkStatus() {
            try {
                renderApk(await apiRequest('/api/v1/apk/status'));
            } catch (error) {
                document.getElementById('apk-status').innerText = `Générateur indisponible : ${error.message}`;
                document.getElementById('build-apk-button').disabled = false;
            }
        }

        async function startApkBuild() {
            const button = document.getElementById('build-apk-button');
            button.disabled = true;
            document.getElementById('apk-error').textContent = '';
            try {
                await apiRequest('/api/v1/apk/build', { method: 'POST' });
            } catch (error) {
                document.getElementById('apk-error').textContent = error.message;
            }
            await fetchApkStatus();
        }

        document.getElementById('build-apk-button').addEventListener('click', startApkBuild);
        document.getElementById('task-filter').addEventListener('change', renderTasks);
        document.getElementById('task-search').addEventListener('input', renderTasks);
        fetchStats();
        fetchHealth();
        fetchApkStatus();
        setInterval(fetchStats, 5000);
        setInterval(fetchHealth, 10000);
        setInterval(fetchApkStatus, 3000);
    </script>
</body>
</html>"""
    return HTMLResponse(content=html_content)


@app.get("/dashboard/logs", response_class=HTMLResponse)
async def dashboard_logs():
    logs_page = os.path.join(os.path.dirname(__file__), "dashboard_logs.html")
    with open(logs_page, encoding="utf-8") as page:
        return HTMLResponse(content=page.read())


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
        raise HTTPException(status_code=400, detail="The uploaded file is empty.")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail=f"File exceeds the {MAX_UPLOAD_BYTES}-byte upload limit.")

    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        extension = ".png"
    elif content.startswith(b"\xff\xd8\xff"):
        extension = ".jpg"
    elif len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        extension = ".webp"
    elif content.startswith(b"%PDF-"):
        extension = ".pdf"
    else:
        raise HTTPException(
            status_code=415,
            detail="Only valid PNG, JPEG, WebP images, or PDF documents are supported.",
        )

    import uuid
    task_id = str(uuid.uuid4())
    os.makedirs("data/temp", exist_ok=True)
    temp_file_path = os.path.join("data/temp", f"{task_id}{extension}")
    log_path = os.path.join("data/temp", f"{task_id}.log")

    with open(temp_file_path, "wb") as f:
        f.write(content)
    with open(log_path, "w", encoding="utf-8") as log_file:
        log_file.write(f"Fichier reçu : {file.filename} ({len(content)} octets)\n")

    now = datetime.now(timezone.utc).isoformat()
    task_info = {
        "task_id": task_id,
        "title": title.strip() or "Untitled Score",
        "status": "STATUS_QUEUED",
        "created_at": now,
        "file_path": temp_file_path,
        "logs_path": log_path,
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
            "error_summary": TASK_FAILURE_SUMMARY,
            "failed_at": datetime.now(timezone.utc).isoformat(),
        })
        with open(log_path, "a", encoding="utf-8") as log_file:
            log_file.write(f"\nÉchec de mise en file : {exc}\n")
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
                    "error_summary": TASK_FAILURE_SUMMARY,
                }
            current_status = task_info.get("status", "STATUS_QUEUED")

            if current_status != last_status:
                last_status = current_status
                data = json.dumps({
                    "task_id": task_id,
                    "status": current_status,
                    "progress": progress_by_status.get(current_status, 0.0),
                    "error": (
                        task_info.get("error_summary") or TASK_FAILURE_SUMMARY
                        if current_status == "STATUS_FAILED"
                        else None
                    ),
                })
                yield f"data: {data}\n\n"

            if current_status in {"STATUS_COMPLETED", "STATUS_FAILED"}:
                break

            now = loop.time()
            if now - started >= TASK_TIMEOUT_SECONDS:
                task_info.update({
                    "status": "STATUS_FAILED",
                    "error": f"Image processing timed out after {TASK_TIMEOUT_SECONDS} seconds.",
                    "error_summary": "Le traitement a expiré. Consultez les diagnostics dans le dashboard.",
                    "failed_at": datetime.now(timezone.utc).isoformat(),
                })
                set_task_state(task_id, task_info)
                data = json.dumps({
                    "task_id": task_id,
                    "status": "STATUS_FAILED",
                    "progress": 0.0,
                    "error": task_info["error_summary"],
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


@app.get("/api/v1/result/{task_id}/musicxml")
async def get_task_musicxml(task_id: str):
    task_info = get_task_state(task_id)
    if not task_info:
        raise HTTPException(status_code=404, detail="Task not found")

    if task_info.get("status") == "STATUS_FAILED":
        raise HTTPException(status_code=422, detail=task_info.get("error", "Image processing failed."))
    if task_info.get("status") != "STATUS_COMPLETED":
        raise HTTPException(status_code=409, detail="Image processing has not completed.")

    musicxml_path = task_info.get("musicxml_path")
    if (
        not musicxml_path
        or not os.path.isfile(musicxml_path)
        or os.path.getsize(musicxml_path) == 0
    ):
        raise HTTPException(
            status_code=500,
            detail="Completed task has no valid MusicXML result.",
        )

    return FileResponse(
        musicxml_path,
        media_type="application/vnd.recordare.musicxml+xml",
        filename=f"score_{task_id}.musicxml",
    )
