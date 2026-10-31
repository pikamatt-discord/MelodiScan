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
}
