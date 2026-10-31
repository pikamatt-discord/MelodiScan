import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dart_midi_pro/dart_midi_pro.dart';
import 'package:melodiscan_mobile/models/midi_visualization.dart';
import 'package:melodiscan_mobile/screens/player_screen.dart';
import 'package:melodiscan_mobile/services/midi_configuration.dart';
import 'package:melodiscan_mobile/services/midi_playback.dart';

class FakeMidiPlayback implements MidiPlayback {
  FakeMidiPlayback({this.isSupported = true});

  @override
  final bool isSupported;

  Uint8List? preparedBytes;
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool playing = false;
  int currentTick = 0;

  @override
  Future<void> prepare(Uint8List midiBytes) async {
    preparedBytes = midiBytes;
  }

  @override
  Future<void> play() async {
    playCount++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    playing = false;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    playing = false;
  }

  @override
  Future<MidiPlaybackPosition> getPosition() async {
    return MidiPlaybackPosition(
      currentTick: currentTick,
      totalTicks: 96,
      isPlaying: playing,
      isComplete: false,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

final validMidiBytes = Uint8List.fromList([
  0x4D,
  0x54,
  0x68,
  0x64,
  0,
  0,
  0,
  6,
  0,
  0,
  0,
  1,
  0,
  96,
  0x4D,
  0x54,
  0x72,
  0x6B,
  0,
  0,
  0,
  12,
  0,
  0x90,
  60,
  80,
  96,
  0x80,
  60,
  0,
  0,
  0xFF,
  0x2F,
  0,
]);

const validMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>24</divisions>
        <key><fifths>-1</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note>
        <pitch><step>B</step><alter>-1</alter><octave>4</octave></pitch>
        <duration>24</duration><type>quarter</type>
      </note>
    </measure>
  </part>
</score-partwise>
''';

http.Response _playerResponse(http.Request request) {
  if (request.url.path.endsWith('/musicxml')) {
    return http.Response(
      validMusicXml,
      200,
      headers: {'content-type': 'application/vnd.recordare.musicxml+xml'},
    );
  }
  return http.Response.bytes(
    validMidiBytes,
    200,
    headers: {'content-type': 'audio/midi'},
  );
}

void main() {
  test('MIDI visualization extracts note pitch and duration', () {
    final visualization = MidiVisualization.parse(validMidiBytes);

    expect(visualization.ticksPerBeat, 96);
    expect(visualization.totalTicks, 96);
    expect(visualization.notes, hasLength(1));
    expect(visualization.notes.single.pitch, 60);
    expect(visualization.notes.single.startTick, 0);
    expect(visualization.notes.single.endTick, 96);
  });

  test('Default playback settings preserve the original MIDI bytes', () {
    final defaults = MidiConfiguration.defaultsFor(validMidiBytes);

    expect(
      MidiConfiguration.apply(validMidiBytes, defaults),
      same(validMidiBytes),
    );
  });

  test('Playback settings rewrite instrument, tempo, and volume', () {
    final configured = MidiConfiguration.apply(
      validMidiBytes,
      const MidiPlayerConfiguration(
        instrumentProgram: 73,
        tempoBpm: 90,
        volumePercent: 50,
      ),
    );
    final midi = MidiParser().parseMidiFromBuffer(configured);
    final events = midi.tracks.expand((track) => track).toList();

    expect(
      events.whereType<ProgramChangeMidiEvent>().single.programNumber,
      73,
    );
    expect(
      events.whereType<SetTempoEvent>().single.microsecondsPerBeat,
      666667,
    );
    expect(
      events
          .whereType<ControllerEvent>()
          .singleWhere((event) => event.controllerType == 7)
          .value,
      50,
    );
    final note = MidiVisualization.parse(configured).notes.single;
    expect(note.startTick, 0);
    expect(note.endTick, 96);
  });

  test('A delayed tempo change keeps the selected tempo from tick zero', () {
    final midiBytes = Uint8List.fromList(
      MidiWriter().writeMidiToBuffer(
        MidiFile(
          [
            [
              NoteOnEvent()
                ..channel = 0
                ..noteNumber = 60
                ..velocity = 80,
              SetTempoEvent()
                ..deltaTime = 48
                ..microsecondsPerBeat = 400000,
              NoteOffEvent()
                ..deltaTime = 48
                ..channel = 0
                ..noteNumber = 60,
              EndOfTrackEvent(),
            ],
          ],
          MidiHeader(format: 0, numTracks: 1, ticksPerBeat: 96),
        ),
      ),
    );
    final defaults = MidiConfiguration.defaultsFor(midiBytes);
    final configured = MidiParser().parseMidiFromBuffer(
      MidiConfiguration.apply(
        midiBytes,
        const MidiPlayerConfiguration(
          instrumentProgram: 0,
          tempoBpm: 90,
          volumePercent: 100,
        ),
      ),
    );
    final tempos = configured.tracks
        .expand((track) => track)
        .whereType<SetTempoEvent>()
        .toList();

    expect(defaults.tempoBpm, 120);
    expect(tempos, hasLength(2));
    expect(tempos.first.microsecondsPerBeat, 666667);
    expect(tempos.last.microsecondsPerBeat, 533334);
  });

  testWidgets('PlayerScreen plays, pauses, and stops a verified MIDI result',
      (tester) async {
    final client = MockClient((request) async => _playerResponse(request));
    final playback = FakeMidiPlayback();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerScreen(
            taskId: 'test_task_456',
            title: 'Symphonie No. 5',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
            midiPlayback: playback,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Symphonie No. 5'), findsNWidgets(2));
    expect(find.textContaining('Acoustic Grand Piano'), findsOneWidget);
    expect(find.text('Partition'), findsOneWidget);
    expect(find.byKey(const Key('traditional_score_view')), findsOneWidget);
    expect(find.text('Lire'), findsOneWidget);
    expect(find.byKey(const Key('stop_playback')), findsOneWidget);

    await tester.tap(find.text('Piano roll'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piano_roll_view')), findsOneWidget);
    await tester.tap(find.text('Partition'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('traditional_score_view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('play_pause_fab')));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(playback.preparedBytes, equals(validMidiBytes));
    expect(playback.playCount, 1);

    await tester.tap(find.byKey(const Key('play_pause_fab')));
    await tester.pumpAndSettle();
    expect(find.text('Lire'), findsOneWidget);
    expect(playback.pauseCount, 1);

    await tester.tap(find.byKey(const Key('stop_playback')));
    await tester.pumpAndSettle();
    expect(playback.stopCount, 1);
  });

  testWidgets('Player configuration exposes instrument, tempo, and volume',
      (tester) async {
    final client = MockClient((request) async => _playerResponse(request));
    final playback = FakeMidiPlayback();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          taskId: 'settings_task',
          title: 'Partition',
          serverUrl: 'http://localhost:8080',
          httpClient: client,
          midiPlayback: playback,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_configuration_button')));
    await tester.pumpAndSettle();

    expect(find.text('Configuration du lecteur'), findsOneWidget);
    expect(find.byKey(const Key('instrument_selector')), findsOneWidget);
    expect(find.byKey(const Key('tempo_slider')), findsOneWidget);
    expect(find.byKey(const Key('volume_slider')), findsOneWidget);
    expect(GeneralMidiInstrument.all, hasLength(128));

    await tester.tap(find.byKey(const Key('instrument_selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. Bright Acoustic Piano').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_player_configuration')));
    await tester.pumpAndSettle();
    expect(find.text('Configuration du lecteur'), findsNothing);
    expect(find.textContaining('120 BPM'), findsOneWidget);
    expect(find.textContaining('Bright Acoustic Piano'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play_pause_fab')));
    await tester.pumpAndSettle();
    final preparedMidi =
        MidiParser().parseMidiFromBuffer(playback.preparedBytes!);
    expect(
      preparedMidi.tracks
          .expand((track) => track)
          .whereType<ProgramChangeMidiEvent>()
          .single
          .programNumber,
      1,
    );
  });

  testWidgets(
      'PlayerScreen shows HTTP errors instead of fabricating a MIDI result',
      (tester) async {
    final client = MockClient((_) async => http.Response(
          '{"detail":"Audiveris failed"}',
          422,
          headers: {'content-type': 'application/json'},
        ));
    final playback = FakeMidiPlayback();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerScreen(
            taskId: 'failed_task',
            title: 'Failed scan',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
            midiPlayback: playback,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger le résultat MIDI'), findsOneWidget);
    expect(find.text('Audiveris failed'), findsOneWidget);
    expect(find.text('Lire'), findsNothing);
  });

  testWidgets('PlayerScreen explains when playback is not supported',
      (tester) async {
    final client = MockClient((request) async => _playerResponse(request));
    final playback = FakeMidiPlayback(isSupported: false);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          taskId: 'test_task_789',
          title: 'Partition',
          serverUrl: 'http://localhost:8080',
          httpClient: client,
          midiPlayback: playback,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('disponible sur Android 7'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('play_pause_fab')), findsNothing);
  });

  testWidgets('Piano roll follows playback position updates', (tester) async {
    final client = MockClient((request) async => _playerResponse(request));
    final playback = FakeMidiPlayback();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          taskId: 'piano_roll_task',
          title: 'Piano roll test',
          serverUrl: 'http://localhost:8080',
          httpClient: client,
          midiPlayback: playback,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piano roll'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play_pause_fab')));
    await tester.pumpAndSettle();

    playback.currentTick = 48;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('piano_roll_view')), findsOneWidget);
    expect(find.text('50 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
