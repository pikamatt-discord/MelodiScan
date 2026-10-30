import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:melodiscan_mobile/services/general_midi_soundfont.dart';

void main() {
  test('downloads the verified soundfont once and reuses the cached file',
      () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('melodiscan-soundfont-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final bytes = [1, 2, 3, 4, 5];
    final digest = sha256.convert(bytes).toString();
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      return http.Response.bytes(bytes, 200);
    });
    addTearDown(client.close);
    final soundfont = GeneralMidiSoundfont(
      client: client,
      supportDirectoryProvider: () async => temporaryDirectory,
      downloadUri: Uri.https('example.test', '/GeneralUser-GS.sf2'),
      expectedLength: bytes.length,
      expectedSha256: digest,
    );

    final firstFile = await soundfont.getFile();
    final secondFile = await soundfont.getFile();

    expect(await firstFile.readAsBytes(), bytes);
    expect(secondFile.path, firstFile.path);
    expect(requestCount, 1);
  });

  test('rejects a soundfont with an invalid checksum', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('melodiscan-soundfont-test-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final client = MockClient((_) async => http.Response.bytes([1, 2, 3], 200));
    addTearDown(client.close);
    final soundfont = GeneralMidiSoundfont(
      client: client,
      supportDirectoryProvider: () async => temporaryDirectory,
      downloadUri: Uri.https('example.test', '/GeneralUser-GS.sf2'),
      expectedLength: 3,
      expectedSha256: 'invalid',
    );

    await expectLater(soundfont.getFile(), throwsFormatException);

    final cacheDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}soundfonts',
    );
    expect(await cacheDirectory.list().toList(), isEmpty);
  });
}
