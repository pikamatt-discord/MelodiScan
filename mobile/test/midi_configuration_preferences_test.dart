import 'package:flutter_test/flutter_test.dart';
import 'package:melodiscan_mobile/services/midi_configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists and restores player settings across sessions', () async {
    SharedPreferences.setMockInitialValues({});
    const fallback = MidiPlayerConfiguration(
      instrumentProgram: 0,
      tempoBpm: 120,
      volumePercent: 100,
    );
    const saved = MidiPlayerConfiguration(
      instrumentProgram: 73,
      tempoBpm: 88,
      volumePercent: 72,
      followScoreInstrument: false,
      followScoreTempo: false,
    );

    final initial = await MidiConfiguration.loadPreferences(fallback);
    expect(initial.instrumentProgram, fallback.instrumentProgram);
    expect(initial.tempoBpm, fallback.tempoBpm);
    expect(initial.volumePercent, fallback.volumePercent);
    expect(initial.followScoreInstrument, isTrue);
    expect(initial.followScoreTempo, isTrue);
    await MidiConfiguration.savePreferences(saved);

    final restored = await MidiConfiguration.loadPreferences(fallback);
    expect(restored.instrumentProgram, saved.instrumentProgram);
    expect(restored.tempoBpm, saved.tempoBpm);
    expect(restored.volumePercent, saved.volumePercent);
    expect(restored.followScoreInstrument, isFalse);
    expect(restored.followScoreTempo, isFalse);
  });
}
