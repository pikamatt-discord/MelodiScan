import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/musicxml_score.dart';
import '../models/midi_visualization.dart';
import '../network/api_client.dart';
import 'player_configuration_screen.dart';
import '../services/midi_configuration.dart';
import '../services/midi_playback.dart';
import '../widgets/traditional_score.dart';

class PlayerScreen extends StatefulWidget {
  final String taskId;
  final String title;
  final String serverUrl;
  final String apiKey;
  final http.Client? httpClient;
  final MidiPlayback? midiPlayback;

  const PlayerScreen({
    super.key,
    required this.taskId,
    required this.title,
    required this.serverUrl,
    this.apiKey = '',
    this.httpClient,
    this.midiPlayback,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isLoading = true;
  Uint8List? _midiBytes;
  MidiVisualization? _visualization;
  MusicXmlScore? _score;
  MidiPlayerConfiguration? _configuration;
  String? _errorMessage;
  String? _playbackError;
  bool _isPreparingPlayback = false;
  bool _isPlaying = false;
  bool _playbackComplete = false;
  bool _hasPreparedPlayback = false;
  bool _showPianoRoll = false;
  final ValueNotifier<int> _playbackPosition = ValueNotifier<int>(0);
  bool _isReadingPosition = false;
  Timer? _positionTimer;
  Future<void>? _playbackOperation;
  late final MidiPlayback _playback =
      widget.midiPlayback ?? FlutterMidiPlayback();

  @override
  void initState() {
    super.initState();
    _fetchMidiResult();
  }

  Future<void> _fetchMidiResult() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _midiBytes = null;
      _visualization = null;
      _score = null;
      _configuration = null;
      _playbackPosition.value = 0;
    });

    try {
      final client = widget.httpClient ?? createApiClient();
      final midiUri =
          Uri.parse('${widget.serverUrl}/api/v1/result/${widget.taskId}');
      final musicXmlUri = Uri.parse(
        '${widget.serverUrl}/api/v1/result/${widget.taskId}/musicxml',
      );
      final headers =
          widget.apiKey.isEmpty ? null : {'X-API-Key': widget.apiKey};
      final responses = await Future.wait([
        client.get(midiUri, headers: headers).timeout(
              const Duration(seconds: 20),
            ),
        client.get(musicXmlUri, headers: headers).timeout(
              const Duration(seconds: 20),
            ),
      ]);
      final midiResponse = responses[0];
      final musicXmlResponse = responses[1];
      if (midiResponse.statusCode != 200) {
        throw StateError(_responseError(midiResponse));
      }
      if (musicXmlResponse.statusCode != 200) {
        throw StateError(_responseError(musicXmlResponse));
      }

      final bytes = midiResponse.bodyBytes;
      if (!_isMidiFile(bytes)) {
        throw const FormatException(
            'Le serveur n’a pas renvoyé un fichier MIDI valide.');
      }
      final visualization = MidiVisualization.parse(bytes);
      final configuration = MidiConfiguration.defaultsFor(bytes);
      final score = MusicXmlScore.parse(
        utf8.decode(musicXmlResponse.bodyBytes),
        ticksPerBeat: visualization.ticksPerBeat,
      );

      if (mounted) {
        setState(() {
          _midiBytes = bytes;
          _visualization = visualization;
          _score = score;
          _configuration = configuration;
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

  Future<void> _togglePlayback() async {
    if (_isPreparingPlayback || _midiBytes == null || !_playback.isSupported) {
      return;
    }

    final operation = _runPlaybackAction();
    _playbackOperation = operation;
    await operation;
  }

  Future<void> _openConfiguration() async {
    final configuration = _configuration;
    if (configuration == null || _isPlaying || _isPreparingPlayback) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerConfigurationScreen(
          initialConfiguration: configuration,
          onSave: (updatedConfiguration) async {
            if (!mounted) return;
            setState(() {
              _configuration = updatedConfiguration;
              _hasPreparedPlayback = false;
              _playbackComplete = false;
              _playbackPosition.value = 0;
              _playbackError = null;
            });
          },
        ),
      ),
    );
  }

  Future<void> _runPlaybackAction() async {
    final wasPlaying = _isPlaying;
    setState(() {
      _isPreparingPlayback = true;
      _playbackError = null;
    });

    try {
      if (!_hasPreparedPlayback) {
        final configuredBytes =
            MidiConfiguration.apply(_midiBytes!, _configuration!);
        await _playback.prepare(configuredBytes);
        _hasPreparedPlayback = true;
      }

      if (wasPlaying) {
        await _playback.pause();
        _positionTimer?.cancel();
        final position = await _playback.getPosition();
        if (mounted) {
          _playbackPosition.value = position.currentTick;
        }
      } else {
        if (_playbackComplete) {
          await _playback.stop();
        }
        await _playback.play();
      }
      if (mounted) {
        setState(() {
          _isPlaying = !wasPlaying;
          _playbackComplete = false;
        });
        if (!wasPlaying) _startPositionPolling();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _playbackError =
              'Impossible de lire ce fichier MIDI : ${error.toString().replaceFirst('Bad state: ', '')}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPreparingPlayback = false);
      }
    }
  }

  Future<void> _stopPlayback() async {
    if (_isPreparingPlayback || !_hasPreparedPlayback) return;
    setState(() {
      _isPreparingPlayback = true;
      _playbackError = null;
    });
    final operation = _stopPlaybackAction();
    _playbackOperation = operation;
    await operation;
  }

  Future<void> _stopPlaybackAction() async {
    try {
      await _playback.stop();
      _positionTimer?.cancel();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackComplete = false;
          _playbackPosition.value = 0;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _playbackError =
            'Impossible d’arrêter la lecture : ${error.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isPreparingPlayback = false);
      }
    }
  }

  void _startPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _refreshPlaybackPosition(),
    );
    unawaited(_refreshPlaybackPosition());
  }

  Future<void> _refreshPlaybackPosition() async {
    if (_isReadingPosition || !mounted) return;
    _isReadingPosition = true;
    try {
      final position = await _playback.getPosition();
      if (!mounted) return;
      _playbackPosition.value = position.currentTick;
      if (_isPlaying != position.isPlaying ||
          _playbackComplete != position.isComplete) {
        setState(() {
          _isPlaying = position.isPlaying;
          _playbackComplete = position.isComplete;
        });
      }
      if (!position.isPlaying) {
        _positionTimer?.cancel();
      }
    } catch (error) {
      _positionTimer?.cancel();
      if (mounted) {
        setState(() => _playbackError =
            'Impossible de suivre la lecture MIDI : ${error.toString()}');
      }
    } finally {
      _isReadingPosition = false;
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _playbackPosition.dispose();
    final pendingOperation = _playbackOperation;
    if (pendingOperation == null) {
      unawaited(_disposePlayback());
    } else {
      unawaited(pendingOperation.whenComplete(_disposePlayback));
    }
    super.dispose();
  }

  Future<void> _disposePlayback() async {
    try {
      await _playback.dispose();
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'MelodiScan MIDI player',
        context: ErrorDescription('while releasing MIDI playback resources'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('player_configuration_button'),
            onPressed: _isLoading || _isPlaying || _isPreparingPlayback
                ? null
                : _openConfiguration,
            tooltip: 'Configurer la lecture',
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _buildError(theme),
                    ),
                  )
                : _buildMidiResult(theme),
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
    final playbackSupported = _playback.isSupported;
    final visualization = _visualization!;
    final score = _score!;
    final configuration = _configuration!;
    final pitchRange = _pitchRange(visualization.notes);
    final instrument =
        GeneralMidiInstrument.byProgram(configuration.instrumentProgram);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.16),
                    child: Icon(Icons.music_note,
                        color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${instrument.name}  ·  ${configuration.tempoBpm} BPM  ·  ${visualization.notes.length} notes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SegmentedButton<bool>(
            key: const Key('player_view_mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.music_note),
                label: Text('Partition'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.piano),
                label: Text('Piano roll'),
              ),
            ],
            selected: {_showPianoRoll},
            onSelectionChanged: (selection) =>
                setState(() => _showPianoRoll = selection.first),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _showPianoRoll
                  ? ValueListenableBuilder<int>(
                      valueListenable: _playbackPosition,
                      builder: (context, currentTick, _) {
                        final activePitches = {
                          for (final note in visualization.notes)
                            if (currentTick >= note.startTick &&
                                currentTick < note.endTick)
                              note.pitch,
                        };
                        return Column(
                          children: [
                            Expanded(
                              child: _PianoRoll(
                                notes: visualization.notes,
                                ticksPerBeat: visualization.ticksPerBeat,
                                currentTick: currentTick,
                                lowPitch: pitchRange.$1,
                                highPitch: pitchRange.$2,
                              ),
                            ),
                            SizedBox(
                              height: 72,
                              child: _PianoKeyboard(
                                lowPitch: pitchRange.$1,
                                highPitch: pitchRange.$2,
                                activePitches: activePitches,
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : TraditionalScore(
                      score: score,
                      currentTick: _playbackPosition,
                    ),
            ),
          ),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _playbackPosition,
          builder: (context, currentTick, _) {
            final progress = (visualization.totalTicks == 0
                    ? 0.0
                    : currentTick / visualization.totalTicks)
                .clamp(0.0, 1.0);
            final activeMeasure = score.measures.isEmpty
                ? 0
                : score.measures
                    .indexWhere((measure) => currentTick < measure.endTick);
            final measureNumber =
                activeMeasure < 0 ? score.measures.length : activeMeasure + 1;
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('playback_progress'),
                      value: progress,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        score.measures.isEmpty
                            ? 'Mesure —'
                            : 'Mesure $measureNumber / ${score.measures.length}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white60),
                      ),
                      const Spacer(),
                      Text(
                        '${(progress * 100).round()} %',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (playbackSupported) ...[
                IconButton.filledTonal(
                  key: const Key('stop_playback'),
                  onPressed: _isPreparingPlayback || !_hasPreparedPlayback
                      ? null
                      : _stopPlayback,
                  tooltip: 'Arrêter et revenir au début',
                  icon: const Icon(Icons.stop_rounded),
                  iconSize: 28,
                ),
                const SizedBox(width: 14),
                FilledButton.icon(
                  key: const Key('play_pause_fab'),
                  onPressed: _isPreparingPlayback ? null : _togglePlayback,
                  icon: _isPreparingPlayback
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(
                    _isPreparingPlayback
                        ? 'Préparation…'
                        : _isPlaying
                            ? 'Pause'
                            : _playbackComplete
                                ? 'Rejouer'
                                : 'Lire',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                ),
              ] else
                const Text('Lecture disponible sur Android 7+'),
            ],
          ),
        ),
        if (playbackSupported && !_hasPreparedPlayback)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              'La première lecture télécharge la banque sonore GM (32 Mo). '
              'Elle sera ensuite disponible hors ligne.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ),
        if (_playbackError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              _playbackError!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  (int, int) _pitchRange(List<MidiNote> notes) {
    final lowest =
        notes.map((note) => note.pitch).reduce((a, b) => a < b ? a : b);
    final highest =
        notes.map((note) => note.pitch).reduce((a, b) => a > b ? a : b);
    var low = (lowest ~/ 12) * 12;
    var high = ((highest ~/ 12) + 1) * 12;
    if (high - low < 24) {
      low = ((low - 12) ~/ 12) * 12;
      high = low + 24;
    }
    if (low < 24) {
      high += 24 - low;
      low = 24;
    }
    if (high > 108) {
      low -= high - 108;
      high = 108;
    }
    return (low, high);
  }
}

class _PianoRoll extends StatelessWidget {
  const _PianoRoll({
    required this.notes,
    required this.ticksPerBeat,
    required this.currentTick,
    required this.lowPitch,
    required this.highPitch,
  });

  final List<MidiNote> notes;
  final int ticksPerBeat;
  final int currentTick;
  final int lowPitch;
  final int highPitch;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('piano_roll_view'),
      color: const Color(0xFF090A0E),
      child: CustomPaint(
        painter: _PianoRollPainter(
          notes: notes,
          ticksPerBeat: ticksPerBeat,
          currentTick: currentTick,
          lowPitch: lowPitch,
          highPitch: highPitch,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PianoRollPainter extends CustomPainter {
  const _PianoRollPainter({
    required this.notes,
    required this.ticksPerBeat,
    required this.currentTick,
    required this.lowPitch,
    required this.highPitch,
  });

  final List<MidiNote> notes;
  final int ticksPerBeat;
  final int currentTick;
  final int lowPitch;
  final int highPitch;

  static const _colors = [
    Color(0xFF73B7FF),
    Color(0xFF9BE640),
    Color(0xFFFFB74D),
    Color(0xFFCE93D8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pitchWidth = size.width / (highPitch - lowPitch);
    final hitLine = size.height * 0.9;
    final visibleTicks = ticksPerBeat * 8;
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (var pitch = lowPitch; pitch <= highPitch; pitch++) {
      final x = (pitch - lowPitch) * pitchWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, hitLine), gridPaint);
    }
    for (var beat = 0; beat <= 8; beat++) {
      final y = hitLine - (beat / 8) * hitLine;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint..strokeWidth = beat % 4 == 0 ? 1.5 : 0.7,
      );
    }

    final notePaint = Paint()..style = PaintingStyle.fill;
    for (final note in notes) {
      if (note.pitch < lowPitch ||
          note.pitch >= highPitch ||
          note.endTick < currentTick ||
          note.startTick > currentTick + visibleTicks) {
        continue;
      }
      final startOffset = note.startTick - currentTick;
      final duration = note.endTick - note.startTick;
      final bottom = hitLine - (startOffset / visibleTicks) * hitLine;
      final top = bottom - (duration / visibleTicks) * hitLine;
      final rect = Rect.fromLTRB(
        (note.pitch - lowPitch) * pitchWidth + 2,
        top.clamp(0, hitLine).toDouble(),
        (note.pitch - lowPitch + 1) * pitchWidth - 2,
        bottom.clamp(0, hitLine).toDouble(),
      );
      if (rect.height <= 0 || rect.width <= 0) continue;

      notePaint.color = _colors[note.channel % _colors.length]
          .withValues(alpha: 0.55 + note.velocity / 280);
      final radius = Radius.circular(pitchWidth.clamp(2, 8).toDouble());
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        notePaint,
      );
      if (rect.height > 22 && rect.width > 24) {
        final label = TextPainter(
          text: TextSpan(
            text: _noteName(note.pitch),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width - 4);
        label.paint(
          canvas,
          Offset(rect.left + 2, rect.top + rect.height - label.height - 2),
        );
      }
    }

    final hitPaint = Paint()
      ..color = Colors.pinkAccent
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, hitLine),
      Offset(size.width, hitLine),
      hitPaint,
    );
  }

  @override
  bool shouldRepaint(_PianoRollPainter oldDelegate) =>
      oldDelegate.currentTick != currentTick ||
      oldDelegate.notes != notes ||
      oldDelegate.lowPitch != lowPitch ||
      oldDelegate.highPitch != highPitch;

  String _noteName(int pitch) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    return '${names[pitch % 12]}${pitch ~/ 12 - 1}';
  }
}

class _PianoKeyboard extends StatelessWidget {
  const _PianoKeyboard({
    required this.lowPitch,
    required this.highPitch,
    required this.activePitches,
  });

  final int lowPitch;
  final int highPitch;
  final Set<int> activePitches;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PianoKeyboardPainter(
        lowPitch: lowPitch,
        highPitch: highPitch,
        activePitches: activePitches,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PianoKeyboardPainter extends CustomPainter {
  const _PianoKeyboardPainter({
    required this.lowPitch,
    required this.highPitch,
    required this.activePitches,
  });

  final int lowPitch;
  final int highPitch;
  final Set<int> activePitches;

  static const _blackKeyClasses = {1, 3, 6, 8, 10};
  static const _whiteKeyClasses = {0, 2, 4, 5, 7, 9, 11};

  @override
  void paint(Canvas canvas, Size size) {
    final whitePitches = [
      for (var pitch = lowPitch; pitch < highPitch; pitch++)
        if (_whiteKeyClasses.contains(pitch % 12)) pitch,
    ];
    if (whitePitches.isEmpty) return;

    final whiteWidth = size.width / whitePitches.length;
    final whitePaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < whitePitches.length; index++) {
      final pitch = whitePitches[index];
      whitePaint.color = activePitches.contains(pitch)
          ? const Color(0xFF9BE640)
          : const Color(0xFFF7F5EF);
      final left = index * whiteWidth;
      canvas.drawRect(
        Rect.fromLTWH(left, 0, whiteWidth - 1, size.height),
        whitePaint,
      );
      canvas.drawLine(
        Offset(left, 0),
        Offset(left, size.height),
        Paint()
          ..color = Colors.black26
          ..strokeWidth = 1,
      );
      if (pitch % 12 == 0 && whiteWidth > 13) {
        final label = TextPainter(
          text: TextSpan(
            text: 'C${pitch ~/ 12 - 1}',
            style: const TextStyle(color: Colors.black54, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: whiteWidth - 2);
        label.paint(
          canvas,
          Offset(left + 2, size.height - label.height - 3),
        );
      }
    }

    final blackWidth = whiteWidth * 0.62;
    final blackHeight = size.height * 0.64;
    final blackPaint = Paint()..style = PaintingStyle.fill;
    for (var pitch = lowPitch; pitch < highPitch; pitch++) {
      if (!_blackKeyClasses.contains(pitch % 12)) continue;
      final previousWhiteCount =
          whitePitches.where((whitePitch) => whitePitch < pitch).length;
      final left = previousWhiteCount * whiteWidth - blackWidth / 2;
      blackPaint.color = activePitches.contains(pitch)
          ? const Color(0xFF67C92D)
          : const Color(0xFF101116);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, blackWidth, blackHeight),
          const Radius.circular(2),
        ),
        blackPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PianoKeyboardPainter oldDelegate) =>
      oldDelegate.activePitches != activePitches ||
      oldDelegate.lowPitch != lowPitch ||
      oldDelegate.highPitch != highPitch;
}
