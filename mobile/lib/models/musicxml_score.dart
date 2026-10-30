import 'dart:math' as math;

import 'package:xml/xml.dart';

enum ScoreClef { treble, bass, alto, tenor, percussion }

class ScoreNote {
  const ScoreNote({
    required this.step,
    required this.octave,
    required this.alter,
    required this.startTick,
    required this.endTick,
    required this.noteType,
    required this.dots,
    required this.isRest,
    required this.accidental,
  });

  final String step;
  final int octave;
  final int alter;
  final int startTick;
  final int endTick;
  final String? noteType;
  final int dots;
  final bool isRest;
  final String? accidental;
}

class ScoreMeasure {
  const ScoreMeasure({
    required this.number,
    required this.startTick,
    required this.endTick,
    required this.fifths,
    required this.beats,
    required this.beatType,
    required this.clef,
    required this.notes,
  });

  final String number;
  final int startTick;
  final int endTick;
  final int fifths;
  final int beats;
  final int beatType;
  final ScoreClef clef;
  final List<ScoreNote> notes;
}

class MusicXmlScore {
  const MusicXmlScore({
    required this.measures,
    required this.ticksPerBeat,
  });

  final List<ScoreMeasure> measures;
  final int ticksPerBeat;

  factory MusicXmlScore.parse(
    String source, {
    required int ticksPerBeat,
  }) {
    if (ticksPerBeat <= 0) {
      throw const FormatException('La résolution MIDI doit être positive.');
    }

    final document = XmlDocument.parse(source);
    final part = _firstChild(document.rootElement, 'part');
    if (part == null) {
      throw const FormatException(
        'Le MusicXML ne contient aucune partie musicale.',
      );
    }

    var divisions = 1.0;
    var fifths = 0;
    var beats = 4;
    var beatType = 4;
    var clef = ScoreClef.treble;
    var clefLine = 2;
    var elapsedQuarterNotes = 0.0;
    final measures = <ScoreMeasure>[];

    for (final measure in _children(part, 'measure')) {
      var cursor = 0.0;
      var furthestCursor = 0.0;
      var previousNoteStart = 0.0;
      final notes = <ScoreNote>[];

      for (final element in measure.children.whereType<XmlElement>()) {
        if (element.name.local == 'attributes') {
          final divisionsText = _text(element, 'divisions');
          if (divisionsText != null) {
            divisions = double.tryParse(divisionsText) ?? 0;
            if (divisions <= 0) {
              throw const FormatException(
                'Le MusicXML contient une division temporelle invalide.',
              );
            }
          }
          final key = _firstChild(element, 'key');
          final fifthsText = key == null ? null : _text(key, 'fifths');
          if (fifthsText != null) {
            fifths = int.tryParse(fifthsText) ?? 0;
          }
          final time = _firstChild(element, 'time');
          final beatsText = time == null ? null : _text(time, 'beats');
          final beatTypeText = time == null ? null : _text(time, 'beat-type');
          if (beatsText != null) {
            beats = beatsText
                .split('+')
                .map((value) => int.tryParse(value) ?? 0)
                .fold(0, (total, value) => total + value);
          }
          if (beatTypeText != null) {
            beatType = int.tryParse(beatTypeText) ?? 0;
          }
          final clefElement = _firstChild(element, 'clef');
          if (clefElement != null) {
            final sign = _text(clefElement, 'sign');
            clefLine = int.tryParse(_text(clefElement, 'line') ?? '') ?? 2;
            clef = switch (sign) {
              'F' => ScoreClef.bass,
              'C' when clefLine == 3 => ScoreClef.alto,
              'C' => ScoreClef.tenor,
              'percussion' => ScoreClef.percussion,
              _ => ScoreClef.treble,
            };
          }
        } else if (element.name.local == 'backup' ||
            element.name.local == 'forward') {
          final duration =
              double.tryParse(_text(element, 'duration') ?? '') ?? 0;
          cursor += element.name.local == 'backup' ? -duration : duration;
          if (cursor < 0) {
            throw const FormatException(
              'Le MusicXML contient un déplacement de mesure invalide.',
            );
          }
          furthestCursor = math.max(furthestCursor, cursor);
        } else if (element.name.local == 'note') {
          final staff = int.tryParse(_text(element, 'staff') ?? '1') ?? 1;
          final isChord = _firstChild(element, 'chord') != null;
          final noteStart = isChord ? previousNoteStart : cursor;
          final duration =
              double.tryParse(_text(element, 'duration') ?? '') ?? 0;
          final pitch = _firstChild(element, 'pitch');
          final rest = _firstChild(element, 'rest') != null;
          final step = pitch == null ? null : _text(pitch, 'step');
          final octave =
              int.tryParse(pitch == null ? '' : _text(pitch, 'octave') ?? '');
          if (staff == 1 && (rest || (step != null && octave != null))) {
            final alter = int.tryParse(
                    pitch == null ? '' : _text(pitch, 'alter') ?? '') ??
                0;
            notes.add(ScoreNote(
              step: step ?? '',
              octave: octave ?? 0,
              alter: alter,
              startTick:
                  ((elapsedQuarterNotes + noteStart / divisions) * ticksPerBeat)
                      .round(),
              endTick:
                  ((elapsedQuarterNotes + (noteStart + duration) / divisions) *
                          ticksPerBeat)
                      .round(),
              noteType: _text(element, 'type'),
              dots: _children(element, 'dot').length,
              isRest: rest,
              accidental: _text(element, 'accidental'),
            ));
          }
          if (!isChord) {
            previousNoteStart = cursor;
            cursor += duration;
          }
          furthestCursor = math.max(furthestCursor, cursor);
        }
      }

      if (beats <= 0 || beatType <= 0) {
        throw const FormatException(
          'Le MusicXML contient une mesure invalide.',
        );
      }
      final expectedQuarterNotes = beats * 4 / beatType;
      final measureQuarterNotes =
          math.max(expectedQuarterNotes, furthestCursor / divisions);
      if (measureQuarterNotes <= 0) continue;

      final startTick = (elapsedQuarterNotes * ticksPerBeat).round();
      elapsedQuarterNotes += measureQuarterNotes;
      final endTick = (elapsedQuarterNotes * ticksPerBeat).round();
      measures.add(ScoreMeasure(
        number: measure.getAttribute('number') ?? '${measures.length + 1}',
        startTick: startTick,
        endTick: endTick,
        fifths: fifths,
        beats: beats,
        beatType: beatType,
        clef: clef,
        notes: List.unmodifiable(notes),
      ));
    }

    if (measures.isEmpty ||
        measures.every((measure) => measure.notes.isEmpty)) {
      throw const FormatException(
        'Le MusicXML ne contient aucune note exploitable sur la première portée.',
      );
    }
    return MusicXmlScore(
      measures: List.unmodifiable(measures),
      ticksPerBeat: ticksPerBeat,
    );
  }
}

XmlElement? _firstChild(XmlElement parent, String name) {
  for (final child in parent.children.whereType<XmlElement>()) {
    if (child.name.local == name) return child;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement parent, String name) =>
    parent.children.whereType<XmlElement>().where(
          (element) => element.name.local == name,
        );

String? _text(XmlElement parent, String name) =>
    _firstChild(parent, name)?.innerText.trim();
