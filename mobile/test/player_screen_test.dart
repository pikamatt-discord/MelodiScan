import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melodiscan_mobile/screens/player_screen.dart';

void main() {
  testWidgets(
      'PlayerScreen displays a verified MIDI result without fake playback',
      (tester) async {
    final client = MockClient((_) async => http.Response.bytes(
          [
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
            4,
            0,
            0xFF,
            0x2F,
            0,
          ],
          200,
          headers: {'content-type': 'audio/midi'},
        ));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerScreen(
            taskId: 'test_task_456',
            title: 'Symphonie No. 5',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Symphonie No. 5'), findsOneWidget);
    expect(find.text('Fichier MIDI reçu et vérifié'), findsOneWidget);
    expect(find.text('Taille : 26 octets'), findsOneWidget);
    expect(find.textContaining('lecture audio intégrée n’est pas disponible'),
        findsOneWidget);
    expect(find.byKey(const Key('play_pause_fab')), findsNothing);
  });

  testWidgets(
      'PlayerScreen shows HTTP errors instead of fabricating a MIDI result',
      (tester) async {
    final client = MockClient((_) async => http.Response(
          '{"detail":"Audiveris failed"}',
          422,
          headers: {'content-type': 'application/json'},
        ));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerScreen(
            taskId: 'failed_task',
            title: 'Failed scan',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger le résultat MIDI'), findsOneWidget);
    expect(find.text('Audiveris failed'), findsOneWidget);
    expect(find.text('Fichier MIDI reçu et vérifié'), findsNothing);
  });
}
