import base64

import httpx
import pytest

from app.gemini_title import GeminiTitleError, extract_score_title


def test_extract_score_title_sends_only_file_and_title_prompt(monkeypatch, tmp_path):
    score_path = tmp_path / "score.png"
    score_bytes = b"\x89PNG\r\n\x1a\nscore"
    score_path.write_bytes(score_bytes)
    monkeypatch.setenv("GEMINI_API_KEY", "test-api-key")
    captured = {}

    def post(url, **kwargs):
        captured["url"] = url
        captured.update(kwargs)
        return httpx.Response(
            200,
            json={
                "candidates": [{
                    "content": {
                        "parts": [{"text": '{"title":"Clair de lune"}'}],
                    },
                }],
            },
            request=httpx.Request(
                "POST",
                "https://generativelanguage.googleapis.com/v1beta/test",
            ),
        )

    monkeypatch.setattr("app.gemini_title.httpx.post", post)

    assert extract_score_title(str(score_path)) == "Clair de lune"
    assert "test-api-key" not in captured["url"]
    assert captured["headers"] == {"x-goog-api-key": "test-api-key"}
    parts = captured["json"]["contents"][0]["parts"]
    assert "only the title" in parts[0]["text"].lower()
    assert parts[1]["inline_data"]["mime_type"] == "image/png"
    assert base64.b64decode(parts[1]["inline_data"]["data"]) == score_bytes
    assert captured["json"]["generationConfig"]["maxOutputTokens"] == 64


def test_extract_score_title_skips_gemini_without_api_key(monkeypatch, tmp_path):
    score_path = tmp_path / "score.png"
    score_path.write_bytes(b"score")
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)

    def fail_if_called(*_args, **_kwargs):
        pytest.fail("Gemini must not be called without an API key")

    monkeypatch.setattr("app.gemini_title.httpx.post", fail_if_called)

    assert extract_score_title(str(score_path)) is None


def test_extract_score_title_rejects_malformed_response(monkeypatch, tmp_path):
    score_path = tmp_path / "score.png"
    score_path.write_bytes(b"score")
    monkeypatch.setenv("GEMINI_API_KEY", "test-api-key")
    monkeypatch.setattr(
        "app.gemini_title.httpx.post",
        lambda *_args, **_kwargs: httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": "not json"}]}}]},
            request=httpx.Request(
                "POST",
                "https://generativelanguage.googleapis.com/v1beta/test",
            ),
        ),
    )

    with pytest.raises(GeminiTitleError, match="invalid title response"):
        extract_score_title(str(score_path))
