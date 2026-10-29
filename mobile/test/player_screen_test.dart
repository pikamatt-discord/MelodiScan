import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:melodiscan_mobile/screens/player_screen.dart';

void main() {
  testWidgets('PlayerScreen renders controls and responds to play button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PlayerScreen(
            taskId: 'test_task_456',
            title: 'Symphonie No. 5',
          ),
        ),
      ),
    );

    expect(find.text('Symphonie No. 5'), findsOneWidget);
    expect(find.text('Verovio Score Viewport (Canvas Vectoriel)'), findsOneWidget);
    expect(find.text('Tempo (Time-Stretching)'), findsOneWidget);

    // Tap play button
    await tester.tap(find.byKey(const Key('play_pause_fab')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.pause), findsOneWidget);
  });
}
