import os
import logging
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
def process_omr_task(task_id: str, image_path: str, title: str) -> dict:
    from app.main import get_task_state, set_task_state

    output_dir = "data/temp"
    os.makedirs(output_dir, exist_ok=True)
    
    state = get_task_state(task_id) or {"task_id": task_id, "title": title}

    # 1. Processing image / running OMR
    state["status"] = "STATUS_RUNNING_OMR"
    set_task_state(task_id, state)

    engine = OMREngine()
    musicxml_path, confidence = engine.process_image(image_path, output_dir)

    # 2. Building MusicXML
    state["status"] = "STATUS_BUILDING_MUSICXML"
    set_task_state(task_id, state)

    # 3. Exporting MIDI via Partitura
    state["status"] = "STATUS_EXPORTING_MIDI"
    set_task_state(task_id, state)

    midi_path = os.path.join(output_dir, f"{task_id}.mid")
    convert_musicxml_to_midi(musicxml_path, midi_path)

    # 4. Completed
    state["status"] = "STATUS_COMPLETED"
    state["midi_path"] = midi_path
    set_task_state(task_id, state)

    return {
        "task_id": task_id,
        "status": "STATUS_COMPLETED",
        "musicxml_path": musicxml_path,
        "midi_path": midi_path,
        "confidence": confidence
    }
