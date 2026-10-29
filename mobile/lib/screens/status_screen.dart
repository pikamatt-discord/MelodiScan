import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'player_screen.dart';

class StatusScreen extends StatefulWidget {
  final String taskId;
  final String title;
  final String serverUrl;
  final String apiKey;
  final http.Client? httpClient;

  const StatusScreen({
    super.key,
    required this.taskId,
    required this.title,
    required this.serverUrl,
    this.apiKey = '',
    this.httpClient,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final List<String> _stages = [
    'STATUS_QUEUED',
    'STATUS_PROCESSING_IMAGE',
    'STATUS_RUNNING_OMR',
    'STATUS_BUILDING_MUSICXML',
    'STATUS_EXPORTING_MIDI',
    'STATUS_COMPLETED',
  ];

  int _currentStageIndex = 0;
  bool _isCompleted = false;
  String? _errorMessage;
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _startSSEStream();
  }

  Future<void> _startSSEStream() async {
    final client = widget.httpClient ?? http.Client();
    try {
      final uri =
          Uri.parse('${widget.serverUrl}/api/v1/stream/${widget.taskId}');
      final request = http.Request('GET', uri);
      if (widget.apiKey.isNotEmpty) {
        request.headers['X-API-Key'] = widget.apiKey;
      }
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        _setError(_responseError(response.statusCode, body));
        return;
      }

      _streamSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleSseLine,
            onError: (Object error) =>
                _setError('Connexion au suivi interrompue : $error'),
            onDone: () {
              if (mounted && !_isCompleted && _errorMessage == null) {
                _setError(
                    'Le serveur a fermé le suivi avant la fin du traitement.');
              }
            },
          );
    } catch (error) {
      _setError('Impossible de suivre le traitement : $error');
    }
  }

  void _handleSseLine(String line) {
    if (!line.startsWith('data: ')) return;
    try {
      final data = jsonDecode(line.substring(6));
      if (data is! Map<String, dynamic>) {
        _setError('Le serveur a envoyé un événement de suivi invalide.');
        return;
      }

      final status = data['status'];
      if (status == 'STATUS_FAILED') {
        _setError(data['error'] as String? ??
            'Le traitement de la partition a échoué.');
      } else if (status is String && _stages.contains(status) && mounted) {
        setState(() {
          _currentStageIndex = _stages.indexOf(status);
          _isCompleted = status == 'STATUS_COMPLETED';
        });
      }
    } on FormatException catch (error) {
      _setError('Événement de suivi invalide : $error');
    }
  }

  String _responseError(int statusCode, String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    } on FormatException {
      if (body.isNotEmpty) return body;
    }
    return 'Le serveur a refusé le suivi ($statusCode).';
  }

  void _setError(String message) {
    if (!mounted || _errorMessage != null) return;
    setState(() {
      _errorMessage = message;
      _isCompleted = false;
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  void _navigateToPlayer() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          taskId: widget.taskId,
          title: widget.title,
          serverUrl: widget.serverUrl,
          apiKey: widget.apiKey,
          httpClient: widget.httpClient,
        ),
      ),
    );
  }

  String _getStageLabel(String stage) {
    switch (stage) {
      case 'STATUS_QUEUED':
        return 'Demande acceptée, en attente du worker';
      case 'STATUS_PROCESSING_IMAGE':
        return 'Validation de l’image';
      case 'STATUS_RUNNING_OMR':
        return 'Reconnaissance OMR avec Audiveris';
      case 'STATUS_BUILDING_MUSICXML':
        return 'Préparation du résultat MusicXML';
      case 'STATUS_EXPORTING_MIDI':
        return 'Conversion MusicXML vers MIDI';
      case 'STATUS_COMPLETED':
        return 'Conversion terminée';
      default:
        return stage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _currentStageIndex / (_stages.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text('Traitement : ${widget.title}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Task Progress Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.terminal_rounded,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'ID : ${widget.taskId.substring(0, widget.taskId.length > 12 ? 12 : widget.taskId.length)}...',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                  fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _errorMessage != null
                                ? Colors.red.withAlpha(40)
                                : _isCompleted
                                    ? Colors.green.withAlpha(40)
                                    : theme.colorScheme.primary.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _errorMessage != null
                                ? 'ÉCHEC'
                                : _isCompleted
                                    ? 'TERMINÉ'
                                    : 'EN COURS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _errorMessage != null
                                  ? Colors.red
                                  : _isCompleted
                                      ? Colors.green
                                      : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isCompleted
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage == null
                          ? '${(progress * 100).toInt()}% Complété'
                          : 'Traitement interrompu',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Flux SSE du Serveur Domestique :',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_errorMessage != null)
              Card(
                color: Colors.red.withAlpha(30),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),

            // Animated Timeline ListView
            Expanded(
              child: ListView.builder(
                itemCount: _stages.length,
                itemBuilder: (context, index) {
                  final stage = _stages[index];
                  final isDone =
                      _errorMessage == null && index < _currentStageIndex;
                  final isCurrent =
                      _errorMessage == null && index == _currentStageIndex;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? theme.colorScheme.primary.withAlpha(30)
                          : isDone
                              ? Colors.green.withAlpha(20)
                              : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : isDone
                                ? Colors.green.withAlpha(150)
                                : Colors.white.withAlpha(10),
                        width: isCurrent ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.withAlpha(40)
                                : isCurrent
                                    ? theme.colorScheme.primary.withAlpha(40)
                                    : Colors.white10,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDone
                                ? Icons.check_circle_rounded
                                : isCurrent
                                    ? Icons.sync_rounded
                                    : Icons.radio_button_unchecked_rounded,
                            color: isDone
                                ? Colors.green
                                : isCurrent
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _getStageLabel(stage),
                            style: TextStyle(
                              color: isCurrent || isDone
                                  ? Colors.white
                                  : Colors.grey.shade400,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_isCompleted) ...[
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.secondary,
                      theme.colorScheme.secondary.withAlpha(200),
                    ],
                  ),
                ),
                child: ElevatedButton.icon(
                  onPressed: _navigateToPlayer,
                  icon: const Icon(Icons.play_circle_fill_rounded,
                      color: Colors.black),
                  label: const Text(
                    'Voir le résultat MIDI',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
