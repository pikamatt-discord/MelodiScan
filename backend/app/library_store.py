import json
import os
import shutil
import sqlite3
from pathlib import Path

DEFAULT_PROFILES = (
    ("profile-1", "Profil 1"),
    ("profile-2", "Profil 2"),
    ("profile-3", "Profil 3"),
)


def _library_dir() -> Path:
    return Path(os.getenv("MELODISCAN_LIBRARY_DIR", "data/library")).resolve()


def _connect() -> sqlite3.Connection:
    library_dir = _library_dir()
    library_dir.mkdir(parents=True, exist_ok=True)
    database_path = Path(
        os.getenv("MELODISCAN_LIBRARY_DB", str(library_dir / "library.sqlite3"))
    )
    database_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database_path, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def initialize_library() -> None:
    with _connect() as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS saved_scores (
                task_id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL REFERENCES profiles(id),
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                source_path TEXT NOT NULL,
                midi_path TEXT NOT NULL,
                musicxml_path TEXT NOT NULL,
                score_metadata TEXT NOT NULL
            );
            """
        )
        for profile_id, name in DEFAULT_PROFILES:
            connection.execute(
                "INSERT OR IGNORE INTO profiles (id, name, created_at) "
                "VALUES (?, ?, datetime('now'))",
                (profile_id, name),
            )


def list_profiles() -> list[dict]:
    initialize_library()
    with _connect() as connection:
        return [
            dict(row)
            for row in connection.execute(
                "SELECT id, name FROM profiles ORDER BY created_at, id"
            )
        ]


def get_profile(profile_id: str) -> dict | None:
    initialize_library()
    with _connect() as connection:
        row = connection.execute(
            "SELECT id, name FROM profiles WHERE id = ?", (profile_id,)
        ).fetchone()
        return dict(row) if row else None


def rename_profile(profile_id: str, name: str) -> dict | None:
    initialize_library()
    with _connect() as connection:
        cursor = connection.execute(
            "UPDATE profiles SET name = ? WHERE id = ?", (name, profile_id)
        )
        if cursor.rowcount == 0:
            return None
        row = connection.execute(
            "SELECT id, name FROM profiles WHERE id = ?", (profile_id,)
        ).fetchone()
        return dict(row)


def save_completed_score(
    *,
    task_id: str,
    profile_id: str,
    title: str,
    created_at: str,
    source_path: str,
    midi_path: str,
    musicxml_path: str,
    score_metadata: dict,
) -> dict:
    initialize_library()
    if get_profile(profile_id) is None:
        profile_id = DEFAULT_PROFILES[0][0]

    source = Path(source_path)
    midi = Path(midi_path)
    musicxml = Path(musicxml_path)
    for path in (source, midi, musicxml):
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Cannot save scan with missing result file: {path.name}")

    score_dir = _library_dir() / "scores" / task_id
    score_dir.mkdir(parents=True, exist_ok=True)
    saved_paths = {
        "source_path": score_dir / f"source{source.suffix.lower()}",
        "midi_path": score_dir / "score.mid",
        "musicxml_path": score_dir / "score.musicxml",
    }

    try:
        shutil.copy2(source, saved_paths["source_path"])
        shutil.copy2(midi, saved_paths["midi_path"])
        shutil.copy2(musicxml, saved_paths["musicxml_path"])
        with _connect() as connection:
            connection.execute(
                """
                INSERT OR REPLACE INTO saved_scores (
                    task_id, profile_id, title, created_at, source_path,
                    midi_path, musicxml_path, score_metadata
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    task_id,
                    profile_id,
                    title,
                    created_at,
                    str(saved_paths["source_path"]),
                    str(saved_paths["midi_path"]),
                    str(saved_paths["musicxml_path"]),
                    json.dumps(score_metadata, ensure_ascii=False),
                ),
            )
    except Exception:
        shutil.rmtree(score_dir, ignore_errors=True)
        raise

    return {
        "task_id": task_id,
        "profile_id": profile_id,
        "title": title,
        "created_at": created_at,
        "source_path": str(saved_paths["source_path"]),
        "midi_path": str(saved_paths["midi_path"]),
        "musicxml_path": str(saved_paths["musicxml_path"]),
        "score_metadata": score_metadata,
    }


def list_saved_scores(profile_id: str) -> list[dict]:
    initialize_library()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT task_id, profile_id, title, created_at, source_path,
                   midi_path, musicxml_path, score_metadata
            FROM saved_scores
            WHERE profile_id = ?
            ORDER BY created_at DESC, task_id DESC
            """,
            (profile_id,),
        )
        results = []
        for row in rows:
            item = dict(row)
            item["score_metadata"] = json.loads(item["score_metadata"])
            results.append(item)
        return results


def get_saved_score(task_id: str, profile_id: str | None = None) -> dict | None:
    initialize_library()
    with _connect() as connection:
        if profile_id is None:
            row = connection.execute(
                "SELECT * FROM saved_scores WHERE task_id = ?", (task_id,)
            ).fetchone()
        else:
            row = connection.execute(
                "SELECT * FROM saved_scores WHERE task_id = ? AND profile_id = ?",
                (task_id, profile_id),
            ).fetchone()
        if not row:
            return None
        item = dict(row)
        item["score_metadata"] = json.loads(item["score_metadata"])
        return item


def delete_saved_score(task_id: str, profile_id: str) -> bool:
    initialize_library()
    with _connect() as connection:
        row = connection.execute(
            "SELECT source_path, midi_path, musicxml_path "
            "FROM saved_scores WHERE task_id = ? AND profile_id = ?",
            (task_id, profile_id),
        ).fetchone()
        if row is None:
            return False

        score_dir = Path(row["source_path"]).parent.resolve()
        scores_dir = (_library_dir() / "scores").resolve()
        if score_dir.parent != scores_dir:
            raise ValueError("Saved score path is outside the library.")
        if any(Path(row[key]).parent.resolve() != score_dir for key in (
            "source_path",
            "midi_path",
            "musicxml_path",
        )):
            raise ValueError("Saved score files do not share the expected directory.")

        connection.execute(
            "DELETE FROM saved_scores WHERE task_id = ? AND profile_id = ?",
            (task_id, profile_id),
        )

    if score_dir.exists():
        shutil.rmtree(score_dir)
    return True
