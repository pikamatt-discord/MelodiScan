import 'dart:typed_data';

import 'package:dart_midi_pro/dart_midi_pro.dart';

class GeneralMidiInstrument {
  const GeneralMidiInstrument(this.program, this.name);

  final int program;
  final String name;

  static const all = <GeneralMidiInstrument>[
    GeneralMidiInstrument(0, 'Acoustic Grand Piano'),
    GeneralMidiInstrument(1, 'Bright Acoustic Piano'),
    GeneralMidiInstrument(2, 'Electric Grand Piano'),
    GeneralMidiInstrument(3, 'Honky-tonk Piano'),
    GeneralMidiInstrument(4, 'Electric Piano 1'),
    GeneralMidiInstrument(5, 'Electric Piano 2'),
    GeneralMidiInstrument(6, 'Harpsichord'),
    GeneralMidiInstrument(7, 'Clavinet'),
    GeneralMidiInstrument(8, 'Celesta'),
    GeneralMidiInstrument(9, 'Glockenspiel'),
    GeneralMidiInstrument(10, 'Music Box'),
    GeneralMidiInstrument(11, 'Vibraphone'),
    GeneralMidiInstrument(12, 'Marimba'),
    GeneralMidiInstrument(13, 'Xylophone'),
    GeneralMidiInstrument(14, 'Tubular Bells'),
    GeneralMidiInstrument(15, 'Dulcimer'),
    GeneralMidiInstrument(16, 'Drawbar Organ'),
    GeneralMidiInstrument(17, 'Percussive Organ'),
    GeneralMidiInstrument(18, 'Rock Organ'),
    GeneralMidiInstrument(19, 'Church Organ'),
    GeneralMidiInstrument(20, 'Reed Organ'),
    GeneralMidiInstrument(21, 'Accordion'),
    GeneralMidiInstrument(22, 'Harmonica'),
    GeneralMidiInstrument(23, 'Tango Accordion'),
    GeneralMidiInstrument(24, 'Acoustic Guitar (nylon)'),
    GeneralMidiInstrument(25, 'Acoustic Guitar (steel)'),
    GeneralMidiInstrument(26, 'Electric Guitar (jazz)'),
    GeneralMidiInstrument(27, 'Electric Guitar (clean)'),
    GeneralMidiInstrument(28, 'Electric Guitar (muted)'),
    GeneralMidiInstrument(29, 'Overdriven Guitar'),
    GeneralMidiInstrument(30, 'Distortion Guitar'),
    GeneralMidiInstrument(31, 'Guitar harmonics'),
    GeneralMidiInstrument(32, 'Acoustic Bass'),
    GeneralMidiInstrument(33, 'Electric Bass (finger)'),
    GeneralMidiInstrument(34, 'Electric Bass (pick)'),
    GeneralMidiInstrument(35, 'Fretless Bass'),
    GeneralMidiInstrument(36, 'Slap Bass 1'),
    GeneralMidiInstrument(37, 'Slap Bass 2'),
    GeneralMidiInstrument(38, 'Synth Bass 1'),
    GeneralMidiInstrument(39, 'Synth Bass 2'),
    GeneralMidiInstrument(40, 'Violin'),
    GeneralMidiInstrument(41, 'Viola'),
    GeneralMidiInstrument(42, 'Cello'),
    GeneralMidiInstrument(43, 'Contrabass'),
    GeneralMidiInstrument(44, 'Tremolo Strings'),
    GeneralMidiInstrument(45, 'Pizzicato Strings'),
    GeneralMidiInstrument(46, 'Orchestral Harp'),
    GeneralMidiInstrument(47, 'Timpani'),
    GeneralMidiInstrument(48, 'String Ensemble 1'),
    GeneralMidiInstrument(49, 'String Ensemble 2'),
    GeneralMidiInstrument(50, 'SynthStrings 1'),
    GeneralMidiInstrument(51, 'SynthStrings 2'),
    GeneralMidiInstrument(52, 'Choir Aahs'),
    GeneralMidiInstrument(53, 'Voice Oohs'),
    GeneralMidiInstrument(54, 'Synth Voice'),
    GeneralMidiInstrument(55, 'Orchestra Hit'),
    GeneralMidiInstrument(56, 'Trumpet'),
    GeneralMidiInstrument(57, 'Trombone'),
    GeneralMidiInstrument(58, 'Tuba'),
    GeneralMidiInstrument(59, 'Muted Trumpet'),
    GeneralMidiInstrument(60, 'French Horn'),
    GeneralMidiInstrument(61, 'Brass Section'),
    GeneralMidiInstrument(62, 'SynthBrass 1'),
    GeneralMidiInstrument(63, 'SynthBrass 2'),
    GeneralMidiInstrument(64, 'Soprano Sax'),
    GeneralMidiInstrument(65, 'Alto Sax'),
    GeneralMidiInstrument(66, 'Tenor Sax'),
    GeneralMidiInstrument(67, 'Baritone Sax'),
    GeneralMidiInstrument(68, 'Oboe'),
    GeneralMidiInstrument(69, 'English Horn'),
    GeneralMidiInstrument(70, 'Bassoon'),
    GeneralMidiInstrument(71, 'Clarinet'),
    GeneralMidiInstrument(72, 'Piccolo'),
    GeneralMidiInstrument(73, 'Flute'),
    GeneralMidiInstrument(74, 'Recorder'),
    GeneralMidiInstrument(75, 'Pan Flute'),
    GeneralMidiInstrument(76, 'Blown Bottle'),
    GeneralMidiInstrument(77, 'Shakuhachi'),
    GeneralMidiInstrument(78, 'Whistle'),
    GeneralMidiInstrument(79, 'Ocarina'),
    GeneralMidiInstrument(80, 'Lead 1 (square)'),
    GeneralMidiInstrument(81, 'Lead 2 (sawtooth)'),
    GeneralMidiInstrument(82, 'Lead 3 (calliope)'),
    GeneralMidiInstrument(83, 'Lead 4 (chiff)'),
    GeneralMidiInstrument(84, 'Lead 5 (charang)'),
    GeneralMidiInstrument(85, 'Lead 6 (voice)'),
    GeneralMidiInstrument(86, 'Lead 7 (fifths)'),
    GeneralMidiInstrument(87, 'Lead 8 (bass + lead)'),
    GeneralMidiInstrument(88, 'Pad 1 (new age)'),
    GeneralMidiInstrument(89, 'Pad 2 (warm)'),
    GeneralMidiInstrument(90, 'Pad 3 (polysynth)'),
    GeneralMidiInstrument(91, 'Pad 4 (choir)'),
    GeneralMidiInstrument(92, 'Pad 5 (bowed)'),
    GeneralMidiInstrument(93, 'Pad 6 (metallic)'),
    GeneralMidiInstrument(94, 'Pad 7 (halo)'),
    GeneralMidiInstrument(95, 'Pad 8 (sweep)'),
    GeneralMidiInstrument(96, 'FX 1 (rain)'),
    GeneralMidiInstrument(97, 'FX 2 (soundtrack)'),
    GeneralMidiInstrument(98, 'FX 3 (crystal)'),
    GeneralMidiInstrument(99, 'FX 4 (atmosphere)'),
    GeneralMidiInstrument(100, 'FX 5 (brightness)'),
    GeneralMidiInstrument(101, 'FX 6 (goblins)'),
    GeneralMidiInstrument(102, 'FX 7 (echoes)'),
    GeneralMidiInstrument(103, 'FX 8 (sci-fi)'),
    GeneralMidiInstrument(104, 'Sitar'),
    GeneralMidiInstrument(105, 'Banjo'),
    GeneralMidiInstrument(106, 'Shamisen'),
    GeneralMidiInstrument(107, 'Koto'),
    GeneralMidiInstrument(108, 'Kalimba'),
    GeneralMidiInstrument(109, 'Bag pipe'),
    GeneralMidiInstrument(110, 'Fiddle'),
    GeneralMidiInstrument(111, 'Shanai'),
    GeneralMidiInstrument(112, 'Tinkle Bell'),
    GeneralMidiInstrument(113, 'Agogo'),
    GeneralMidiInstrument(114, 'Steel Drums'),
    GeneralMidiInstrument(115, 'Woodblock'),
    GeneralMidiInstrument(116, 'Taiko Drum'),
    GeneralMidiInstrument(117, 'Melodic Tom'),
    GeneralMidiInstrument(118, 'Synth Drum'),
    GeneralMidiInstrument(119, 'Reverse Cymbal'),
    GeneralMidiInstrument(120, 'Guitar Fret Noise'),
    GeneralMidiInstrument(121, 'Breath Noise'),
    GeneralMidiInstrument(122, 'Seashore'),
    GeneralMidiInstrument(123, 'Bird Tweet'),
    GeneralMidiInstrument(124, 'Telephone Ring'),
    GeneralMidiInstrument(125, 'Helicopter'),
    GeneralMidiInstrument(126, 'Applause'),
    GeneralMidiInstrument(127, 'Gunshot'),
  ];

  static GeneralMidiInstrument byProgram(int program) =>
      all.firstWhere((instrument) => instrument.program == program);
}

class MidiPlayerConfiguration {
  const MidiPlayerConfiguration({
    required this.instrumentProgram,
    required this.tempoBpm,
    required this.volumePercent,
  });

  final int instrumentProgram;
  final int tempoBpm;
  final int volumePercent;
}

class MidiConfiguration {
  static const _microsecondsPerMinute = 60000000;

  static MidiPlayerConfiguration defaultsFor(Uint8List bytes) {
    final midi = MidiParser().parseMidiFromBuffer(bytes);
    final programs = midi.tracks
        .expand((track) => track)
        .whereType<ProgramChangeMidiEvent>();
    final tempos = <(int tick, int microseconds)>[];
    for (final track in midi.tracks) {
      var tick = 0;
      for (final event in track) {
        tick += event.deltaTime;
        if (event is SetTempoEvent) {
          tempos.add((tick, event.microsecondsPerBeat));
        }
      }
    }
    tempos.sort((a, b) => a.$1.compareTo(b.$1));
    final microseconds =
        tempos.isNotEmpty && tempos.first.$1 == 0 ? tempos.first.$2 : 500000;
    final bpm =
        (_microsecondsPerMinute / microseconds).round().clamp(40, 240).toInt();
    return MidiPlayerConfiguration(
      instrumentProgram: programs.isEmpty ? 0 : programs.first.programNumber,
      tempoBpm: bpm,
      volumePercent: 100,
    );
  }

  static Uint8List apply(
    Uint8List bytes,
    MidiPlayerConfiguration configuration,
  ) {
    final midi = MidiParser().parseMidiFromBuffer(bytes);
    if (midi.tracks.isEmpty) {
      throw const FormatException('Le fichier MIDI ne contient aucune piste.');
    }

    var initialTempo = 500000;
    var hasTempoAtStart = false;
    final channelsByTrack = <int, Set<int>>{};
    final noteChannels = <int>{};
    final tempoEvents = <SetTempoEvent>[];

    for (var trackIndex = 0; trackIndex < midi.tracks.length; trackIndex++) {
      var tick = 0;
      for (final event in midi.tracks[trackIndex]) {
        tick += event.deltaTime;
        if (event is SetTempoEvent) {
          tempoEvents.add(event);
          if (tick == 0 && !hasTempoAtStart) {
            initialTempo = event.microsecondsPerBeat;
            hasTempoAtStart = true;
          }
        } else if (event is NoteOnEvent && event.velocity > 0) {
          channelsByTrack
              .putIfAbsent(trackIndex, () => <int>{})
              .add(event.channel);
          noteChannels.add(event.channel);
        }
      }
    }

    final targetTempo =
        (_microsecondsPerMinute / configuration.tempoBpm).round();
    for (final event in tempoEvents) {
      event.microsecondsPerBeat =
          (event.microsecondsPerBeat * targetTempo / initialTempo)
              .round()
              .clamp(1, 0xffffff)
              .toInt();
    }
    if (!hasTempoAtStart) {
      midi.tracks.first.insert(
        0,
        SetTempoEvent()
          ..type = 'setTempo'
          ..microsecondsPerBeat = targetTempo,
      );
    }

    final volumeScale = configuration.volumePercent / 100;
    for (var trackIndex = 0; trackIndex < midi.tracks.length; trackIndex++) {
      final track = midi.tracks[trackIndex];
      final channels = channelsByTrack[trackIndex] ?? const <int>{};
      for (final event in track) {
        if (event is ProgramChangeMidiEvent &&
            noteChannels.contains(event.channel) &&
            event.channel != 9) {
          event.programNumber = configuration.instrumentProgram;
        } else if (event is ControllerEvent &&
            event.controllerType == 7 &&
            noteChannels.contains(event.channel)) {
          event.value =
              (event.value * volumeScale).round().clamp(0, 127).toInt();
        }
      }

      for (final channel in channels) {
        if (channel != 9) {
          final program = ProgramChangeMidiEvent()
            ..type = 'programChange'
            ..channel = channel
            ..programNumber = configuration.instrumentProgram;
          track.insert(0, program);
        }
        final volume = ControllerEvent()
          ..type = 'controller'
          ..channel = channel
          ..controllerType = 7
          ..value = configuration.volumePercent;
        track.insert(0, volume);
      }
    }

    return Uint8List.fromList(MidiWriter().writeMidiToBuffer(midi));
  }
}
