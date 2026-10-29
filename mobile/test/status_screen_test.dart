import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melodiscan_mobile/screens/status_screen.dart';

void main() {
  testWidgets('StatusScreen displays SSE pipeline progress stages', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: StatusScreen(
            taskId: 'test_task_123',
            title: 'Test Symphony',
            serverUrl: 'http://localhost:8080',
          ),
        ),
      ),
    );

    expect(find.text('Traitement : Test Symphony'), findsOneWidget);
    expect(find.text('Prétraitement d\'image & Binarisation Sauvola'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Ouvrir le Player & Inspecteur'), findsOneWidget);
  });
}
