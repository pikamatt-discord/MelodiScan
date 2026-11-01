import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/models/musicxml_score.dart';

void main() {
  test('preserves detected clef, key, meter, accidentals and note timing', () {
    const musicXml = '''
      <score-partwise>
        <part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
        <part id="P1">
          <measure number="7">
            <attributes>
              <divisions>24</divisions>
              <key><fifths>-2</fifths></key>
              <time><beats>3</beats><beat-type>8</beat-type></time>
              <clef><sign>F</sign><line>4</line></clef>
            </attributes>
            <note>
              <pitch><step>B</step><alter>-1</alter><octave>3</octave></pitch>
              <duration>12</duration><type>eighth</type>
              <accidental>flat</accidental>
            </note>
            <note>
              <pitch><step>B</step><alter>0</alter><octave>3</octave></pitch>
              <duration>12</duration><type>eighth</type>
              <accidental>natural</accidental>
            </note>
          </measure>
        </part>
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);
    final measure = score.measures.single;

    expect(measure.number, '7');
    expect(measure.clef, ScoreClef.bass);
    expect(measure.fifths, -2);
    expect(measure.beats, 3);
    expect(measure.beatType, 8);
    expect(measure.startTick, 0);
    expect(measure.endTick, 144);
    expect(measure.notes, hasLength(2));
    expect(measure.notes[0].startTick, 0);
    expect(measure.notes[0].endTick, 48);
    expect(measure.notes[0].accidental, 'flat');
    expect(measure.notes[1].startTick, 48);
    expect(measure.notes[1].endTick, 96);
    expect(measure.notes[1].accidental, 'natural');
  });

  test('recognizes percussion parts and keeps unpitched staff notes', () {
    const musicXml = '''
      <score-partwise>
        <part-list>
          <score-part id="P1">
            <part-name>Ensemble</part-name>
            <midi-instrument id="I1">
              <midi-channel>10</midi-channel>
              <midi-program>1</midi-program>
            </midi-instrument>
          </score-part>
        </part-list>
        <part id="P1">
          <measure number="1">
            <attributes>
              <divisions>24</divisions>
              <clef><sign>percussion</sign><line>2</line></clef>
            </attributes>
            <note>
              <unpitched><display-step>F</display-step><display-octave>4</display-octave></unpitched>
              <duration>24</duration><type>quarter</type>
            </note>
          </measure>
        </part>
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);

    expect(score.parts.single.isPercussion, isTrue);
    expect(score.parts.single.instrumentProgram, 0);
    expect(score.measures.single.clef, ScoreClef.percussion);
    expect(score.measures.single.notes, hasLength(1));
    expect(score.measures.single.notes.single.step, 'F');
    expect(score.measures.single.notes.single.octave, 4);
  });

  test('places chord tones together and advances backup voices correctly', () {
    const musicXml = '''
      <score-partwise>
        <part id="P1">
          <measure number="1">
            <attributes>
              <divisions>24</divisions>
              <time><beats>4</beats><beat-type>4</beat-type></time>
            </attributes>
            <note>
              <pitch><step>C</step><octave>4</octave></pitch>
              <duration>24</duration><type>quarter</type>
            </note>
            <note>
              <chord/>
              <pitch><step>E</step><octave>4</octave></pitch>
              <duration>24</duration><type>quarter</type>
            </note>
            <backup><duration>24</duration></backup>
            <note>
              <pitch><step>G</step><octave>3</octave></pitch>
              <duration>12</duration><type>eighth</type>
            </note>
          </measure>
        </part>
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);
    final notes = score.measures.single.notes;

    expect(notes.map((note) => note.startTick), [0, 0, 0]);
    expect(notes.map((note) => note.endTick), [96, 96, 48]);
  });

  test('selects piano part and preserves both staves and tuplet timing', () {
    const musicXml = '''
      <score-partwise>
        <part-list>
          <score-part id="P1"><part-name>Flute</part-name></score-part>
          <score-part id="P2"><part-name>Piano</part-name></score-part>
        </part-list>
        <part id="P1">
          <measure number="1">
            <note>
              <pitch><step>A</step><octave>4</octave></pitch>
              <duration>24</duration><type>quarter</type>
            </note>
          </measure>
        </part>
        <part id="P2">
          <measure number="1">
            <attributes>
              <divisions>24</divisions>
              <staves>2</staves>
              <key><fifths>1</fifths></key>
              <time><beats>4</beats><beat-type>4</beat-type></time>
              <clef number="1"><sign>G</sign><line>2</line></clef>
              <clef number="2"><sign>F</sign><line>4</line></clef>
            </attributes>
            <note>
              <pitch><step>F</step><alter>1</alter><octave>4</octave></pitch>
              <duration>8</duration><type>eighth</type>
              <time-modification>
                <actual-notes>3</actual-notes><normal-notes>2</normal-notes>
              </time-modification>
              <staff>1</staff><voice>1</voice>
            </note>
            <backup><duration>8</duration></backup>
            <note>
              <pitch><step>C</step><octave>3</octave></pitch>
              <duration>8</duration><type>eighth</type>
              <staff>2</staff><voice>2</voice>
            </note>
          </measure>
        </part>
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);

    expect(score.hasGrandStaff, isTrue);
    expect(score.measures.single.staves, 2);
    expect(score.measures.single.clefForStaff(1), ScoreClef.treble);
    expect(score.measures.single.clefForStaff(2), ScoreClef.bass);
    expect(score.measures.single.notes, hasLength(2));
    expect(score.measures.single.notes.map((note) => note.staff), [1, 2]);
    expect(score.measures.single.notes.first.actualNotes, 3);
    expect(score.measures.single.notes.first.normalNotes, 2);
    expect(score.measures.single.notes.map((note) => note.startTick), [0, 0]);
    expect(score.measures.single.notes.map((note) => note.endTick), [32, 32]);
  });

  test('rejects MusicXML with no part', () {
    expect(
      () => MusicXmlScore.parse(
        '<score-partwise/>',
        ticksPerBeat: 96,
      ),
      throwsFormatException,
    );
  });

  test('exposes all parts, selects grand staff automatically and reads tempos',
      () {
    const musicXml = '''
      <score-partwise>
        <part-list>
          <score-part id="P1"><part-name>Flute</part-name></score-part>
          <score-part id="P2"><part-name>Piano</part-name></score-part>
        </part-list>
        <part id="P1">
          <measure number="1">
            <attributes><divisions>24</divisions></attributes>
            <direction><direction-type><metronome>
              <beat-unit>eighth</beat-unit><per-minute>120</per-minute>
            </metronome></direction-type></direction>
            <note><pitch><step>A</step><octave>4</octave></pitch>
              <duration>96</duration><type>whole</type></note>
          </measure>
          <measure number="2">
            <direction><sound tempo="90"/></direction>
            <note><pitch><step>B</step><octave>4</octave></pitch>
              <duration>96</duration><type>whole</type></note>
          </measure>
        </part>
        <part id="P2">
          <measure number="1">
            <attributes>
              <divisions>24</divisions><staves>2</staves>
              <time><beats>4</beats><beat-type>4</beat-type></time>
              <clef number="1"><sign>G</sign><line>2</line></clef>
              <clef number="2"><sign>F</sign><line>4</line></clef>
            </attributes>
            <note><pitch><step>C</step><octave>4</octave></pitch>
              <duration>96</duration><type>whole</type><staff>1</staff></note>
          </measure>
          <measure number="2">
            <note><pitch><step>D</step><octave>4</octave></pitch>
              <duration>96</duration><type>whole</type><staff>1</staff></note>
          </measure>
        </part>
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);

    expect(score.parts.map((part) => part.name), ['Flute', 'Piano']);
    expect(score.parts.last.staves, 2);
    expect(score.selectedPartId, 'P2');
    expect(score.hasGrandStaff, isTrue);
    expect(score.tempoChanges.map((tempo) => tempo.bpm), [60, 90]);
    expect(score.tempoChanges.map((tempo) => tempo.tick), [0, 384]);

    final flute = MusicXmlScore.parse(
      musicXml,
      ticksPerBeat: 96,
      selectedPartId: 'P1',
    );
    expect(flute.selectedPartId, 'P1');
    expect(flute.hasGrandStaff, isFalse);
    expect(flute.measures, hasLength(2));
    expect(flute.tempoChanges.map((tempo) => tempo.bpm), [60, 90]);
  });

  test('reads printed credit title and measure-level sound tempos', () {
    const musicXml = '''
      <score-partwise>
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
      </score-partwise>
    ''';

    final score = MusicXmlScore.parse(musicXml, ticksPerBeat: 96);

    expect(score.title, 'Printed Score Title');
    expect(score.tempoChanges.map((tempo) => tempo.bpm), [96, 112]);
    expect(score.tempoChanges.map((tempo) => tempo.tick), [0, 384]);
  });
}
