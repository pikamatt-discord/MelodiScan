import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melodiscan_mobile/screens/status_screen.dart';

void main() {
  testWidgets(
      'StatusScreen opens the player only after the server reports completion',
      (tester) async {
    final client = MockClient((_) async => http.Response(
          'data: {"task_id":"task-1","status":"STATUS_COMPLETED","progress":1.0}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StatusScreen(
            taskId: 'task-1',
            title: 'Test Symphony',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Traitement : Test Symphony'), findsOneWidget);
    expect(find.text('Votre partition est prête'), findsOneWidget);
    expect(
      find.text('Votre partition et votre fichier MIDI sont prêts.'),
      findsOneWidget,
    );
    expect(find.text('TERMINÉ'), findsOneWidget);
    expect(find.text('Ouvrir le lecteur MIDI'), findsOneWidget);
  });

  testWidgets(
      'StatusScreen displays concise processing errors without simulating completion',
      (tester) async {
    const errorSummary = 'Aucune portée détectée : Audiveris mesure seulement '
        '6 pixels entre les lignes. La photo peut être nette, mais sa définition '
        'reste trop faible pour cette analyse.';
    final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(
            'data: {"task_id":"task-2","status":"STATUS_FAILED","error":"$errorSummary"}\n\n',
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        ));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: StatusScreen(
            taskId: 'task-2',
            title: 'Failed Scan',
            serverUrl: 'http://localhost:8080',
            httpClient: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(errorSummary), findsOneWidget);
    expect(find.text('ÉCHEC'), findsOneWidget);
    expect(find.text('Voir le résultat MIDI'), findsNothing);
  });
}
