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


def test_extracts_credit_title_and_measure_level_sound_tempos(tmp_path):
    source = tmp_path / "filename-is-not-used.musicxml"
    source.write_text(
        """<score-partwise>
          <credit page="1">
            <credit-type>title</credit-type>
            <credit-words>Printed Score Title</credit-words>
          </credit>
          <credit page="1">
            <credit-type>composer</credit-type>
            <credit-words>Not the title</credit-words>
          </credit>
          <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>24</divisions>
                <time><beats>4</beats><beat-type>4</beat-type></time>
              </attributes>
              <sound tempo="96"/>
              <note><pitch><step>C</step><octave>4</octave></pitch>
                <duration>24</duration><type>quarter</type></note>
            </measure>
            <measure number="2">
              <sound tempo="112"/>
              <note><pitch><step>D</step><octave>4</octave></pitch>
                <duration>24</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>""",
        encoding="utf-8",
    )

    metadata = analyze_musicxml_file(str(source))

    assert metadata["title"] == "Printed Score Title"
    assert metadata["tempo_changes"] == [
        {"quarter_position": 0.0, "bpm": 96.0, "measure": 1},
        {"quarter_position": 4.0, "bpm": 112.0, "measure": 2},
    ]


def test_extracts_dynamic_signatures_clefs_and_percussion_identity(tmp_path):
    source = tmp_path / "not-the-instrument-name.musicxml"
    source.write_text(
        """<score-partwise>
          <part-list>
            <score-part id="P1">
              <part-name>Ensemble</part-name>
              <score-instrument id="I1"><instrument-name>Drum Kit</instrument-name></score-instrument>
              <midi-instrument id="I1"><midi-channel>10</midi-channel><midi-program>1</midi-program></midi-instrument>
            </score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>24</divisions>
                <key><fifths>0</fifths></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>percussion</sign><line>2</line></clef>
              </attributes>
              <note><unpitched><display-step>F</display-step><display-octave>4</display-octave></unpitched>
                <duration>24</duration><type>quarter</type></note>
            </measure>
            <measure number="2">
              <attributes>
                <key><fifths>-2</fifths></key>
                <time><beats>3</beats><beat-type>4</beat-type></time>
                <clef><sign>F</sign><line>4</line></clef>
              </attributes>
              <note><pitch><step>C</step><octave>4</octave></pitch>
                <duration>24</duration><type>quarter</type></note>
            </measure>
          </part>
        </score-partwise>""",
        encoding="utf-8",
    )

    metadata = analyze_musicxml_file(str(source))
    part = metadata["parts"][0]

    assert part["instrument_name"] == "Drum Kit"
    assert part["instrument_program"] == 0
    assert part["is_percussion"] is True
    assert part["clefs"] == {"1": "percussion"}
    assert part["key_fifths"] == 0
    assert part["meter"] == {"beats": "4", "beat_type": "4"}
    assert part["key_changes"] == [
        {"quarter_position": 0.0, "measure": 1, "fifths": 0},
        {"quarter_position": 4.0, "measure": 2, "fifths": -2},
    ]
    assert part["meter_changes"] == [
        {
            "quarter_position": 0.0,
            "measure": 1,
            "beats": "4",
            "beat_type": "4",
        },
        {
            "quarter_position": 4.0,
            "measure": 2,
            "beats": "3",
            "beat_type": "4",
        },
    ]
    assert part["clef_changes"] == [
        {
            "quarter_position": 0.0,
            "measure": 1,
            "staff": "1",
            "clef": "percussion",
        },
        {
            "quarter_position": 4.0,
            "measure": 2,
            "staff": "1",
            "clef": "bass",
        },
    ]
