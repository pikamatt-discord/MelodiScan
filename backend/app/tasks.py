import os
import logging
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

@celery_app.task(name="app.tasks.process_omr_task")
def process_omr_task(task_id: str, score_path: str, title: str) -> dict:
    from app.main import TASK_FAILURE_SUMMARY, get_task_state, set_task_state

    output_dir = "data/temp"
    os.makedirs(output_dir, exist_ok=True)

    state = get_task_state(task_id) or {"task_id": task_id, "title": title}
    if state.get("status") == "STATUS_FAILED":
        return state

    try:
        state["status"] = "STATUS_PROCESSING_IMAGE"
        set_task_state(task_id, state)

        state["status"] = "STATUS_RUNNING_OMR"
        set_task_state(task_id, state)
        musicxml_path = OMREngine(
            executable=os.getenv("AUDIVERIS_EXECUTABLE", "audiveris")
        ).process_score(score_path, output_dir)

        state["status"] = "STATUS_BUILDING_MUSICXML"
        set_task_state(task_id, state)

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
        set_task_state(task_id, state)
        return state
    except Exception as exc:
        logger.exception("OMR task %s failed.", task_id)
        state.update({
            "status": "STATUS_FAILED",
            "error": str(exc)[:4500],
            "error_summary": TASK_FAILURE_SUMMARY,
            "failed_at": datetime.now(timezone.utc).isoformat(),
        })
        set_task_state(task_id, state)
        raise
    finally:
        try:
            os.remove(score_path)
        except FileNotFoundError:
            pass
        except OSError:
            logger.exception("Could not remove uploaded score file for task %s.", task_id)
