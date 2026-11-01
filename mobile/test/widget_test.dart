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
    var deletionRequests = 0;
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        deletionRequests += 1;
        expect(request.url.path, '/api/v1/library/saved-score');
        expect(request.url.queryParameters['profile_id'], 'profile-1');
        return http.Response('', 204);
      }
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
            {'id': 'profile-1', 'name': 'Profil familial principal partagé'},
            {'id': 'profile-2', 'name': 'Profil 2'},
            {'id': 'profile-3', 'name': 'Profil 3'},
          ],
        }),
        200,
      );
    });

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(child: MelodiScanApp(httpClient: client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sélection du profil'), findsOneWidget);
    expect(find.text('Profil familial principal partagé'), findsOneWidget);
    expect(find.byKey(const Key('profile_card_profile-1')), findsOneWidget);
    expect(find.byKey(const Key('profile_card_profile-2')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Profil familial principal partagé'));
    await tester.pumpAndSettle();
    expect(
      find.text('MelodiScan · Profil familial principal partagé'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('melodiscan_app_bar_logo')), findsOneWidget);
    expect(tester.takeException(), isNull);

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

    await tester.enterText(
      find.byKey(const Key('history_search_field')),
      '',
    );
    await tester.pumpAndSettle();
    final deleteButton = find.byKey(const Key('delete_score_saved-score'));
    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette partition ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(deletionRequests, 0);
    expect(find.text('Sonate en do'), findsOneWidget);

    await tester.ensureVisible(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete_score')));
    await tester.pumpAndSettle();
    expect(deletionRequests, 1);
    expect(find.text('Sonate en do'), findsNothing);
    expect(find.text('Étude rapide'), findsOneWidget);
  });
}
