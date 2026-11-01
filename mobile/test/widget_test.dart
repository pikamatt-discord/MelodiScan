import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melodiscan_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App starts by asking which profile is using it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/library') {
        expect(request.url.queryParameters['profile_id'], 'profile-1');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'task_id': 'saved-score',
                'title': 'Sonate en do',
                'created_at': '2025-01-01T10:00:00+00:00',
                'score_metadata': {'measure_count': 12},
              },
              {
                'task_id': 'saved-score-2',
                'title': 'Étude rapide',
                'created_at': '2025-02-01T10:00:00+00:00',
                'score_metadata': {'measure_count': 8},
              },
            ],
          }),
          200,
        );
      }
      expect(request.url.path, '/api/v1/profiles');
      return http.Response(
        jsonEncode({
          'profiles': [
            {'id': 'profile-1', 'name': 'Profil 1'},
            {'id': 'profile-2', 'name': 'Profil 2'},
            {'id': 'profile-3', 'name': 'Profil 3'},
          ],
        }),
        200,
      );
    });

    await tester.pumpWidget(
      ProviderScope(child: MelodiScanApp(httpClient: client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Qui utilise MelodiScan ?'), findsOneWidget);
    expect(find.text('Profil 1'), findsOneWidget);

    await tester.tap(find.text('Profil 1'));
    await tester.pumpAndSettle();
    expect(find.text('MelodiScan · Profil 1'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(find.text('Sonate en do'), findsOneWidget);
    expect(find.text('Étude rapide'), findsOneWidget);
    expect(find.textContaining('12 mesures'), findsOneWidget);

    await tester.tap(find.text('Titre A–Z'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Étude rapide')).dy,
      lessThan(tester.getTopLeft(find.text('Sonate en do')).dy),
    );

    await tester.enterText(
      find.byKey(const Key('history_search_field')),
      'etude',
    );
    await tester.pumpAndSettle();
    expect(find.text('Étude rapide'), findsOneWidget);
    expect(find.text('Sonate en do'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('history_search_field')),
      'introuvable',
    );
    await tester.pumpAndSettle();
    expect(find.text('Aucune partition trouvée'), findsOneWidget);
  });
}
