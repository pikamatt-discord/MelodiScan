import os
from xml.etree import ElementTree


def _local_name(element: ElementTree.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _child(element: ElementTree.Element, name: str) -> ElementTree.Element | None:
    return next(
        (item for item in element if _local_name(item) == name),
        None,
    )


def _children(element: ElementTree.Element, name: str):
    return (item for item in element if _local_name(item) == name)


def _text(element: ElementTree.Element | None, name: str) -> str | None:
    if element is None:
        return None
    child = _child(element, name)
    if child is None or not child.text:
        return None
    value = child.text.strip()
    return value or None


def _clef_name(clef: ElementTree.Element) -> str:
    sign = _text(clef, "sign")
    line = _text(clef, "line")
    if sign == "G":
        return "treble"
    if sign == "F":
        return "bass"
    if sign == "C":
        return {"3": "alto", "4": "tenor"}.get(line or "", "alto")
    if sign and sign.lower() == "percussion":
        return "percussion"
    return "unknown"


def _tempo_from_direction(direction: ElementTree.Element) -> float | None:
    sound = _child(direction, "sound")
    if sound is not None:
        tempo = sound.get("tempo")
        if tempo:
            try:
                value = float(tempo)
                if 20 <= value <= 400:
                    return value
            except ValueError:
                pass

    for metronome in (
        element for element in direction.iter()
        if _local_name(element) == "metronome"
    ):
        per_minute = _text(metronome, "per-minute")
        beat_unit = _text(metronome, "beat-unit")
        try:
            value = float(per_minute or "")
        except ValueError:
            continue
        quarter_notes_per_unit = {
            "whole": 4,
            "half": 2,
            "quarter": 1,
            "eighth": 0.5,
            "16th": 0.25,
            "32nd": 0.125,
            "64th": 0.0625,
        }.get(beat_unit or "")
        if quarter_notes_per_unit is None:
            continue
        dots = sum(1 for child in metronome if _local_name(child) == "beat-unit-dot")
        value *= quarter_notes_per_unit * (2 - 0.5**dots)
        if 20 <= value <= 400:
            return value
    return None


def analyze_musicxml(musicxml_path: str) -> dict:
    """Extract only metadata explicitly present in the MusicXML document."""
    root = ElementTree.parse(musicxml_path).getroot()
    work = next((item for item in root if _local_name(item) == "work"), None)
    identification = next(
        (item for item in root if _local_name(item) == "identification"),
        None,
    )
    title = _text(work, "work-title") or _text(root, "movement-title")
    creators = []
    if identification is not None:
        for creator in _children(identification, "creator"):
            role = creator.get("type", "").strip()
            name = (creator.text or "").strip()
            if name:
                creators.append({"role": role or "creator", "name": name})

    part_names = {}
    part_programs = {}
    part_list = next((item for item in root if _local_name(item) == "part-list"), None)
    if part_list is not None:
        for score_part in _children(part_list, "score-part"):
            part_id = score_part.get("id")
            if not part_id:
                continue
            part_names[part_id] = (
                _text(score_part, "part-name") or
                _text(score_part, "part-abbreviation")
            )
            midi_instrument = next(
                (item for item in score_part if _local_name(item) == "midi-instrument"),
                None,
            )
            program = _text(midi_instrument, "midi-program")
            if program:
                try:
                    part_programs[part_id] = min(127, max(0, int(program) - 1))
                except ValueError:
                    pass

    parts = []
    tempo_changes: dict[tuple[float, float], dict] = {}
    global_measure_count = 0
    for part_index, part in enumerate(
        (item for item in root if _local_name(item) == "part"),
        start=1,
    ):
        part_id = part.get("id", "")
        measures = [item for item in _children(part, "measure")]
        global_measure_count = max(global_measure_count, len(measures))
        staves = 1
        clefs = {}
        fifths = None
        meter = None
        note_count = 0
        divisions = 1.0
        elapsed_quarters = 0.0

        for measure_index, measure in enumerate(measures, start=1):
            cursor = 0.0
            furthest = 0.0
            previous_note_start = 0.0
            for item in measure:
                name = _local_name(item)
                if name == "attributes":
                    divisions_value = _text(item, "divisions")
                    if divisions_value:
                        try:
                            divisions = float(divisions_value)
                        except ValueError:
                            raise ValueError("MusicXML divisions must be numeric.")
                        if divisions <= 0:
                            raise ValueError("MusicXML divisions must be positive.")
                    staves_value = _text(item, "staves")
                    if staves_value:
                        try:
                            staves = max(staves, int(staves_value))
                        except ValueError:
                            pass
                    key = _child(item, "key")
                    fifths_value = _text(key, "fifths")
                    if fifths_value:
                        try:
                            fifths = int(fifths_value)
                        except ValueError:
                            pass
                    time = _child(item, "time")
                    beats = _text(time, "beats")
                    beat_type = _text(time, "beat-type")
                    if beats and beat_type:
                        meter = {"beats": beats, "beat_type": beat_type}
                    for clef in _children(item, "clef"):
                        number = clef.get("number", "1")
                        clefs[number] = _clef_name(clef)
                        try:
                            staves = max(staves, int(number))
                        except ValueError:
                            pass
                elif name in {"backup", "forward"}:
                    duration = _text(item, "duration")
                    try:
                        delta = float(duration or "0")
                    except ValueError:
                        delta = 0
                    cursor += -delta if name == "backup" else delta
                    furthest = max(furthest, cursor)
                elif name == "note":
                    if _child(item, "rest") is None:
                        note_count += 1
                    staff = _text(item, "staff")
                    if staff:
                        try:
                            staves = max(staves, int(staff))
                        except ValueError:
                            pass
                    duration = _text(item, "duration")
                    try:
                        note_duration = float(duration or "0")
                    except ValueError:
                        note_duration = 0
                    is_chord = _child(item, "chord") is not None
                    if not is_chord:
                        previous_note_start = cursor
                        cursor += note_duration
                    furthest = max(
                        furthest,
                        previous_note_start + note_duration,
                        cursor,
                    )
                elif name == "direction":
                    tempo = _tempo_from_direction(item)
                    if tempo is not None:
                        offset_text = _text(item, "offset")
                        try:
                            offset = float(offset_text or "0")
                        except ValueError:
                            offset = 0
                        quarter_position = round(
                            elapsed_quarters + (cursor + offset) / divisions,
                            6,
                        )
                        tempo_changes[(quarter_position, tempo)] = {
                            "quarter_position": quarter_position,
                            "bpm": round(tempo, 2),
                            "measure": measure_index,
                        }

            expected_quarters = 0.0
            if meter:
                try:
                    beat_count = sum(int(value) for value in meter["beats"].split("+"))
                    expected_quarters = beat_count * 4 / int(meter["beat_type"])
                except (ValueError, ZeroDivisionError):
                    expected_quarters = 0
            duration_quarters = max(expected_quarters, furthest / divisions)
            elapsed_quarters += duration_quarters

        parts.append({
            "id": part_id or f"part-{part_index}",
            "name": part_names.get(part_id) or f"Partie {part_index}",
            "instrument_program": part_programs.get(part_id),
            "staves": staves,
            "clefs": clefs,
            "measure_count": len(measures),
            "note_count": note_count,
            "key_fifths": fifths,
            "meter": meter,
        })

    return {
        "title": title,
        "creators": creators,
        "measure_count": global_measure_count,
        "parts": parts,
        "tempo_changes": sorted(
            tempo_changes.values(),
            key=lambda item: (item["quarter_position"], item["bpm"]),
        ),
        "source": "musicxml",
    }


def analyze_musicxml_file(musicxml_path: str) -> dict:
    if not os.path.isfile(musicxml_path) or os.path.getsize(musicxml_path) == 0:
        raise ValueError("MusicXML analysis requires a non-empty document.")
    return analyze_musicxml(musicxml_path)
