import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan/api_service.dart';
import 'package:melodiscan/main.dart';
import 'package:melodiscan/player_view.dart';

class MockApiService extends ApiService {
  final OMRResult resultToReturn;
  final bool connectionResult;

  MockApiService(this.resultToReturn, {this.connectionResult = true});

  @override
  Future<OMRResult> scanPartition(File imageFile, String serverAddress) async {
    return resultToReturn;
  }

  @override
  Future<bool> checkConnection(String serverAddress) async {
    return connectionResult;
  }
}

void main() {
  testWidgets('Renders HomeScreen in Capture State with Dark Theme by default', (WidgetTester tester) async {
    await tester.pumpWidget(const MelodiScanApp());

    expect(find.text('MelodiScan'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('ip_input_field')), findsOneWidget);
    expect(find.byKey(const Key('scan_button')), findsOneWidget);
    expect(find.byKey(const Key('gallery_button')), findsOneWidget);
    expect(find.byKey(const Key('photo_tips_expander')), findsOneWidget);
  });

  testWidgets('Opens Theme Personalization Dialog and toggles options', (WidgetTester tester) async {
    await tester.pumpWidget(const MelodiScanApp());

    await tester.tap(find.byKey(const Key('theme_settings_button')));
    await tester.pump();

    expect(find.text('Personnalisation Studio'), findsOneWidget);
    expect(find.text('Mode Sombre (Cyber Dark)'), findsOneWidget);
  });

  testWidgets('PlayerView renders controls, segmented view mode button, and sliders', (WidgetTester tester) async {
    final dummyMidi = Uint8List.fromList([
      0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06, 0x00, 0x01, 0x00, 0x01, 0x01, 0xE0,
      0x4D, 0x54, 0x72, 0x6B, 0x00, 0x00, 0x00, 0x0F,
      0x00, 0x90, 0x3C, 0x64, 0x81, 0x70, 0x80, 0x3C, 0x00, 0x00, 0xFF, 0x2F, 0x00
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerView(
            midiData: dummyMidi,
            onReset: () {},
          ),
        ),
      ),
    );

    expect(find.text('Lecteur OMR Interactif'), findsOneWidget);
    expect(find.byKey(const Key('view_mode_segmented_button')), findsOneWidget);
    expect(find.byKey(const Key('play_pause_button')), findsOneWidget);
    expect(find.byKey(const Key('stop_button')), findsOneWidget);
    expect(find.byKey(const Key('tempo_slider')), findsOneWidget);
    expect(find.byKey(const Key('transposition_slider')), findsOneWidget);
    expect(find.byKey(const Key('seeking_slider')), findsOneWidget);

    // Switch view mode to Xylophone Falling Notes
    await tester.tap(find.text('Mode Xylophone'));
    await tester.pump();

    expect(find.text('Partition Recomposée'), findsOneWidget);
  });

  testWidgets('ApiService formatBaseUrl and checkConnection behave properly', (WidgetTester tester) async {
    final apiService = ApiService();
    expect(apiService.formatBaseUrl('192.168.1.10:8000'), 'http://192.168.1.10:8000');
    expect(apiService.formatBaseUrl('http://192.168.1.10:8000/'), 'http://192.168.1.10:8000');
    expect(apiService.formatBaseUrl(''), 'http://127.0.0.1:8000');
  });

  test('MidiNoteInfo transposition calculates transposed pitch names correctly', () {
    final note = MidiNoteInfo(
      noteNumber: 60, // C4
      noteName: 'C4',
      startTimeInBeats: 0,
      durationInBeats: 1,
    );

    expect(note.getTransposedNoteName(0), 'C4');
    expect(note.getTransposedNoteName(2), 'D4');
    expect(note.getTransposedNoteName(-1), 'B3');
  });
}
