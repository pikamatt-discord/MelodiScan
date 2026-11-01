import os
import json
import asyncio
import base64
import binascii
import hashlib
import hmac
import logging
import secrets
import shutil
import statistics
import time
from datetime import datetime, timezone
from typing import Dict, Any, AsyncGenerator
from urllib.parse import parse_qs, urlencode
from fastapi import FastAPI, Request, UploadFile, File, Form, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
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
AUDIVERIS_EXECUTABLE = os.getenv("AUDIVERIS_EXECUTABLE", "audiveris")
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
        ) and not _has_dashboard_session(request):
            return JSONResponse(
                status_code=401,
                content={"detail": "A valid API key is required."},
                headers={"WWW-Authenticate": "ApiKey"},
            )

    is_login_route = path in {"/login", "/auth/login", "/logout", "/assets/dashboard.css"}
    if (
        not is_login_route
        and (path == "/" or path.startswith("/dashboard"))
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


def dashboard_navigation(active_page: str) -> str:
    links = (
        ("overview", "/dashboard", "Vue d’ensemble"),
        ("logs", "/dashboard/logs", "Traitements"),
        ("profiles", "/dashboard/profiles", "Profils"),
    )
    navigation_items = []
    for key, href, label in links:
        current = ' aria-current="page"' if active_page == key else ""
        navigation_items.append(f'<a href="{href}"{current}>{label}</a>')
    navigation = "".join(navigation_items)
    logout = (
        '<form action="/logout" method="post"><button class="nav-logout" type="submit">Déconnexion</button></form>'
        if DASHBOARD_USERNAME else ""
    )
    return f"""
    <nav class="topbar" aria-label="Navigation principale">
        <a class="brand" href="/dashboard" aria-label="MelodiScan, accueil">
            <span class="brand-mark" aria-hidden="true">♫</span>
            <span>Melodi<span>Scan</span><small>ESPACE D’ADMINISTRATION</small></span>
        </a>
        <div class="nav-links">{navigation}</div>
        <div class="nav-account"><span class="account-indicator"></span><span>Serveur privé</span>{logout}</div>
    </nav>
    """


LOGIN_PAGE = """<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="theme-color" content="#101116">
    <title>Connexion · MelodiScan</title>
    <link rel="stylesheet" href="/assets/dashboard.css">
</head>
<body class="login-page">
    <main class="login-layout">
        <section class="login-story" aria-label="MelodiScan">
            <a class="brand login-brand" href="/login">
                <span class="brand-mark" aria-hidden="true">♫</span>
                <span>Melodi<span>Scan</span><small>ESPACE D’ADMINISTRATION</small></span>
            </a>
            <div class="login-message">
                <span class="eyebrow"><span class="pulse-dot"></span> STUDIO DE NUMÉRISATION MUSICALE</span>
                <h1>Vos partitions,<br><em>à portée de main.</em></h1>
                <p>Retrouvez vos traitements, suivez vos services et gérez votre espace MelodiScan.</p>
            </div>
            <div class="music-art" aria-hidden="true">
                <span></span><span></span><span></span><span></span><span></span><span></span><span></span>
                <span></span><span></span><span></span><span></span><span></span><span></span>
            </div>
            <div class="login-footnote">Une expérience musicale, pensée dans les moindres détails.</div>
        </section>
        <section class="login-panel">
            <div class="login-card">
                <div class="login-icon" aria-hidden="true">↗</div>
                <div class="eyebrow">BON RETOUR</div>
                <h2>Connexion</h2>
                <p class="login-intro">Connectez-vous pour accéder à votre tableau de bord.</p>
                <form id="login-form">
                    <input type="hidden" name="next">
                    <label for="username">Identifiant</label>
                    <input id="username" name="username" autocomplete="username" required autofocus>
                    <label for="password">Mot de passe</label>
                    <div class="password-field">
                        <input id="password" name="password" type="password" autocomplete="current-password" required>
                        <button id="toggle-password" class="password-toggle" type="button" aria-label="Afficher le mot de passe" aria-pressed="false">Afficher</button>
                    </div>
                    <div id="login-error" class="login-error" role="alert" aria-live="polite"></div>
                    <button class="login-submit" type="submit"><span>Accéder au dashboard</span><span aria-hidden="true">→</span></button>
                </form>
                <div class="login-security"><span aria-hidden="true">⌑</span> Connexion sécurisée · Session privée</div>
            </div>
            <div class="login-copyright">MELODISCAN <span>·</span> VOTRE ATELIER MUSICAL</div>
        </section>
    </main>
    <script>
        const form = document.getElementById('login-form');
        const errorBox = document.getElementById('login-error');
        form.elements.next.value = new URLSearchParams(location.search).get('next') || '/dashboard';
        form.addEventListener('submit', async event => {
            event.preventDefault();
            const button = form.querySelector('.login-submit');
            button.disabled = true;
            errorBox.textContent = '';
            try {
                const response = await fetch('/auth/login', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: new URLSearchParams(new FormData(form))
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.detail || 'Connexion impossible.');
                location.assign(result.redirect_url);
            } catch (error) {
                errorBox.textContent = error.message;
                button.disabled = false;
            }
        });
        document.getElementById('toggle-password').addEventListener('click', event => {
            const password = document.getElementById('password');
            const visible = password.type === 'password';
            password.type = visible ? 'text' : 'password';
            event.currentTarget.textContent = visible ? 'Masquer' : 'Afficher';
            event.currentTarget.setAttribute('aria-pressed', String(visible));
            event.currentTarget.setAttribute('aria-label', visible ? 'Masquer le mot de passe' : 'Afficher le mot de passe');
        });
    </script>
</body>
</html>"""


@app.get("/assets/dashboard.css")
async def dashboard_stylesheet():
    stylesheet = os.path.join(os.path.dirname(__file__), "dashboard.css")
    return FileResponse(stylesheet, media_type="text/css")


@app.get("/login", response_class=HTMLResponse)
async def login_page():
    if not DASHBOARD_USERNAME:
        return RedirectResponse("/dashboard", status_code=303)
    return HTMLResponse(content=LOGIN_PAGE)


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
    <meta name="theme-color" content="#101116">
    <title>Tableau de bord · MelodiScan</title>
    <link rel="stylesheet" href="/assets/dashboard.css">
    <style>
        body {
            padding: 0 24px 42px;
        }
        .container {
            max-width: 1240px;
            margin: 0 auto;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .card {
            background: linear-gradient(145deg, rgba(28, 29, 39, .96), rgba(23, 24, 32, .96));
            border: 1px solid var(--border);
            border-radius: 15px;
            padding: 21px;
            box-shadow: 0 10px 28px rgba(0,0,0,.12);
            animation: rise-in .45s both;
            transition: border-color .2s ease, transform .2s ease, box-shadow .2s ease;
        }
        .card:hover {
            border-color: rgba(167,139,250,.25);
            box-shadow: 0 14px 32px rgba(0,0,0,.2);
            transform: translateY(-2px);
        }
        .grid .card:nth-child(2) { animation-delay: .04s; }
        .grid .card:nth-child(3) { animation-delay: .08s; }
        .grid .card:nth-child(4) { animation-delay: .12s; }
        .grid .card:nth-child(5) { animation-delay: .16s; }
        .grid .card:nth-child(6) { animation-delay: .2s; }
        .grid .card:nth-child(7) { animation-delay: .24s; }
        .grid .card:nth-child(8) { animation-delay: .28s; }
        .metric-title {
            color: var(--text-muted);
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: .09em;
        }
        .metric-value {
            font-size: 34px;
            font-weight: 720;
            letter-spacing: -.04em;
            color: var(--secondary);
            margin-top: 12px;
        }
        .btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            border: 1px solid rgba(195, 176, 255, .38);
            background: linear-gradient(120deg, #9276e6, #7562c4);
            color: #fff;
            font-weight: 700;
            padding: 12px 19px;
            border-radius: 10px;
            text-decoration: none;
            transition: filter .2s, transform .2s, box-shadow .2s;
        }
        .btn:hover {
            filter: brightness(1.08);
            box-shadow: 0 8px 20px rgba(117,98,196,.2);
            transform: translateY(-1px);
        }
        .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            border: 1px solid rgba(103,232,194,.18);
            border-radius: 20px;
            background: rgba(103, 232, 194, 0.08);
            color: var(--secondary);
            font-size: 11px;
            font-weight: 650;
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
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: .08em;
        }
        code {
            background: rgba(255,255,255,.055);
            padding: 4px 8px;
            border-radius: 5px;
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
        .section-heading h2, .card h2 { margin: 0; font-size: 16px; letter-spacing: -.02em; }
        .section-tools select, .section-tools input, .btn-secondary {
            color: var(--text);
            background: rgba(255,255,255,.035);
            border: 1px solid var(--border);
            border-radius: 9px;
            padding: 10px 12px;
        }
        .section-tools select, .section-tools input { min-height: 40px; }
        .section-tools input { min-width: 180px; }
        .btn-secondary { text-decoration: none; }
        .btn-secondary {
            cursor: pointer;
            font-weight: 700;
            font-size: 12px;
            transition: border-color .2s, background .2s;
        }
        .btn-secondary:hover { border-color: rgba(167,139,250,.45); background: rgba(167,139,250,.08); }
        .btn:disabled, .btn-secondary:disabled { opacity: .55; cursor: wait; transform: none; }
        .service-grid { justify-content: flex-start; flex-wrap: wrap; margin-top: 16px; }
        .service { display: flex; align-items: center; gap: 8px; padding: 10px 13px;
            border: 1px solid var(--border); background: rgba(255,255,255,.025); border-radius: 10px;
            color: #d3d2dc; font-size: 12px; }
        .dot { width: 9px; height: 9px; border-radius: 50%; background: #64748b; }
        .dot.online { background: var(--secondary); box-shadow: 0 0 12px rgba(103,232,194,.45); }
        .dot.offline { background: #ff6577; }
        .apk-layout { display: flex; align-items: center; justify-content: space-between; gap: 24px; flex-wrap: wrap; }
        .apk-meta, .muted, .error-text { color: var(--text-muted); font-size: 13px; }
        .apk-actions { justify-content: flex-start; flex-wrap: wrap; margin-top: 16px; }
        .error-text { color: var(--error); white-space: pre-wrap; }
        .status-pill { display: inline-flex; padding: 5px 9px; border-radius: 99px;
            background: rgba(148,163,184,.12); color: var(--text-muted); font-size: 12px; }
        .status-pill.success { color: var(--secondary); background: rgba(6,214,160,.12); }
        .status-pill.failed { color: var(--error); background: rgba(251,135,149,.1); }
        .status-pill.running { color: var(--accent-cyan); background: rgba(125,211,252,.1); }
        .task-error { color: var(--error); margin-top: 5px; max-width: 420px; white-space: normal; }
        .task-error:hover { color: #ffc0c8; }
        .last-updated { color: var(--text-muted); font-size: 12px; }
        @media (max-width: 650px) {
            body { padding: 0 12px 28px; }
            .section-heading, .apk-layout { align-items: flex-start; flex-direction: column; }
            .section-tools { width: 100%; }
            .section-tools input { min-width: 0; width: 100%; }
            th, td { padding: 10px 7px; }
            table { font-size: 12px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- DASHBOARD_NAV -->
        <div class="page-heading">
            <div>
                <div class="eyebrow">VOTRE ATELIER MUSICAL</div>
                <h1>Vue d’ensemble</h1>
                <p>Suivez vos numérisations et l’activité de vos services en un coup d’œil.</p>
            </div>
            <span class="badge" id="server-badge"><span class="pulse-dot"></span> Vérification des services…</span>
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
    return HTMLResponse(content=html_content.replace("<!-- DASHBOARD_NAV -->", dashboard_navigation("overview")))


@app.get("/dashboard/logs", response_class=HTMLResponse)
async def dashboard_logs():
    logs_page = os.path.join(os.path.dirname(__file__), "dashboard_logs.html")
    with open(logs_page, encoding="utf-8") as page:
        return HTMLResponse(content=page.read().replace("<!-- DASHBOARD_NAV -->", dashboard_navigation("logs")))


@app.get("/dashboard/profiles", response_class=HTMLResponse)
async def dashboard_profiles():
    page_path = os.path.join(os.path.dirname(__file__), "dashboard_profiles.html")
    with open(page_path, encoding="utf-8") as page:
        return HTMLResponse(content=page.read().replace("<!-- DASHBOARD_NAV -->", dashboard_navigation("profiles")))


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
        "midi_path": None
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
