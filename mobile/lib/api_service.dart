import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class OMRResult {
  final Uint8List? midiData;
  final String? errorMessage;
  final bool isSuccess;

  OMRResult.success(this.midiData)
      : errorMessage = null,
        isSuccess = true;

  OMRResult.failure(this.errorMessage)
      : midiData = null,
        isSuccess = false;
}

class ApiService {
  final http.Client client;

  ApiService({http.Client? client}) : client = client ?? http.Client();

  /// Formats server base address URL (handles with or without http:// and trailing slashes)
  String formatBaseUrl(String serverAddress) {
    String address = serverAddress.trim();
    if (address.isEmpty) {
      address = "127.0.0.1:8000";
    }
    if (!address.startsWith('http://') && !address.startsWith('https://')) {
      address = 'http://$address';
    }
    if (address.endsWith('/')) {
      address = address.substring(0, address.length - 1);
    }
    return address;
  }

  /// Pings the backend server root endpoint to check connection
  Future<bool> checkConnection(String serverAddress) async {
    try {
      final baseUrl = formatBaseUrl(serverAddress);
      final uri = Uri.parse(baseUrl);
      final response = await client.get(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends image file to /scan endpoint with explicit image content type header and 60s timeout
  Future<OMRResult> scanPartition(File imageFile, String serverAddress) async {
    try {
      final baseUrl = formatBaseUrl(serverAddress);
      final uri = Uri.parse('$baseUrl/scan');

      final request = http.MultipartRequest('POST', uri);
      final fileStream = http.ByteStream(imageFile.openRead());
      final length = await imageFile.length();

      final fileName = imageFile.path.split('/').last;
      MediaType mediaType = MediaType('image', 'jpeg');
      if (fileName.toLowerCase().endsWith('.png')) {
        mediaType = MediaType('image', 'png');
      } else if (fileName.toLowerCase().endsWith('.webp')) {
        mediaType = MediaType('image', 'webp');
      }

      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        length,
        filename: fileName,
        contentType: mediaType,
      );

      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Network request timed out');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return OMRResult.success(response.bodyBytes);
      } else {
        return OMRResult.failure(
          "Impossible de lire la partition. Veuillez reprendre la photo avec une meilleure luminosité.",
        );
      }
    } on TimeoutException {
      return OMRResult.failure(
        "Délai d'attente dépassé. Le serveur n'a pas répondu à temps.",
      );
    } on SocketException {
      return OMRResult.failure(
        "Impossible de contacter le serveur. Vérifiez l'adresse IP et votre connexion réseau.",
      );
    } catch (e) {
      return OMRResult.failure(
        "Impossible de lire la partition. Veuillez reprendre la photo avec une meilleure luminosité.",
      );
    }
  }
}
