import os
import json
import asyncio
import base64
import binascii
import hashlib
import hmac
import importlib.util
import logging
import secrets
import statistics
import time
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, AsyncGenerator
from urllib.parse import parse_qs, urlencode
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import httpx
from pydantic import BaseModel, Field
import redis
from app.library_store import (
    DEFAULT_PROFILES,
    delete_saved_score,
    get_profile,
    get_saved_score,
    list_profiles,
    list_saved_scores,
    rename_profile,
)

app = FastAPI(
    title="MelodiScan Core Engine API",
    version="1.0.0",
    description="API for OMR score digitization and music processing"
)

logger = logging.getLogger(__name__)
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
API_KEY = os.getenv("API_KEY", "")
DASHBOARD_USERNAME = os.getenv("DASHBOARD_USERNAME", "")
DASHBOARD_PASSWORD = os.getenv("DASHBOARD_PASSWORD", "")
DASHBOARD_SESSION_SECRET = (
    os.getenv("DASHBOARD_SESSION_SECRET", "")
    or API_KEY
    or secrets.token_urlsafe(32)
)
DASHBOARD_SESSION_COOKIE = "melodiscan_dashboard_session"
DASHBOARD_SESSION_MAX_AGE = 8 * 60 * 60
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", 20 * 1024 * 1024))
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
        ) and not _has_dashboard_session(request):
            return JSONResponse(
                status_code=401,
                content={"detail": "A valid API key is required."},
                headers={"WWW-Authenticate": "ApiKey"},
            )

    is_login_route = path in {"/login", "/auth/login", "/logout"}
    if (
        not is_login_route
        and (path == "/" or path == "/dashboard" or path.startswith("/dashboard/"))
        and DASHBOARD_USERNAME
        and not _has_dashboard_credentials(request.headers.get("Authorization", ""))
        and not _has_dashboard_session(request)
    ):
        target = request.url.path
        if request.url.query:
            target += f"?{request.url.query}"
        return RedirectResponse(f"/login?{urlencode({'next': target})}", status_code=303)

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


def _dashboard_session_signature(expires_at: str) -> str:
    key = hashlib.sha256(DASHBOARD_SESSION_SECRET.encode()).digest()
    return hmac.new(key, expires_at.encode(), hashlib.sha256).hexdigest()


def _has_dashboard_session(request: Request) -> bool:
    if not DASHBOARD_USERNAME:
        return False
    try:
        expires_at, signature = request.cookies.get(DASHBOARD_SESSION_COOKIE, "").split(".", 1)
        expiry = int(expires_at)
    except (ValueError, TypeError):
        return False
    now = int(time.time())
    return (
        now < expiry <= now + DASHBOARD_SESSION_MAX_AGE
        and hmac.compare_digest(signature, _dashboard_session_signature(expires_at))
    )


def _safe_dashboard_redirect(value: str) -> str:
    if value.startswith("/") and not value.startswith("//") and "\\" not in value and not any(
        ord(character) < 32 for character in value
    ):
        return value
    return "/dashboard"


DASHBOARD_DIST = os.path.join(os.path.dirname(os.path.dirname(__file__)), "dashboard", "dist")

app.mount(
    "/dashboard-assets",
    StaticFiles(directory=DASHBOARD_DIST, check_dir=False),
    name="dashboard-assets",
)


def dashboard_index():
    index_path = os.path.join(DASHBOARD_DIST, "index.html")
    if not os.path.isfile(index_path):
        raise HTTPException(status_code=503, detail="Dashboard frontend is not built.")
    return FileResponse(index_path, media_type="text/html")


@app.get("/", response_class=HTMLResponse)
@app.get("/dashboard", response_class=HTMLResponse)
@app.get("/dashboard/logs", response_class=HTMLResponse)
@app.get("/dashboard/profiles", response_class=HTMLResponse)
async def dashboard_page():
    return dashboard_index()


@app.get("/login", response_class=HTMLResponse)
async def login_page():
    if not DASHBOARD_USERNAME:
        return RedirectResponse("/dashboard", status_code=303)
    return dashboard_index()


@app.post("/auth/login")
async def login(request: Request):
    if not DASHBOARD_USERNAME:
        raise HTTPException(status_code=404, detail="Dashboard authentication is not configured.")
    try:
        values = parse_qs((await request.body()).decode("utf-8"), keep_blank_values=True)
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid login form.") from exc
    username = values.get("username", [""])[0]
    password = values.get("password", [""])[0]
    if not (
        hmac.compare_digest(username, DASHBOARD_USERNAME)
        and hmac.compare_digest(password, DASHBOARD_PASSWORD)
    ):
        return JSONResponse(status_code=401, content={"detail": "Identifiant ou mot de passe incorrect."})
    expires_at = str(int(time.time()) + DASHBOARD_SESSION_MAX_AGE)
    response = JSONResponse(
        content={"redirect_url": _safe_dashboard_redirect(values.get("next", ["/dashboard"])[0])}
    )
    response.set_cookie(
        DASHBOARD_SESSION_COOKIE,
        f"{expires_at}.{_dashboard_session_signature(expires_at)}",
        max_age=DASHBOARD_SESSION_MAX_AGE,
        httponly=True,
        secure=(
            request.url.scheme == "https"
            or request.headers.get("x-forwarded-proto", "").split(",", 1)[0].strip().lower() == "https"
        ),
        samesite="lax",
        path="/",
    )
    return response


@app.post("/logout")
async def logout():
    response = RedirectResponse("/login", status_code=303)
    response.delete_cookie(DASHBOARD_SESSION_COOKIE, path="/")
    return response


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


class ProfileUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=40)


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
    oemer_available = importlib.util.find_spec("oemer") is not None
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
        "oemer": oemer_available,
        "apk_builder": apk_builder_online,
    }
    status = "ok" if all(dependencies.values()) else "degraded"
    return JSONResponse(
        status_code=200 if status == "ok" else 503,
        content={
            "status": status,
            "service": "MelodiScan Engine",
            "version": os.getenv("MELODISCAN_VERSION", "unknown"),
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
    activity_dates = [today - timedelta(days=offset) for offset in range(6, -1, -1)]
    activity_by_day = {day.isoformat(): 0 for day in activity_dates}
    for task in tasks:
        created = _parse_timestamp(task.get("created_at"))
        if created:
            day = created.astimezone(timezone.utc).date().isoformat()
            if day in activity_by_day:
                activity_by_day[day] += 1
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
        "primary_omr_engine": "Oemer",
        "activity_by_day": [
            {"date": day.isoformat(), "count": activity_by_day[day.isoformat()]}
            for day in activity_dates
        ],
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
    title: str = Form("", max_length=200),
    profile_id: str = Form(DEFAULT_PROFILES[0][0]),
    notification_token: str | None = Form(None, max_length=4096),
):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file uploaded")
    if get_profile(profile_id) is None:
        raise HTTPException(status_code=400, detail="Unknown profile.")

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
        "title": title.strip() or "Analyse de la partition",
        "user_title": title.strip() or None,
        "profile_id": profile_id,
        "status": "STATUS_QUEUED",
        "created_at": now,
        "file_path": temp_file_path,
        "logs_path": log_path,
        "midi_path": None,
        "notification_token": notification_token,
    }
    set_task_state(task_id, task_info)

    try:
        from app.tasks import process_omr_task
        process_omr_task.delay(
            task_id,
            temp_file_path,
            task_info["user_title"] or "",
        )
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


@app.get("/api/v1/profiles")
async def get_profiles():
    return {"profiles": list_profiles()}


@app.put("/api/v1/profiles/{profile_id}")
async def update_profile(profile_id: str, update: ProfileUpdate):
    name = update.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Profile name cannot be empty.")
    profile = rename_profile(profile_id, name)
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found.")
    return profile


@app.get("/api/v1/library")
async def get_profile_library(profile_id: str = Query(..., min_length=1)):
    if get_profile(profile_id) is None:
        raise HTTPException(status_code=404, detail="Profile not found.")
    items = list_saved_scores(profile_id)
    return {
        "items": [
            {
                "task_id": item["task_id"],
                "profile_id": item["profile_id"],
                "title": item["title"],
                "created_at": item["created_at"],
                "score_metadata": item["score_metadata"],
                "source_url": f"/api/v1/library/{item['task_id']}/source",
            }
            for item in items
        ]
    }


@app.get("/api/v1/library/{task_id}/source")
async def get_saved_source(
    task_id: str, profile_id: str = Query(..., min_length=1)
):
    item = get_saved_score(task_id, profile_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Saved score not found.")
    source_path = item["source_path"]
    extension = os.path.splitext(source_path)[1].lower()
    media_type = SCORE_MEDIA_TYPES.get(extension)
    if media_type is None or not os.path.isfile(source_path):
        raise HTTPException(status_code=404, detail="Saved source file is unavailable.")
    return FileResponse(
        source_path,
        media_type=media_type,
        headers={"Content-Disposition": "inline"},
    )


@app.delete("/api/v1/library/{task_id}", status_code=204)
async def delete_library_score(
    task_id: str, profile_id: str = Query(..., min_length=1)
):
    try:
        deleted = delete_saved_score(task_id, profile_id)
    except OSError as exc:
        logger.exception("Could not remove saved score files for task %s.", task_id)
        raise HTTPException(
            status_code=500,
            detail="The score record was removed, but its files could not be fully deleted.",
        ) from exc
    except ValueError as exc:
        logger.exception("Invalid saved score paths for task %s.", task_id)
        raise HTTPException(status_code=500, detail="Saved score files are invalid.") from exc
    if not deleted:
        raise HTTPException(status_code=404, detail="Saved score not found.")


@app.get("/api/v1/stream/{task_id}")
async def stream_task_status(task_id: str):
    if not get_task_state(task_id):
        raise HTTPException(status_code=404, detail="Task not found")

    async def event_generator() -> AsyncGenerator[str, None]:
        last_status = None
        loop = asyncio.get_running_loop()
        last_heartbeat = loop.time()
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
                    "title": task_info.get("title"),
                    "score_metadata": task_info.get("score_metadata"),
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
            if now - last_heartbeat >= 15:
                yield ": keep-alive\n\n"
                last_heartbeat = now
            await asyncio.sleep(0.4)

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/api/v1/result/{task_id}")
async def get_task_result(
    task_id: str,
    profile_id: str | None = Query(default=None, min_length=1),
):
    task_info = get_task_state(task_id)
    if not task_info or task_info.get("status") != "STATUS_COMPLETED":
        saved_score = get_saved_score(task_id, profile_id)
        if saved_score is not None:
            task_info = saved_score | {"status": "STATUS_COMPLETED"}
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
async def get_task_musicxml(
    task_id: str,
    profile_id: str | None = Query(default=None, min_length=1),
):
    task_info = get_task_state(task_id)
    if not task_info or task_info.get("status") != "STATUS_COMPLETED":
        saved_score = get_saved_score(task_id, profile_id)
        if saved_score is not None:
            task_info = saved_score | {"status": "STATUS_COMPLETED"}
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
