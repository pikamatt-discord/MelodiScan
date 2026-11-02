import copy
import os
import subprocess
import tempfile
from xml.etree import ElementTree


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _part_names(root: ElementTree.Element) -> dict[str, str]:
    part_list = next(
        (element for element in root if _local_name(element.tag) == "part-list"),
        None,
    )
    if part_list is None:
        return {}
    return {
        part.get("id"): " ".join((name.text or "").split()).casefold()
        for part in part_list
        if _local_name(part.tag) == "score-part" and part.get("id")
        for name in part
        if _local_name(name.tag) == "part-name"
    }


def _merge_page_musicxml(pages: list[bytes]) -> bytes:
    try:
        roots = [ElementTree.fromstring(content) for content in pages]
    except ElementTree.ParseError as exc:
        raise OMRProcessingError(
            f"Could not parse Oemer page MusicXML: {exc}"
        ) from exc

    merged_root = copy.deepcopy(roots[0])
    target_parts = {
        part.get("id"): part
        for part in merged_root
        if _local_name(part.tag) == "part" and part.get("id")
    }
    if not target_parts or any(
        _local_name(root.tag) != _local_name(merged_root.tag) for root in roots
    ):
        raise OMRProcessingError(
            "Oemer page exports do not contain compatible partwise MusicXML."
        )

    target_names = _part_names(merged_root)
    names_to_ids: dict[str, list[str]] = {}
    for part_id, name in target_names.items():
        names_to_ids.setdefault(name, []).append(part_id)

    for root in roots[1:]:
        source_names = _part_names(root)
        source_parts = [part for part in root if _local_name(part.tag) == "part"]
        matched_parts: set[str] = set()
        for source_part in source_parts:
            source_id = source_part.get("id")
            target_id = source_id if source_id in target_parts else None
            if target_id is None:
                source_name = source_names.get(source_id)
                matches = names_to_ids.get(source_name or "", [])
                if len(matches) == 1:
                    target_id = matches[0]
            if target_id is None or target_id in matched_parts:
                raise OMRProcessingError(
                    "Oemer page exports have incompatible or ambiguous parts."
                )
            matched_parts.add(target_id)
            target_part = target_parts[target_id]
            target_part.extend(
                copy.deepcopy(measure)
                for measure in source_part
                if _local_name(measure.tag) == "measure"
            )
        if matched_parts != set(target_parts):
            raise OMRProcessingError(
                "Oemer page exports do not contain the same set of parts."
            )

    return ElementTree.tostring(
        merged_root, encoding="utf-8", xml_declaration=True
    )


class OMRProcessingError(RuntimeError):
    def __init__(self, message: str, diagnostics: str = ""):
        super().__init__(message)
        self.diagnostics = diagnostics


class OMREngine:
    def __init__(self, executable: str = "oemer"):
        self.executable = executable

    def process_score(
        self, score_path: str, output_dir: str, log_path: str | None = None
    ) -> str:
        os.makedirs(output_dir, exist_ok=True)
        base_name = os.path.splitext(os.path.basename(score_path))[0]
        output_musicxml = os.path.join(output_dir, f"{base_name}.musicxml")
        is_pdf = os.path.splitext(score_path)[1].lower() == ".pdf"
        diagnostics: list[str] = []

        with tempfile.TemporaryDirectory(
            prefix=f"{base_name}-oemer-", dir=output_dir
        ) as working_dir:
            if is_pdf:
                try:
                    from pdf2image import convert_from_path

                    page_paths = convert_from_path(
                        score_path,
                        dpi=300,
                        fmt="png",
                        output_folder=working_dir,
                        output_file="page",
                        paths_only=True,
                    )
                except Exception as exc:
                    raise OMRProcessingError(
                        f"Could not rasterize PDF pages for Oemer: {exc}"
                    ) from exc
            else:
                page_paths = [score_path]

            if not page_paths:
                raise OMRProcessingError("The uploaded score contains no pages.")

            page_musicxml: list[bytes] = []
            for page_number, page_path in enumerate(page_paths, start=1):
                page_output_dir = os.path.join(working_dir, f"page-{page_number}")
                os.makedirs(page_output_dir)
                page_xml_path = os.path.join(page_output_dir, "recognized.musicxml")
                command = [
                    self.executable,
                    page_path,
                    "--output-path",
                    page_xml_path,
                ]
                try:
                    result = subprocess.run(
                        command,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        timeout=600,
                        check=False,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                    )
                except FileNotFoundError as exc:
                    raise OMRProcessingError(
                        f"Oemer executable '{self.executable}' is not installed or not on PATH."
                    ) from exc
                except subprocess.TimeoutExpired as exc:
                    captured = exc.stdout or ""
                    if isinstance(captured, bytes):
                        captured = captured.decode("utf-8", errors="replace")
                    raise OMRProcessingError(
                        f"Oemer timed out while processing page {page_number}.",
                        captured,
                    ) from exc
                except OSError as exc:
                    raise OMRProcessingError(f"Could not run Oemer: {exc}") from exc

                page_diagnostics = result.stdout or ""
                diagnostics.append(
                    f"Page {page_number}:\n{page_diagnostics}".rstrip()
                )
                if log_path and page_diagnostics:
                    with open(log_path, "a", encoding="utf-8") as log_file:
                        log_file.write(
                            f"\nOemer page {page_number}:\n{page_diagnostics}\n"
                        )
                if result.returncode != 0:
                    raise OMRProcessingError(
                        f"Oemer failed on page {page_number} with exit code "
                        f"{result.returncode}.",
                        "\n".join(diagnostics),
                    )

                if not os.path.isfile(page_xml_path) or os.path.getsize(page_xml_path) == 0:
                    raise OMRProcessingError(
                        f"Oemer completed without producing MusicXML for page {page_number} "
                        f"at '{page_xml_path}'.",
                        "\n".join(diagnostics),
                    )
                with open(page_xml_path, "rb") as musicxml_file:
                    page_musicxml.append(musicxml_file.read())

            try:
                musicxml = (
                    page_musicxml[0]
                    if len(page_musicxml) == 1
                    else _merge_page_musicxml(page_musicxml)
                )
            except OMRProcessingError as exc:
                raise OMRProcessingError(str(exc), "\n".join(diagnostics)) from exc

        with open(output_musicxml, "wb") as musicxml_file:
            musicxml_file.write(musicxml)
        return output_musicxml

    def process_image(self, image_path: str, output_dir: str) -> str:
        return self.process_score(image_path, output_dir)

def convert_musicxml_to_midi(musicxml_path: str, midi_output_path: str) -> str:
    try:
        from music21 import converter
        import mido

        score = converter.parse(musicxml_path)
        for note in score.recurse().notes:
            note.volume.velocity = 88
        for instrument_part in score.recurse().getElementsByClass("Instrument"):
            instrument_part.midiProgram = 0

        score.write("midi", fp=midi_output_path)
        midi_file = mido.MidiFile(midi_output_path)
        for track in midi_file.tracks:
            channels = {
                message.channel
                for message in track
                if not message.is_meta and hasattr(message, "channel")
            }
            if not channels:
                continue
            for message in track:
                if message.type == "program_change":
                    message.program = 0
                elif message.type == "note_on" and message.velocity > 0:
                    message.velocity = 88
            effects = []
            for channel in sorted(channels):
                effects.extend(
                    [
                        mido.Message(
                            "program_change", channel=channel, program=0, time=0
                        ),
                        mido.Message(
                            "control_change",
                            channel=channel,
                            control=91,
                            value=45,
                            time=0,
                        ),
                        mido.Message(
                            "control_change",
                            channel=channel,
                            control=93,
                            value=20,
                            time=0,
                        ),
                    ]
                )
            track[:0] = effects
        midi_file.save(midi_output_path)

        if not os.path.isfile(midi_output_path) or os.path.getsize(midi_output_path) < 22:
            raise OMRProcessingError("MusicXML conversion completed without producing a valid MIDI file.")
        with open(midi_output_path, "rb") as midi_file:
            header = midi_file.read(8)
            if header[:4] != b"MThd" or len(header) != 8:
                raise OMRProcessingError("MusicXML conversion produced an invalid MIDI header.")
            midi_file.seek(8 + int.from_bytes(header[4:8], "big"))
            if midi_file.read(4) != b"MTrk":
                raise OMRProcessingError("MusicXML conversion produced no valid MIDI track.")
    except Exception as e:
        if os.path.isfile(midi_output_path):
            os.remove(midi_output_path)
        if isinstance(e, OMRProcessingError):
            raise
        raise OMRProcessingError(f"MusicXML to MIDI conversion failed: {e}") from e
    return midi_output_path
