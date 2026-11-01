import os
import subprocess
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

def convert_musicxml_to_midi(musicxml_path: str, midi_output_path: str) -> str:
    try:
        import partitura
        score = partitura.load_musicxml(musicxml_path)
        partitura.save_score_midi(score, midi_output_path)
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
