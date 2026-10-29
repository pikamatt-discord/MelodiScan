import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melodiscan_mobile/screens/scan_screen.dart';

void main() {
  testWidgets('Scan screen renders camera, gallery buttons and toggles edge binarization', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ScanScreen(),
        ),
      ),
    );

    expect(find.text('MelodiScan Scanner'), findsOneWidget);
    expect(find.text('Prendre en Photo'), findsOneWidget);
    expect(find.text('Galerie (Multi)'), findsOneWidget);

    final binarizeButton = find.text('Binarisation Sauvola');
    expect(binarizeButton, findsOneWidget);

    await tester.ensureVisible(binarizeButton);
    await tester.tap(binarizeButton);
    await tester.pumpAndSettle();

    expect(find.text('Réinitialiser'), findsOneWidget);
  });
}
