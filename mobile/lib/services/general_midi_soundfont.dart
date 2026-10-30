import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GeneralMidiSoundfont {
  GeneralMidiSoundfont({
    http.Client? client,
    Future<Directory> Function()? supportDirectoryProvider,
    Uri? downloadUri,
    int expectedLength = _defaultExpectedLength,
    String expectedSha256 = _defaultExpectedSha256,
  })  : _client = client,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _downloadUri = downloadUri ?? _defaultDownloadUri,
        _expectedLength = expectedLength,
        _expectedSha256 = expectedSha256;

  static final _defaultDownloadUri = Uri.parse(
    'https://github.com/got-feedBack/feedBack-soundfonts/releases/download/'
    'soundfonts-v1/GeneralUser-GS.sf2',
  );
  static const _defaultExpectedLength = 32319396;
  static const _defaultExpectedSha256 =
      '9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe';

  final http.Client? _client;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Uri _downloadUri;
  final int _expectedLength;
  final String _expectedSha256;

  Future<File> getFile() async {
    final directory = Directory(
      '${(await _supportDirectoryProvider()).path}${Platform.pathSeparator}soundfonts',
    );
    await directory.create(recursive: true);

    final soundfont = File(
      '${directory.path}${Platform.pathSeparator}GeneralUser-GS.sf2',
    );
    if (await _matchesExpectedFile(soundfont)) return soundfont;
    if (await soundfont.exists()) await soundfont.delete();

    final partialFile = File('${soundfont.path}.download');
    if (await partialFile.exists()) await partialFile.delete();

    final client = _client ?? http.Client();
    try {
      final response = await client
          .send(http.Request('GET', _downloadUri))
          .timeout(const Duration(minutes: 2));
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain<void>();
        throw HttpException(
          'Téléchargement de la banque MIDI refusé (HTTP ${response.statusCode}).',
          uri: _downloadUri,
        );
      }

      final contentLength = response.contentLength;
      if (contentLength != null &&
          contentLength > 0 &&
          contentLength != _expectedLength) {
        await response.stream.drain<void>();
        throw const FormatException(
          'La taille de la banque MIDI téléchargée est incorrecte.',
        );
      }

      final hashOutput = _DigestSink();
      final hashInput = sha256.startChunkedConversion(hashOutput);
      var receivedLength = 0;
      try {
        final outputFile = await partialFile.open(mode: FileMode.write);
        try {
          await for (final chunk in response.stream) {
            receivedLength += chunk.length;
            if (receivedLength > _expectedLength) {
              throw const FormatException(
                'La banque MIDI téléchargée dépasse la taille attendue.',
              );
            }
            hashInput.add(chunk);
            await outputFile.writeFrom(chunk);
          }
          hashInput.close();
          await outputFile.flush();
        } finally {
          await outputFile.close();
        }
      } catch (_) {
        if (await partialFile.exists()) await partialFile.delete();
        rethrow;
      }

      if (receivedLength != _expectedLength ||
          hashOutput.digest?.toString() != _expectedSha256) {
        await partialFile.delete();
        throw const FormatException(
          'La vérification de la banque MIDI téléchargée a échoué.',
        );
      }

      return partialFile.rename(soundfont.path);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<bool> _matchesExpectedFile(File file) async {
    if (!await file.exists() || await file.length() != _expectedLength) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == _expectedSha256;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
