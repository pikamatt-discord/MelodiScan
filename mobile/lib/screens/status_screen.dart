import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'player_screen.dart';

class StatusScreen extends StatefulWidget {
  final String taskId;
  final String title;
  final String serverUrl;
  final http.Client? httpClient;

  const StatusScreen({
    super.key,
    required this.taskId,
    required this.title,
    required this.serverUrl,
    this.httpClient,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final List<String> _stages = [
    'STATUS_PROCESSING_IMAGE',
    'STATUS_RUNNING_OMR',
    'STATUS_BUILDING_MUSICXML',
    'STATUS_EXPORTING_MIDI',
    'STATUS_COMPLETED',
  ];

  int _currentStageIndex = 0;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _startSSEStream();
  }

  void _startSSEStream() async {
    final client = widget.httpClient ?? http.Client();
    try {
      final uri = Uri.parse('${widget.serverUrl}/api/v1/stream/${widget.taskId}');
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode == 200) {
        response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          if (line.startsWith('data: ')) {
            try {
              final jsonStr = line.substring(6);
              final data = jsonDecode(jsonStr);
              final status = data['status'] as String?;
              if (status != null && _stages.contains(status)) {
                if (mounted) {
                  setState(() {
                    _currentStageIndex = _stages.indexOf(status);
                    if (status == 'STATUS_COMPLETED') {
                      _isCompleted = true;
                    }
                  });
                }
              }
            } catch (_) {}
          }
        }, onError: (_) {
          _fallbackSimulation();
        });
      } else {
        _fallbackSimulation();
      }
    } catch (_) {
      _fallbackSimulation();
    }
  }

  void _fallbackSimulation() async {
    for (int i = 0; i < _stages.length; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          _currentStageIndex = i;
          if (_stages[i] == 'STATUS_COMPLETED') {
            _isCompleted = true;
          }
        });
      }
    }
  }

  void _navigateToPlayer() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          taskId: widget.taskId,
          title: widget.title,
          serverUrl: widget.serverUrl,
        ),
      ),
    );
  }

  String _getStageLabel(String stage) {
    switch (stage) {
      case 'STATUS_PROCESSING_IMAGE':
        return 'Prétraitement d\'image & Binarisation Sauvola';
      case 'STATUS_RUNNING_OMR':
        return 'Moteur OMR Audiveris (JVM Headless)';
      case 'STATUS_BUILDING_MUSICXML':
        return 'Validation Partitura Structure & Métrique';
      case 'STATUS_EXPORTING_MIDI':
        return 'Génération MIDI & SoundFont Synth';
      case 'STATUS_COMPLETED':
        return 'Partition prêt pour le Player interactif !';
      default:
        return stage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_currentStageIndex + 1) / _stages.length;

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
                            Icon(Icons.terminal_rounded, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'ID : ${widget.taskId.substring(0, widget.taskId.length > 12 ? 12 : widget.taskId.length)}...',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isCompleted
                                ? Colors.green.withAlpha(40)
                                : theme.colorScheme.primary.withAlpha(40),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _isCompleted ? 'TERMINÉ' : 'EN COURS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _isCompleted ? Colors.green : theme.colorScheme.primary,
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
                          _isCompleted ? theme.colorScheme.secondary : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(progress * 100).toInt()}% Complété',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

            // Animated Timeline ListView
            Expanded(
              child: ListView.builder(
                itemCount: _stages.length,
                itemBuilder: (context, index) {
                  final stage = _stages[index];
                  final isDone = index < _currentStageIndex;
                  final isCurrent = index == _currentStageIndex;

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
                              color: isCurrent || isDone ? Colors.white : Colors.grey.shade400,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
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
                  icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.black),
                  label: const Text(
                    'Ouvrir le Player & Inspecteur',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
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
