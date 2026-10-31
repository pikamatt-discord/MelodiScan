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
    required this.staff,
    required this.voice,
    required this.actualNotes,
    required this.normalNotes,
    required this.isGrace,
    required this.ties,
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
  final int staff;
  final String voice;
  final int? actualNotes;
  final int? normalNotes;
  final bool isGrace;
  final Set<String> ties;
}

class ScoreMeasure {
  const ScoreMeasure({
    required this.number,
    required this.startTick,
    required this.endTick,
    required this.fifths,
    required this.beats,
    required this.beatType,
    required this.staves,
    required this.clefs,
    required this.notes,
  });

  final String number;
  final int startTick;
  final int endTick;
  final int fifths;
  final int beats;
  final int beatType;
  final int staves;
  final Map<int, ScoreClef> clefs;
  final List<ScoreNote> notes;

  ScoreClef get clef => clefs[1] ?? ScoreClef.treble;

  ScoreClef clefForStaff(int staff) =>
      clefs[staff] ?? (staff == 2 ? ScoreClef.bass : clef);
}

class MusicXmlScore {
  const MusicXmlScore({
    required this.measures,
    required this.ticksPerBeat,
  });

  final List<ScoreMeasure> measures;
  final int ticksPerBeat;

  bool get hasGrandStaff => measures.any(
        (measure) =>
            measure.staves > 1 || measure.notes.any((note) => note.staff > 1),
      );

  factory MusicXmlScore.parse(
    String source, {
    required int ticksPerBeat,
  }) {
    if (ticksPerBeat <= 0) {
      throw const FormatException('La résolution MIDI doit être positive.');
    }

    final document = XmlDocument.parse(source);
    final parts = _children(document.rootElement, 'part').toList();
    if (parts.isEmpty) {
      throw const FormatException(
        'Le MusicXML ne contient aucune partie musicale.',
      );
    }
    final part = parts.firstWhere(
      _hasMultipleStaves,
      orElse: () => parts.first,
    );

    var divisions = 1.0;
    var fifths = 0;
    var beats = 4;
    var beatType = 4;
    var staves = 1;
    final clefs = <int, ScoreClef>{1: ScoreClef.treble};
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
          final stavesText = _text(element, 'staves');
          if (stavesText != null) {
            staves = int.tryParse(stavesText) ?? staves;
          }
          for (final clefElement in _children(element, 'clef')) {
            final staff =
                int.tryParse(clefElement.getAttribute('number') ?? '') ?? 1;
            clefs[staff] = _parseClef(clefElement);
            staves = math.max(staves, staff);
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
          staves = math.max(staves, staff);
          final isChord = _firstChild(element, 'chord') != null;
          final noteStart = isChord ? previousNoteStart : cursor;
          final duration =
              double.tryParse(_text(element, 'duration') ?? '') ?? 0;
          final pitch = _firstChild(element, 'pitch');
          final rest = _firstChild(element, 'rest') != null;
          final step = pitch == null ? null : _text(pitch, 'step');
          final octave =
              int.tryParse(pitch == null ? '' : _text(pitch, 'octave') ?? '');
          if (rest || (step != null && octave != null)) {
            final alter = int.tryParse(
                    pitch == null ? '' : _text(pitch, 'alter') ?? '') ??
                0;
            final timeModification = _firstChild(element, 'time-modification');
            final actualNotes = int.tryParse(
              timeModification == null
                  ? ''
                  : _text(timeModification, 'actual-notes') ?? '',
            );
            final normalNotes = int.tryParse(
              timeModification == null
                  ? ''
                  : _text(timeModification, 'normal-notes') ?? '',
            );
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
              staff: staff,
              voice: _text(element, 'voice') ?? '1',
              actualNotes: actualNotes,
              normalNotes: normalNotes,
              isGrace: _firstChild(element, 'grace') != null,
              ties: {
                for (final tie in _children(element, 'tie'))
                  if (tie.getAttribute('type') case final type?) type,
              },
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
        staves: staves,
        clefs: Map.unmodifiable(Map<int, ScoreClef>.of(clefs)),
        notes: List.unmodifiable(notes),
      ));
    }

    if (measures.isEmpty ||
        measures.every((measure) => measure.notes.isEmpty)) {
      throw const FormatException(
        'Le MusicXML ne contient aucune note exploitable dans la partie principale.',
      );
    }
    return MusicXmlScore(
      measures: List.unmodifiable(measures),
      ticksPerBeat: ticksPerBeat,
    );
  }
}

bool _hasMultipleStaves(XmlElement part) {
  for (final measure in _children(part, 'measure')) {
    for (final attributes in _children(measure, 'attributes')) {
      if ((int.tryParse(_text(attributes, 'staves') ?? '') ?? 1) > 1) {
        return true;
      }
    }
    for (final note in _children(measure, 'note')) {
      if ((int.tryParse(_text(note, 'staff') ?? '') ?? 1) > 1) {
        return true;
      }
    }
  }
  return false;
}

ScoreClef _parseClef(XmlElement clef) {
  final sign = _text(clef, 'sign');
  final line = int.tryParse(_text(clef, 'line') ?? '') ?? 2;
  return switch (sign) {
    'F' => ScoreClef.bass,
    'C' when line == 3 => ScoreClef.alto,
    'C' => ScoreClef.tenor,
    'percussion' => ScoreClef.percussion,
    _ => ScoreClef.treble,
  };
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
