import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melodiscan_mobile/main.dart';

void main() {
  testWidgets('App starts with dark theme', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MelodiScanApp()));
    expect(find.text('MelodiScan Scanner'), findsOneWidget);
  });
}
