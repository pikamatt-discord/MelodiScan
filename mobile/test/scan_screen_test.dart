import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/screens/scan_screen.dart';

void main() {
  testWidgets(
      'Scan screen requires one real image and displays server configuration',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ScanScreen()),
      ),
    );

    expect(find.text('MelodiScan · Profil 1'), findsOneWidget);
    expect(find.text('Prendre en photo'), findsOneWidget);
    expect(find.text('Choisir une image'), findsOneWidget);
    expect(find.text('Importer un PDF'), findsOneWidget);
    expect(find.text('Une image par traitement'), findsNothing);
    expect(find.text('Binarisation Sauvola'), findsNothing);
    expect(find.text('Galerie (Multi)'), findsNothing);
    expect(find.text('Choisissez une partition'), findsNothing);
    expect(find.text('Donnez vie à\nvotre partition'), findsOneWidget);

    expect(find.text('Aucun fichier sélectionné'), findsNothing);
    expect(find.text('Analyser la partition'), findsOneWidget);
    expect(find.text('Réglages avancés'), findsOneWidget);
    final analyzeButton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Analyser la partition'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    );
    expect(analyzeButton.onPressed, isNull);

    await tester.ensureVisible(find.text('Réglages avancés'));
    await tester.tap(find.text('Réglages avancés'));
    await tester.pumpAndSettle();
    expect(find.text('URL du serveur'), findsOneWidget);
    expect(find.text('Clé API (si configurée sur le serveur)'), findsOneWidget);
    expect(find.text('Titre (facultatif)'), findsNothing);
    expect(find.text('Serveur, clé API et titre du morceau'), findsNothing);
  });
}
