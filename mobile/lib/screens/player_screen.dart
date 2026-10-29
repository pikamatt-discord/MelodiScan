import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../network/api_client.dart';

class PlayerScreen extends StatefulWidget {
  final String taskId;
  final String title;
  final String serverUrl;
  final String apiKey;
  final http.Client? httpClient;

  const PlayerScreen({
    super.key,
    required this.taskId,
    required this.title,
    required this.serverUrl,
    this.apiKey = '',
    this.httpClient,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isLoading = true;
  int? _midiBytesLength;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMidiResult();
  }

  Future<void> _fetchMidiResult() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _midiBytesLength = null;
    });

    try {
      final client = widget.httpClient ?? createApiClient();
      final uri =
          Uri.parse('${widget.serverUrl}/api/v1/result/${widget.taskId}');
      final response = await client
          .get(
            uri,
            headers:
                widget.apiKey.isEmpty ? null : {'X-API-Key': widget.apiKey},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError(_responseError(response));
      }

      final bytes = response.bodyBytes;
      if (!_isMidiFile(bytes)) {
        throw const FormatException(
            'Le serveur n’a pas renvoyé un fichier MIDI valide.');
      }

      if (mounted) {
        setState(() {
          _midiBytesLength = bytes.length;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString().replaceFirst('Bad state: ', '');
          _isLoading = false;
        });
      }
    }
  }

  bool _isMidiFile(List<int> bytes) {
    if (bytes.length < 22 || String.fromCharCodes(bytes.take(4)) != 'MThd') {
      return false;
    }
    final headerLength =
        (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
    if (headerLength < 6 || bytes.length < 22) {
      return false;
    }
    return String.fromCharCodes(bytes.skip(8 + headerLength).take(4)) == 'MTrk';
  }

  String _responseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } on FormatException {
      if (response.body.isNotEmpty) return response.body;
    }
    return 'Le serveur a refusé le résultat (${response.statusCode}).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? const CircularProgressIndicator()
              : _errorMessage != null
                  ? _buildError(theme)
                  : _buildMidiResult(theme),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
        const SizedBox(height: 16),
        const Text('Impossible de charger le résultat MIDI',
            style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Text(_errorMessage!, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _fetchMidiResult,
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
          style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary),
        ),
      ],
    );
  }

  Widget _buildMidiResult(ThemeData theme) {
    final resultUrl = '${widget.serverUrl}/api/v1/result/${widget.taskId}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.music_note_rounded,
            color: theme.colorScheme.secondary, size: 64),
        const SizedBox(height: 16),
        const Text(
          'Fichier MIDI reçu et vérifié',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Taille : $_midiBytesLength octets'),
        const SizedBox(height: 20),
        const Text(
          'La lecture audio intégrée n’est pas disponible dans cette version.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text('URL du fichier MIDI :'),
        const SizedBox(height: 4),
        SelectableText(resultUrl, textAlign: TextAlign.center),
      ],
    );
  }
}
