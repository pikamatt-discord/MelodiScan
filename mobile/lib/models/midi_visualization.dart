import 'dart:typed_data';

import 'package:dart_midi_pro/dart_midi_pro.dart';

class MidiNote {
  const MidiNote({
    required this.pitch,
    required this.velocity,
    required this.startTick,
    required this.endTick,
    required this.channel,
  });

  final int pitch;
  final int velocity;
  final int startTick;
  final int endTick;
  final int channel;
}

class MidiProgramChange {
  const MidiProgramChange({
    required this.tick,
    required this.channel,
    required this.program,
  });

  final int tick;
  final int channel;
  final int program;
}

class MidiVisualization {
  const MidiVisualization({
    required this.notes,
    required this.programChanges,
    required this.trackNames,
    required this.ticksPerBeat,
    required this.totalTicks,
    required this.trackCount,
  });

  final List<MidiNote> notes;
  final List<MidiProgramChange> programChanges;
  final List<String?> trackNames;
  final int ticksPerBeat;
  final int totalTicks;
  final int trackCount;

  factory MidiVisualization.parse(
    Uint8List bytes, {
    int? trackIndex,
  }) {
    final midi = MidiParser().parseMidiFromBuffer(bytes);
    final ticksPerBeat = midi.header.ticksPerBeat;
    if (ticksPerBeat == null || ticksPerBeat <= 0) {
      throw const FormatException(
        'Le fichier MIDI utilise une division temporelle non prise en charge.',
      );
    }
    if (trackIndex != null &&
        (trackIndex < 0 || trackIndex >= midi.tracks.length)) {
      throw RangeError.range(
        trackIndex,
        0,
        midi.tracks.length - 1,
        'trackIndex',
      );
    }

    final notes = <MidiNote>[];
    final programChanges = <MidiProgramChange>[];
    final namesByTrack = [
      for (final track in midi.tracks) _trackName(track),
    ];
    var totalTicks = 0;

    for (var currentTrackIndex = 0;
        currentTrackIndex < midi.tracks.length;
        currentTrackIndex++) {
      final track = midi.tracks[currentTrackIndex];
      var tick = 0;
      final pendingNotes = <(int, int), List<(int, int)>>{};

      for (final event in track) {
        tick += event.deltaTime;
        if (trackIndex != null && currentTrackIndex != trackIndex) continue;

        if (event is ProgramChangeMidiEvent) {
          programChanges.add(MidiProgramChange(
            tick: tick,
            channel: event.channel,
            program: event.programNumber,
          ));
        } else if (event is NoteOnEvent && event.velocity > 0) {
          final key = (event.channel, event.noteNumber);
          pendingNotes.putIfAbsent(key, () => []).add((tick, event.velocity));
        } else if (event is NoteOffEvent ||
            (event is NoteOnEvent && event.velocity == 0)) {
          final channel = event is NoteOffEvent
              ? event.channel
              : (event as NoteOnEvent).channel;
          final pitch = event is NoteOffEvent
              ? event.noteNumber
              : (event as NoteOnEvent).noteNumber;
          final key = (channel, pitch);
          final starts = pendingNotes[key];
          if (starts == null || starts.isEmpty) continue;

          final (startTick, velocity) = starts.removeAt(0);
          notes.add(MidiNote(
            pitch: pitch,
            velocity: velocity,
            startTick: startTick,
            endTick: tick > startTick ? tick : startTick + 1,
            channel: channel,
          ));
        }
      }

      if (tick > totalTicks) totalTicks = tick;
      if (trackIndex != null && currentTrackIndex != trackIndex) continue;
      for (final entry in pendingNotes.entries) {
        for (final (startTick, velocity) in entry.value) {
          notes.add(MidiNote(
            pitch: entry.key.$2,
            velocity: velocity,
            startTick: startTick,
            endTick: tick > startTick ? tick : startTick + 1,
            channel: entry.key.$1,
          ));
        }
      }
    }

    notes.sort((a, b) => a.startTick.compareTo(b.startTick));
    programChanges.sort((a, b) => a.tick.compareTo(b.tick));
    if (notes.isEmpty) {
      throw const FormatException(
        'Le fichier MIDI ne contient aucune note à afficher.',
      );
    }

    return MidiVisualization(
      notes: List.unmodifiable(notes),
      programChanges: List.unmodifiable(programChanges),
      trackNames: List.unmodifiable(namesByTrack),
      ticksPerBeat: ticksPerBeat,
      totalTicks: totalTicks,
      trackCount: midi.tracks.length,
    );
  }
}

String? _trackName(List<MidiEvent> track) {
  for (final event in track) {
    if (event is TrackNameEvent) return event.text;
  }
  return null;
}
