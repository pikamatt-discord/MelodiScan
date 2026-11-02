import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles a valid SoundFont asset', () async {
    final soundfont = await rootBundle.load('assets/soundfonts/instruments.sf2');

    expect(soundfont.lengthInBytes, greaterThan(1024 * 1024));
    expect(soundfont.getUint32(0), 0x52494646);
    expect(soundfont.getUint32(8), 0x7366626b);
  });
}
