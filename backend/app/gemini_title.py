import base64
import json
import logging
import os
from pathlib import Path

import httpx

logger = logging.getLogger(__name__)

_MODEL = "gemini-3.5-flash-lite"
_MAX_INLINE_BYTES = 14 * 1024 * 1024
_MIME_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".pdf": "application/pdf",
}


class GeminiTitleError(RuntimeError):
    pass


def extract_score_title(score_path: str) -> str | None:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        return None

    path = Path(score_path)
    mime_type = _MIME_TYPES.get(path.suffix.lower())
    if mime_type is None:
        raise GeminiTitleError("unsupported score file type")

    try:
        file_size = path.stat().st_size
        if file_size > _MAX_INLINE_BYTES:
            raise GeminiTitleError(
                "score file exceeds Gemini's inline request size limit"
            )
        file_data = base64.b64encode(path.read_bytes()).decode("ascii")
    except OSError as exc:
        raise GeminiTitleError("could not read score file for title extraction") from exc

    request_body = {
        "contents": [{
            "parts": [
                {
                    "text": (
                        "Read the printed title of this musical score. Return only "
                        "the title exactly as printed. Do not return a composer, "
                        "instrument name, filename, or other text. If no title is "
                        "clearly printed, return an empty title."
                    )
                },
                {
                    "inline_data": {
                        "mime_type": mime_type,
                        "data": file_data,
                    }
                },
            ],
        }],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": {
                "type": "OBJECT",
                "properties": {"title": {"type": "STRING"}},
                "required": ["title"],
            },
            "maxOutputTokens": 64,
            "temperature": 0,
        },
    }

    try:
        response = httpx.post(
            f"https://generativelanguage.googleapis.com/v1beta/models/{_MODEL}:generateContent",
            headers={"x-goog-api-key": api_key},
            json=request_body,
            timeout=45,
        )
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("Gemini title request failed: %s", exc)
        raise GeminiTitleError("Gemini title request failed") from exc

    try:
        result = response.json()
        text = result["candidates"][0]["content"]["parts"][0]["text"]
        title = json.loads(text)["title"]
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        raise GeminiTitleError("Gemini returned an invalid title response") from exc

    if not isinstance(title, str):
        raise GeminiTitleError("Gemini returned a non-text title")
    title = title.strip()
    return title[:200] or None
