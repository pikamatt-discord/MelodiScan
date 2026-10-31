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
  bool _isConnecting = true;

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
        if (mounted) setState(() => _isConnecting = false);
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
      if (mounted) setState(() => _isConnecting = false);
    } catch (error) {
      _isConnecting = false;
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
        final error = data['error'];
        _setError(error is String && error.isNotEmpty
            ? error
            : 'Le traitement a échoué. Consultez les diagnostics dans le dashboard.');
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

  String _getStageDescription(String stage) {
    switch (stage) {
      case 'STATUS_QUEUED':
        return 'Votre demande attend qu’un worker soit disponible.';
      case 'STATUS_PROCESSING_IMAGE':
        return 'Vérification et préparation de l’image envoyée.';
      case 'STATUS_RUNNING_OMR':
        return 'Audiveris repère les portées et reconnaît les notes.';
      case 'STATUS_BUILDING_MUSICXML':
        return 'La partition reconnue est mise en forme.';
      case 'STATUS_EXPORTING_MIDI':
        return 'Création du fichier MIDI à écouter.';
      case 'STATUS_COMPLETED':
        return 'Votre partition et votre fichier MIDI sont prêts.';
      default:
        return 'Préparation de votre partition.';
    }
  }

  IconData _getStageIcon(String stage) {
    switch (stage) {
      case 'STATUS_QUEUED':
        return Icons.hourglass_top_rounded;
      case 'STATUS_PROCESSING_IMAGE':
        return Icons.image_search_rounded;
      case 'STATUS_RUNNING_OMR':
        return Icons.music_note_rounded;
      case 'STATUS_BUILDING_MUSICXML':
        return Icons.auto_awesome_rounded;
      case 'STATUS_EXPORTING_MIDI':
        return Icons.piano_rounded;
      case 'STATUS_COMPLETED':
        return Icons.check_rounded;
      default:
        return Icons.sync_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _currentStageIndex / (_stages.length - 1);
    final currentStage = _stages[_currentStageIndex];
    final title = _errorMessage != null
        ? 'Traitement interrompu'
        : _isCompleted
            ? 'Votre partition est prête'
            : _getStageLabel(currentStage);
    final description = _errorMessage != null
        ? 'Le suivi du traitement a rencontré une erreur.'
        : _isConnecting
            ? 'Connexion au serveur de traitement…'
            : _getStageDescription(currentStage);

    return Scaffold(
      appBar: AppBar(
        title: Text('Traitement : ${widget.title}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _errorMessage != null
                                  ? theme.colorScheme.error
                                      .withValues(alpha: 0.14)
                                  : _isCompleted
                                      ? theme.colorScheme.secondary
                                          .withValues(alpha: 0.14)
                                      : theme.colorScheme.primary
                                          .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              _errorMessage != null
                                  ? Icons.error_outline_rounded
                                  : _getStageIcon(currentStage),
                              color: _errorMessage != null
                                  ? theme.colorScheme.error
                                  : _isCompleted
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: Text(
                                    title,
                                    key: ValueKey(title),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  key:
                                      const Key('processing_stage_description'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white70,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text(
                            _isCompleted
                                ? 'Traitement terminé'
                                : 'Progression du traitement',
                            style: theme.textTheme.labelLarge,
                          ),
                          const Spacer(),
                          Text(
                            'Étape ${_currentStageIndex + 1} / ${_stages.length}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          key: const Key('processing_progress'),
                          tween: Tween<double>(end: progress),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _isCompleted
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            _isConnecting
                                ? Icons.cloud_sync_rounded
                                : Icons.cloud_done_rounded,
                            size: 15,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _isConnecting
                                  ? 'Connexion au serveur…'
                                  : 'Traitement sur votre serveur',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          Text(
                            'ID ${widget.taskId.substring(0, widget.taskId.length > 12 ? 12 : widget.taskId.length)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Étapes de conversion',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_errorMessage != null)
                    Text(
                      'ÉCHEC',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (_isCompleted)
                    Text(
                      'TERMINÉ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else
                    Text(
                      'EN COURS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemCount: _stages.length,
                itemBuilder: (context, index) {
                  final stage = _stages[index];
                  final isDone = _errorMessage == null &&
                      (index < _currentStageIndex ||
                          (_isCompleted && index == _currentStageIndex));
                  final isCurrent = _errorMessage == null &&
                      !_isCompleted &&
                      index == _currentStageIndex;
                  final accent = isDone
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.primary;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AnimatedContainer(
                      key: ValueKey('processing_stage_$stage'),
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? theme.colorScheme.primary.withValues(alpha: 0.11)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: 0.8)
                              : isDone
                                  ? theme.colorScheme.secondary
                                      .withValues(alpha: 0.35)
                                  : Colors.white.withValues(alpha: 0.06),
                          width: isCurrent ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDone || isCurrent
                                  ? accent.withValues(alpha: 0.16)
                                  : Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isDone
                                  ? Icons.check_rounded
                                  : isCurrent
                                      ? _getStageIcon(stage)
                                      : Icons.radio_button_unchecked_rounded,
                              color:
                                  isDone || isCurrent ? accent : Colors.white38,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStageLabel(stage),
                                  style: TextStyle(
                                    color: isCurrent || isDone
                                        ? Colors.white
                                        : Colors.white54,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    _getStageDescription(stage),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isCurrent)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                key: const Key('processing_activity_indicator'),
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isCompleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _navigateToPlayer,
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: const Text('Ouvrir le lecteur MIDI'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Card(
                  color: theme.colorScheme.error.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
