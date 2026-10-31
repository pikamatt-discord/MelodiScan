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

class ScorePartInfo {
  const ScorePartInfo({
    required this.id,
    required this.name,
    required this.staves,
    required this.instrumentProgram,
  });

  final String id;
  final String name;
  final int staves;
  final int? instrumentProgram;
}

class ScoreCreator {
  const ScoreCreator({
    required this.name,
    required this.role,
  });

  final String name;
  final String role;
}

class ScoreTempoChange {
  const ScoreTempoChange({
    required this.tick,
    required this.bpm,
  });

  final int tick;
  final double bpm;
}

class MusicXmlScore {
  const MusicXmlScore({
    required this.measures,
    required this.ticksPerBeat,
    required this.parts,
    required this.selectedPartId,
    required this.tempoChanges,
    required this.title,
    required this.creators,
  });

  final List<ScoreMeasure> measures;
  final int ticksPerBeat;
  final List<ScorePartInfo> parts;
  final String selectedPartId;
  final List<ScoreTempoChange> tempoChanges;
  final String? title;
  final List<ScoreCreator> creators;

  bool get hasGrandStaff => measures.any(
        (measure) =>
            measure.staves > 1 || measure.notes.any((note) => note.staff > 1),
      );

  factory MusicXmlScore.parse(
    String source, {
    required int ticksPerBeat,
    String? selectedPartId,
  }) {
    if (ticksPerBeat <= 0) {
      throw const FormatException('La résolution MIDI doit être positive.');
    }

    final document = XmlDocument.parse(source);
    final work = _firstChild(document.rootElement, 'work');
    final title = _text(work ?? document.rootElement, 'work-title') ??
        _text(document.rootElement, 'movement-title');
    final identification = _firstChild(document.rootElement, 'identification');
    final creators = <ScoreCreator>[
      if (identification != null)
        for (final creator in _children(identification, 'creator'))
          if (creator.innerText.trim().isNotEmpty)
            ScoreCreator(
              name: creator.innerText.trim(),
              role: creator.getAttribute('type')?.trim().isNotEmpty == true
                  ? creator.getAttribute('type')!.trim()
                  : 'creator',
            ),
    ];
    final parts = _children(document.rootElement, 'part').toList();
    if (parts.isEmpty) {
      throw const FormatException(
        'Le MusicXML ne contient aucune partie musicale.',
      );
    }
    final partNames = <String, String>{};
    final partPrograms = <String, int>{};
    final partList = _firstChild(document.rootElement, 'part-list');
    if (partList != null) {
      for (final scorePart in _children(partList, 'score-part')) {
        final id = scorePart.getAttribute('id');
        if (id == null) continue;
        final name = _text(scorePart, 'part-name') ??
            _text(scorePart, 'part-abbreviation');
        if (name != null) partNames[id] = name;
        final midiProgram = int.tryParse(
          _text(_firstChild(scorePart, 'midi-instrument') ?? scorePart,
                  'midi-program') ??
              '',
        );
        if (midiProgram != null) {
          partPrograms[id] = (midiProgram - 1).clamp(0, 127).toInt();
        }
      }
    }

    XmlElement? selectedPart;
    if (selectedPartId == null) {
      selectedPart =
          parts.firstWhere(_hasMultipleStaves, orElse: () => parts.first);
    } else {
      for (final candidate in parts) {
        if ((candidate.getAttribute('id') ??
                'part-${parts.indexOf(candidate) + 1}') ==
            selectedPartId) {
          selectedPart = candidate;
          break;
        }
      }
    }
    if (selectedPart == null) {
      throw FormatException('La partie "$selectedPartId" est introuvable.');
    }
    final part = selectedPart;
    final partInfos = <ScorePartInfo>[];
    for (var index = 0; index < parts.length; index++) {
      final id = parts[index].getAttribute('id') ?? 'part-${index + 1}';
      partInfos.add(ScorePartInfo(
        id: id,
        name: partNames[id] ?? 'Partie ${index + 1}',
        staves: _staffCount(parts[index]),
        instrumentProgram: partPrograms[id],
      ));
    }
    final tempoChanges = _parseTempoChanges(parts, ticksPerBeat);

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
          furthestCursor = math.max(
            furthestCursor,
            math.max(cursor, noteStart + duration),
          );
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
      parts: List.unmodifiable(partInfos),
      selectedPartId: part.getAttribute('id') ?? 'part-1',
      tempoChanges: List.unmodifiable(tempoChanges),
      title: title,
      creators: List.unmodifiable(creators),
    );
  }
}

List<ScoreTempoChange> _parseTempoChanges(
  List<XmlElement> parts,
  int ticksPerBeat,
) {
  final changes = <(int, double), ScoreTempoChange>{};
  for (final part in parts) {
    var divisions = 1.0;
    var beats = 4;
    var beatType = 4;
    var elapsedQuarterNotes = 0.0;

    for (final measure in _children(part, 'measure')) {
      var cursor = 0.0;
      var furthestCursor = 0.0;
      var previousNoteStart = 0.0;
      for (final element in measure.children.whereType<XmlElement>()) {
        switch (element.name.local) {
          case 'attributes':
            final divisionsText = _text(element, 'divisions');
            if (divisionsText != null) {
              final parsedDivisions = double.tryParse(divisionsText);
              if (parsedDivisions == null || parsedDivisions <= 0) {
                throw const FormatException(
                  'Le MusicXML contient une division temporelle invalide.',
                );
              }
              divisions = parsedDivisions;
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
          case 'backup':
          case 'forward':
            final duration =
                double.tryParse(_text(element, 'duration') ?? '') ?? 0;
            cursor += element.name.local == 'backup' ? -duration : duration;
            furthestCursor = math.max(furthestCursor, cursor);
          case 'note':
            final duration =
                double.tryParse(_text(element, 'duration') ?? '') ?? 0;
            final isChord = _firstChild(element, 'chord') != null;
            if (!isChord) {
              previousNoteStart = cursor;
              cursor += duration;
            }
            furthestCursor = math.max(
              furthestCursor,
              math.max(cursor, previousNoteStart + duration),
            );
          case 'direction':
            final bpm = _tempoFromDirection(element);
            if (bpm != null) {
              final offset =
                  double.tryParse(_text(element, 'offset') ?? '0') ?? 0;
              final tick =
                  ((elapsedQuarterNotes + (cursor + offset) / divisions) *
                          ticksPerBeat)
                      .round();
              changes[(tick, bpm)] = ScoreTempoChange(tick: tick, bpm: bpm);
            }
        }
      }

      final expectedQuarterNotes =
          beats > 0 && beatType > 0 ? beats * 4 / beatType : 0.0;
      elapsedQuarterNotes += math.max(
        expectedQuarterNotes,
        furthestCursor / divisions,
      );
    }
  }
  return changes.values.toList()
    ..sort((a, b) {
      final tickOrder = a.tick.compareTo(b.tick);
      return tickOrder != 0 ? tickOrder : a.bpm.compareTo(b.bpm);
    });
}

int _staffCount(XmlElement part) {
  var staves = 1;
  for (final measure in _children(part, 'measure')) {
    for (final attributes in _children(measure, 'attributes')) {
      staves = math.max(
        staves,
        int.tryParse(_text(attributes, 'staves') ?? '') ?? 1,
      );
      for (final clef in _children(attributes, 'clef')) {
        staves = math.max(
          staves,
          int.tryParse(clef.getAttribute('number') ?? '') ?? 1,
        );
      }
    }
    for (final note in _children(measure, 'note')) {
      staves = math.max(staves, int.tryParse(_text(note, 'staff') ?? '') ?? 1);
    }
  }
  return staves;
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

double? _tempoFromDirection(XmlElement direction) {
  final sound = _firstChild(direction, 'sound');
  final soundTempo = double.tryParse(sound?.getAttribute('tempo') ?? '');
  if (soundTempo != null && soundTempo >= 20 && soundTempo <= 400) {
    return soundTempo;
  }

  for (final metronome in direction.descendants.whereType<XmlElement>()) {
    if (metronome.name.local != 'metronome') continue;
    final bpm = double.tryParse(_text(metronome, 'per-minute') ?? '');
    if (bpm == null) continue;
    final quarterNotesPerUnit = switch (_text(metronome, 'beat-unit')) {
      'whole' => 4.0,
      'half' => 2.0,
      'quarter' => 1.0,
      'eighth' => 0.5,
      '16th' => 0.25,
      '32nd' => 0.125,
      '64th' => 0.0625,
      _ => null,
    };
    if (quarterNotesPerUnit == null) continue;
    final dots = _children(metronome, 'beat-unit-dot').length;
    final converted = bpm * quarterNotesPerUnit * (2 - math.pow(0.5, dots));
    if (converted >= 20 && converted <= 400) return converted.toDouble();
  }
  return null;
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
