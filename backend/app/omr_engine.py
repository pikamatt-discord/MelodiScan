import os
import subprocess
import tempfile
import zipfile
from xml.etree import ElementTree


class OMRProcessingError(RuntimeError):
    def __init__(self, message: str, diagnostics: str = ""):
        super().__init__(message)
        self.diagnostics = diagnostics


class OMREngine:
    def __init__(self, executable: str = "audiveris"):
        self.executable = executable

    def process_score(
        self, score_path: str, output_dir: str, log_path: str | None = None
    ) -> str:
        os.makedirs(output_dir, exist_ok=True)
        base_name = os.path.splitext(os.path.basename(score_path))[0]
        output_musicxml = os.path.join(output_dir, f"{base_name}.musicxml")

        try:
            cmd = [
                self.executable,
                "-batch",
                "-transcribe",
                "-export",
                "-output",
                output_dir,
                score_path,
            ]
            if log_path:
                with open(log_path, "ab") as log_file:
                    res = subprocess.run(
                        cmd,
                        stdout=log_file,
                        stderr=subprocess.STDOUT,
                        timeout=300,
                    )
                with open(log_path, "r", encoding="utf-8", errors="replace") as log_file:
                    output = log_file.read()
            else:
                res = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=300,
                )
                output = "\n".join(
                    f"{name}:\n{captured.decode('utf-8', errors='replace').strip()}"
                    for name, captured in (("STDERR", res.stderr), ("STDOUT", res.stdout))
                    if captured
                ).strip()
        except FileNotFoundError as exc:
            raise OMRProcessingError(
                f"Audiveris executable '{self.executable}' is not installed or not on PATH."
            ) from exc
        except subprocess.TimeoutExpired as exc:
            diagnostics = ""
            if log_path and os.path.isfile(log_path):
                with open(log_path, "r", encoding="utf-8", errors="replace") as log_file:
                    diagnostics = log_file.read()
            elif exc.output:
                diagnostics = exc.output.decode("utf-8", errors="replace")
            raise OMRProcessingError(
                "Audiveris timed out after 300 seconds.", diagnostics
            ) from exc
        except OSError as exc:
            raise OMRProcessingError(f"Could not run Audiveris: {exc}") from exc

        if res.returncode != 0:
            raise OMRProcessingError(
                f"Audiveris failed with exit code {res.returncode}.", output
            )
        output_mxl = os.path.join(output_dir, f"{base_name}.mxl")
        if os.path.isfile(output_mxl) and os.path.getsize(output_mxl) > 0:
            try:
                with zipfile.ZipFile(output_mxl) as archive:
                    container = ElementTree.fromstring(
                        archive.read("META-INF/container.xml")
                    )
                    rootfile = next(
                        (
                            element
                            for element in container.iter()
                            if element.tag.rsplit("}", 1)[-1] == "rootfile"
                        ),
                        None,
                    )
                    musicxml_entry = rootfile.get("full-path") if rootfile is not None else None
                    if not musicxml_entry:
                        raise OMRProcessingError(
                            "Audiveris exported an MXL file without a MusicXML rootfile."
                        )
                    musicxml_content = archive.read(musicxml_entry)
                if not musicxml_content:
                    raise OMRProcessingError(
                        "Audiveris exported an empty MusicXML document inside the MXL file."
                    )
                with open(output_musicxml, "wb") as musicxml_file:
                    musicxml_file.write(musicxml_content)
                return output_musicxml
            except (zipfile.BadZipFile, KeyError, ElementTree.ParseError, OSError) as exc:
                raise OMRProcessingError(
                    f"Could not read MusicXML from Audiveris MXL export '{output_mxl}': {exc}",
                    output,
                ) from exc
        if not os.path.isfile(output_musicxml) or os.path.getsize(output_musicxml) == 0:
            raise OMRProcessingError(
                "Audiveris completed without producing a non-empty MusicXML file "
                f"at the expected path '{output_musicxml}'.",
                output,
            )

        return output_musicxml

    def process_image(self, image_path: str, output_dir: str) -> str:
        return self.process_score(image_path, output_dir)

    @staticmethod
    def _local_name(element: ElementTree.Element) -> str:
        return element.tag.rsplit("}", 1)[-1]

    @staticmethod
    def _child(element: ElementTree.Element, name: str) -> ElementTree.Element | None:
        return next(
            (item for item in element if OMREngine._local_name(item) == name),
            None,
        )

    @staticmethod
    def _text(element: ElementTree.Element | None, name: str) -> str | None:
        child = None if element is None else OMREngine._child(element, name)
        if child is None or child.text is None:
            return None
        value = child.text.strip()
        return value or None


    @staticmethod
    def _midi_pitch_from_display(
        step: str | None,
        octave: str | None,
    ) -> int | None:
        steps = {
            "C": 0,
            "D": 2,
            "E": 4,
            "F": 5,
            "G": 7,
            "A": 9,
            "B": 11,
        }
        try:
            midi_pitch = (int(octave) + 1) * 12 + steps[step or ""]
            return midi_pitch if 0 <= midi_pitch <= 127 else None
        except (KeyError, TypeError, ValueError):
            return None


    @staticmethod
    def _pitch_element_for_midi_note(
        parent: ElementTree.Element,
        midi_pitch: int,
    ) -> ElementTree.Element:
        namespace = parent.tag.partition("}")[0] + "}" if "}" in parent.tag else ""
        step, alter = (
            ("C", 0),
            ("C", 1),
            ("D", 0),
            ("D", 1),
            ("E", 0),
            ("F", 0),
            ("F", 1),
            ("G", 0),
            ("G", 1),
            ("A", 0),
            ("A", 1),
            ("B", 0),
        )[midi_pitch % 12]
        pitch = ElementTree.Element(f"{namespace}pitch")
        ElementTree.SubElement(pitch, f"{namespace}step").text = step
        if alter:
            ElementTree.SubElement(pitch, f"{namespace}alter").text = str(alter)
        ElementTree.SubElement(pitch, f"{namespace}octave").text = str(
            midi_pitch // 12 - 1
        )
        return pitch


    @staticmethod
    def _prepare_musicxml_for_midi(
        musicxml_path: str,
    ) -> tuple[dict[str, dict], str | None]:
        tree = ElementTree.parse(musicxml_path)
        root = tree.getroot()
        part_settings = {}
        part_list = next(
            (item for item in root if OMREngine._local_name(item) == "part-list"),
            None,
        )

        if part_list is not None:
            for score_part in (
                item
                for item in part_list
                if OMREngine._local_name(item) == "score-part"
            ):
                part_id = score_part.get("id")
                if not part_id:
                    continue
                score_instruments = [
                    item
                    for item in score_part
                    if OMREngine._local_name(item) == "score-instrument"
                ]
                midi_instruments = {
                    item.get("id"): item
                    for item in score_part
                    if OMREngine._local_name(item) == "midi-instrument"
                }
                midi_pitches = {}
                for instrument in score_instruments:
                    instrument_id = instrument.get("id")
                    midi_pitch = OMREngine._text(
                        midi_instruments.get(instrument_id),
                        "midi-unpitched",
                    )
                    try:
                        if midi_pitch is not None:
                            pitch_number = int(midi_pitch)
                            if 0 <= pitch_number <= 127:
                                midi_pitches[instrument_id] = pitch_number
                    except ValueError:
                        pass

                midi_instrument = next(iter(midi_instruments.values()), None)
                channel_text = OMREngine._text(midi_instrument, "midi-channel")
                program_text = OMREngine._text(midi_instrument, "midi-program")
                channel = (
                    int(channel_text)
                    if channel_text and channel_text.isdigit()
                    else None
                )
                program = (
                    int(program_text) - 1
                    if program_text and program_text.isdigit()
                    else None
                )
                instrument_name = next(
                    (
                        OMREngine._text(instrument, "instrument-name")
                        for instrument in score_instruments
                        if OMREngine._text(instrument, "instrument-name")
                    ),
                    None,
                )
                labels = (
                    f"{instrument_name or ''} "
                    f"{OMREngine._text(score_part, 'part-name') or ''}"
                ).casefold()
                part_settings[part_id] = {
                    "channel": channel,
                    "program": (
                        program
                        if program is not None and 0 <= program <= 127
                        else None
                    ),
                    "percussion": channel == 10
                    or any(
                        word in labels
                        for word in ("percussion", "drum", "batterie")
                    ),
                    "midi_pitches": midi_pitches,
                    "default_midi_pitch": (
                        next(iter(midi_pitches.values()))
                        if len(midi_pitches) == 1
                        else None
                    ),
                }

        has_unpitched = False
        for part in (
            item for item in root if OMREngine._local_name(item) == "part"
        ):
            settings = part_settings.get(part.get("id", ""), {})
            for clef in (
                element for element in part.iter()
                if OMREngine._local_name(element) == "clef"
            ):
                if (OMREngine._text(clef, "sign") or "").casefold() == "percussion":
                    settings["percussion"] = True
            for note in (
                element for element in part.iter()
                if OMREngine._local_name(element) == "note"
            ):
                unpitched = OMREngine._child(note, "unpitched")
                if unpitched is None:
                    continue
                instrument = OMREngine._child(note, "instrument")
                instrument_id = None if instrument is None else instrument.get("id")
                midi_pitch = settings.get("midi_pitches", {}).get(instrument_id)
                settings["percussion"] = True
                if midi_pitch is None:
                    midi_pitch = settings.get("default_midi_pitch")
                if midi_pitch is None:
                    midi_pitch = OMREngine._midi_pitch_from_display(
                        OMREngine._text(unpitched, "display-step"),
                        OMREngine._text(unpitched, "display-octave"),
                    )
                if midi_pitch is None:
                    continue
                pitch = OMREngine._pitch_element_for_midi_note(note, midi_pitch)
                note.insert(list(note).index(unpitched), pitch)
                note.remove(unpitched)
                has_unpitched = True

        if not has_unpitched:
            return part_settings, None

        with tempfile.NamedTemporaryFile(
            mode="wb",
            suffix=".musicxml",
            delete=False,
        ) as temporary_file:
            tree.write(temporary_file, encoding="utf-8", xml_declaration=True)
            return part_settings, temporary_file.name


    @staticmethod
    def convert_musicxml_to_midi(
        musicxml_path: str,
        midi_output_path: str,
    ) -> str:
        temporary_musicxml_path = None
        try:
            import partitura
            import mido

            part_settings, temporary_musicxml_path = (
                OMREngine._prepare_musicxml_for_midi(musicxml_path)
            )
            score = partitura.load_musicxml(
                temporary_musicxml_path or musicxml_path
            )
            parts = [part for part in score.parts if len(part.notes_tied) > 0]
            if not parts:
                raise OMRProcessingError(
                    "MusicXML conversion found no notes to export as MIDI."
                )
            partitura.save_score_midi(parts, midi_output_path)
            midi = mido.MidiFile(midi_output_path)
            if len(midi.tracks) != len(parts):
                raise OMRProcessingError(
                    "MusicXML conversion could not match exported tracks to score parts."
                )
            for track_index, part in enumerate(parts):
                part_id = str(part.id or f"part-{track_index + 1}")
                settings = part_settings.get(part_id, {})
                percussion = settings.get("percussion", False)
                source_channel = settings.get("channel")
                target_channel = (
                    9
                    if percussion
                    else source_channel - 1
                    if isinstance(source_channel, int) and 1 <= source_channel <= 16
                    else None
                )
                track = midi.tracks[track_index]
                channels = set()
                for event in track:
                    if event.type not in {"note_on", "note_off"}:
                        continue
                    channels.add(event.channel)
                    if target_channel is not None:
                        event.channel = target_channel
                if target_channel is not None:
                    channels = {target_channel}

                inserted_events = [
                    mido.MetaMessage("track_name", name=part_id, time=0),
                ]
                program = settings.get("program")
                if not percussion and isinstance(program, int):
                    inserted_events.extend(
                        mido.Message(
                            "program_change",
                            channel=channel,
                            program=program,
                            time=0,
                        )
                        for channel in sorted(channels)
                    )
                track[:] = inserted_events + [
                    event for event in track if event.type != "track_name"
                ]
            midi.save(midi_output_path)
            if (
                not os.path.isfile(midi_output_path)
                or os.path.getsize(midi_output_path) < 22
            ):
                raise OMRProcessingError(
                    "MusicXML conversion completed without producing a valid MIDI file."
                )
            with open(midi_output_path, "rb") as midi_file:
                header = midi_file.read(8)
                if header[:4] != b"MThd" or len(header) != 8:
                    raise OMRProcessingError(
                        "MusicXML conversion produced an invalid MIDI header."
                    )
                midi_file.seek(8 + int.from_bytes(header[4:8], "big"))
                if midi_file.read(4) != b"MTrk":
                    raise OMRProcessingError(
                        "MusicXML conversion produced no valid MIDI track."
                    )
        except Exception as e:
            if os.path.isfile(midi_output_path):
                os.remove(midi_output_path)
            if isinstance(e, OMRProcessingError):
                raise
            raise OMRProcessingError(
                f"MusicXML to MIDI conversion failed: {e}"
            ) from e
        finally:
            if temporary_musicxml_path and os.path.isfile(temporary_musicxml_path):
                os.remove(temporary_musicxml_path)
        return midi_output_path


def convert_musicxml_to_midi(musicxml_path: str, midi_output_path: str) -> str:
    return OMREngine.convert_musicxml_to_midi(musicxml_path, midi_output_path)
