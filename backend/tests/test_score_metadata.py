from app.score_metadata import analyze_musicxml_file


def test_metadata_comes_from_musicxml_content_not_source_filename(tmp_path):
    source = tmp_path / "filename-must-not-be-a-title.musicxml"
    source.write_text(
        """<?xml version="1.0"?>
        <score-partwise>
          <work><work-title>Title printed in the score</work-title></work>
          <identification>
            <creator type="composer">Document Composer</creator>
          </identification>
          <part-list>
            <score-part id="P1">
              <part-name>Flute</part-name>
              <midi-instrument id="I1"><midi-program>74</midi-program></midi-instrument>
            </score-part>
            <score-part id="P2"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>24</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef>
              </attributes>
              <direction>
                <direction-type>
                  <metronome>
                    <beat-unit>eighth</beat-unit>
                    <per-minute>120</per-minute>
                  </metronome>
                </direction-type>
                <sound tempo="60"/>
              </direction>
              <note>
                <pitch><step>C</step><octave>5</octave></pitch>
                <duration>24</duration><type>quarter</type>
              </note>
            </measure>
            <measure number="2">
              <direction><sound tempo="90"/></direction>
              <note>
                <pitch><step>D</step><octave>5</octave></pitch>
                <duration>24</duration><type>quarter</type>
              </note>
            </measure>
          </part>
          <part id="P2">
            <measure number="1">
              <attributes>
                <divisions>24</divisions><staves>2</staves>
                <clef number="1"><sign>G</sign><line>2</line></clef>
                <clef number="2"><sign>F</sign><line>4</line></clef>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>24</duration><type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>""",
        encoding="utf-8",
    )

    metadata = analyze_musicxml_file(str(source))

    assert metadata["title"] == "Title printed in the score"
    assert metadata["creators"] == [
        {"role": "composer", "name": "Document Composer"}
    ]
    assert metadata["measure_count"] == 2
    assert metadata["parts"][0]["name"] == "Flute"
    assert metadata["parts"][0]["instrument_program"] == 73
    assert metadata["parts"][1]["staves"] == 2
    assert metadata["tempo_changes"] == [
        {"quarter_position": 0.0, "bpm": 60.0, "measure": 1},
        {"quarter_position": 4.0, "bpm": 90.0, "measure": 2},
    ]


def test_missing_document_title_stays_unknown_instead_of_using_filename(tmp_path):
    source = tmp_path / "never-use-this-filename.musicxml"
    source.write_text(
        """<score-partwise>
          <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
          <part id="P1"><measure number="1">
            <attributes><divisions>1</divisions></attributes>
            <note><pitch><step>C</step><octave>4</octave></pitch>
              <duration>1</duration><type>quarter</type></note>
          </measure></part>
        </score-partwise>""",
        encoding="utf-8",
    )

    metadata = analyze_musicxml_file(str(source))

    assert metadata["title"] is None
    assert "never-use-this-filename" not in repr(metadata)
