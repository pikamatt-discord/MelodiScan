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

    expect(find.text('MelodiScan Scanner'), findsOneWidget);
    expect(find.text('Prendre en photo'), findsOneWidget);
    expect(find.text('Choisir une image'), findsOneWidget);
    expect(find.text('Importer un PDF'), findsOneWidget);
    expect(find.text('Une image par traitement'), findsNothing);
    expect(find.text('Binarisation Sauvola'), findsNothing);
    expect(find.text('Galerie (Multi)'), findsNothing);

    expect(find.text('Aucun fichier sélectionné'), findsOneWidget);
    expect(find.text('Lancer la reconnaissance OMR'), findsOneWidget);
    final buttons = tester.widgetList<ElevatedButton>(
      find.byWidgetPredicate((widget) => widget is ElevatedButton),
    );
    expect(buttons.any((button) => button.onPressed == null), isTrue);
  });
}
