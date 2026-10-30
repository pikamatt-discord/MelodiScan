import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melodiscan_mobile/models/midi_visualization.dart';
import 'package:melodiscan_mobile/screens/player_screen.dart';
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
      currentTick: 0,
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

  testWidgets('PlayerScreen plays, pauses, and stops a verified MIDI result',
      (tester) async {
    final client = MockClient((_) async => http.Response.bytes(
          validMidiBytes,
          200,
          headers: {'content-type': 'audio/midi'},
        ));
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

    expect(find.text('Symphonie No. 5'), findsOneWidget);
    expect(find.text('Aperçu de la partition non disponible'), findsOneWidget);
    expect(find.text('34 octets'), findsOneWidget);
    expect(find.text('Lire'), findsOneWidget);
    expect(find.byKey(const Key('stop_playback')), findsOneWidget);

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
    final client = MockClient((_) async => http.Response.bytes(
          validMidiBytes,
          200,
          headers: {'content-type': 'audio/midi'},
        ));
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
}
