import os
import logging
import re
from datetime import datetime, timezone
from celery import Celery
from app.omr_engine import OMREngine, convert_musicxml_to_midi

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

celery_app = Celery(
    "melodiscan_tasks",
    broker=REDIS_URL,
    backend=REDIS_URL
)

logger = logging.getLogger(__name__)


def _error_summary(error: Exception, default: str) -> str:
    diagnostic = f"{error}\n{getattr(error, 'diagnostics', '')}"
    interline = re.search(
        r"too low interline value of\s+(\d+)\s+pixels",
        diagnostic,
        re.IGNORECASE,
    )
    if interline and "Created scores: []" in diagnostic:
        return (
            "Aucune portée détectée : Audiveris mesure seulement "
            f"{interline.group(1)} pixels entre les lignes. La photo peut être nette, "
            "mais sa définition reste trop faible pour cette analyse. Essayez le "
            "PDF original ou un scan en 300 DPI."
        )
    if "completed without producing a non-empty MusicXML file" in diagnostic:
        return (
            "Audiveris n’a pas généré le fichier MusicXML attendu. Cela peut signifier "
            "qu’aucune partition exploitable n’a été reconnue ou que le fichier a été "
            "écrit sous un autre nom. Consultez les diagnostics détaillés."
        )
    return default


def _append_task_log(log_path: str | None, message: str) -> None:
    if not log_path:
        return
    timestamp = datetime.now(timezone.utc).isoformat()
    with open(log_path, "a", encoding="utf-8") as log_file:
        log_file.write(f"\n[{timestamp}] {message}\n")


@celery_app.task(name="app.tasks.process_omr_task")
def process_omr_task(task_id: str, score_path: str, title: str) -> dict:
    from app.main import TASK_FAILURE_SUMMARY, get_task_state, set_task_state

    output_dir = "data/temp"
    os.makedirs(output_dir, exist_ok=True)

    state = get_task_state(task_id) or {"task_id": task_id, "title": title}
    if state.get("status") == "STATUS_FAILED":
        return state

    log_path = state.get("logs_path")
    preserve_upload = False
    try:
        _append_task_log(log_path, "Traitement démarré.")
        state["status"] = "STATUS_PROCESSING_IMAGE"
        set_task_state(task_id, state)

        _append_task_log(log_path, "Lancement de la reconnaissance Audiveris.")
        state["status"] = "STATUS_RUNNING_OMR"
        set_task_state(task_id, state)
        musicxml_path = OMREngine(
            executable=os.getenv("AUDIVERIS_EXECUTABLE", "audiveris")
        ).process_score(score_path, output_dir, log_path)

        _append_task_log(log_path, f"MusicXML généré : {musicxml_path}")
        state["status"] = "STATUS_BUILDING_MUSICXML"
        set_task_state(task_id, state)

        _append_task_log(log_path, "Conversion du MusicXML en MIDI.")
        state["status"] = "STATUS_EXPORTING_MIDI"
        set_task_state(task_id, state)
        midi_path = os.path.join(output_dir, f"{task_id}.mid")
        convert_musicxml_to_midi(musicxml_path, midi_path)

        state.update({
            "status": "STATUS_COMPLETED",
            "musicxml_path": musicxml_path,
            "midi_path": midi_path,
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "error": None,
        })
        _append_task_log(log_path, "Traitement terminé avec succès.")
        set_task_state(task_id, state)
        return state
    except Exception as exc:
        preserve_upload = True
        logger.exception("OMR task %s failed.", task_id)
        _append_task_log(log_path, f"Échec du traitement : {exc}")
        state.update({
            "status": "STATUS_FAILED",
            "error": str(exc),
            "error_summary": _error_summary(exc, TASK_FAILURE_SUMMARY),
            "failed_at": datetime.now(timezone.utc).isoformat(),
        })
        set_task_state(task_id, state)
        raise
    finally:
        if not preserve_upload:
            try:
                os.remove(score_path)
            except FileNotFoundError:
                pass
            except OSError:
                logger.exception("Could not remove uploaded score file for task %s.", task_id)
