import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

class _MeasureJumpControl extends StatefulWidget {
  const _MeasureJumpControl({
    required this.currentMeasure,
    required this.totalMeasures,
    required this.enabled,
    required this.onJump,
    super.key,
  });

  final int currentMeasure;
  final int totalMeasures;
  final bool enabled;
  final Future<void> Function(int measure) onJump;

  @override
  State<_MeasureJumpControl> createState() => _MeasureJumpControlState();
}

class _MeasureJumpControlState extends State<_MeasureJumpControl> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.currentMeasure}');
  final FocusNode _focusNode = FocusNode();
  String? _errorText;

  @override
  void didUpdateWidget(covariant _MeasureJumpControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMeasure != widget.currentMeasure &&
        !_focusNode.hasFocus) {
      _controller.text = '${widget.currentMeasure}';
      _errorText = null;
    }
  }

  Future<void> _jump() async {
    final measure = int.tryParse(_controller.text.trim());
    if (measure == null || measure < 1 || measure > widget.totalMeasures) {
      setState(() {
        _errorText = 'Choisissez une mesure de 1 à ${widget.totalMeasures}.';
      });
      return;
    }

    setState(() => _errorText = null);
    _focusNode.unfocus();
    await widget.onJump(measure);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('measure_jump_field'),
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _jump(),
              style: Theme.of(context).textTheme.labelMedium,
              decoration: InputDecoration(
                labelText: 'Mesure',
                isDense: true,
                errorText: _errorText,
                suffixText: '/ ${widget.totalMeasures}',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            key: const Key('measure_jump_button'),
            onPressed: widget.enabled ? _jump : null,
            tooltip: 'Aller à la mesure',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
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
  int? _pendingSeekTick;
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
          onTestAudio: _testPlaybackAudio,
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

  Future<void> _testPlaybackAudio(
    MidiPlayerConfiguration configuration,
  ) async {
    final configuredBytes = MidiConfiguration.apply(_midiBytes!, configuration);
    await _playback.prepare(configuredBytes);
    _hasPreparedPlayback = true;
    await _playback.testNote(
      instrumentProgram: configuration.instrumentProgram,
      volumePercent: configuration.volumePercent,
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
        final pendingSeekTick = _pendingSeekTick;
        if (pendingSeekTick != null) {
          await _playback.seek(pendingSeekTick);
          _pendingSeekTick = null;
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

  Future<void> _seekToMeasure(int measureIndex) async {
    if (_isPreparingPlayback ||
        measureIndex < 0 ||
        measureIndex >= _score!.measures.length) {
      return;
    }

    final operation = _seekToMeasureAction(measureIndex);
    _playbackOperation = operation;
    await operation;
  }

  Future<void> _seekToMeasureAction(int measureIndex) async {
    final tick = _score!.measures[measureIndex].startTick;
    final wasPlaying = _isPlaying;
    var pausedForSeek = false;
    setState(() {
      _isPreparingPlayback = true;
      _playbackError = null;
    });

    try {
      _playbackPosition.value = tick;
      _pendingSeekTick = tick;

      if (_hasPreparedPlayback) {
        if (wasPlaying) {
          await _playback.pause();
          pausedForSeek = true;
          _positionTimer?.cancel();
        } else if (_playbackComplete) {
          await _playback.stop();
        }
        await _playback.seek(tick);
        _pendingSeekTick = null;
        if (wasPlaying) {
          await _playback.play();
          pausedForSeek = false;
        }
      }

      if (mounted) {
        setState(() {
          _isPlaying = wasPlaying;
          _playbackComplete = false;
        });
        if (wasPlaying) _startPositionPolling();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (pausedForSeek) _isPlaying = false;
          _playbackError =
              'Impossible de rejoindre cette mesure : ${error.toString()}';
        });
      }
      if (pausedForSeek) _positionTimer?.cancel();
    } finally {
      if (mounted) setState(() => _isPreparingPlayback = false);
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
      _pendingSeekTick = 0;
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
                  ? _PianoRoll(
                      notes: visualization.notes,
                      ticksPerBeat: visualization.ticksPerBeat,
                      tempoBpm: configuration.tempoBpm,
                      totalTicks: visualization.totalTicks,
                      currentTick: _playbackPosition,
                      isPlaying: _isPlaying,
                      lowPitch: pitchRange.$1,
                      highPitch: pitchRange.$2,
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
            final measureIndex =
                activeMeasure < 0 ? score.measures.length - 1 : activeMeasure;
            final measureNumber = measureIndex + 1;
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
                      _MeasureJumpControl(
                        key: const Key('measure_jump_control'),
                        currentMeasure: measureNumber,
                        totalMeasures: score.measures.length,
                        enabled:
                            !_isPreparingPlayback && score.measures.isNotEmpty,
                        onJump: (measure) => _seekToMeasure(measure - 1),
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

class _PianoRoll extends StatefulWidget {
  const _PianoRoll({
    required this.notes,
    required this.ticksPerBeat,
    required this.tempoBpm,
    required this.totalTicks,
    required this.currentTick,
    required this.isPlaying,
    required this.lowPitch,
    required this.highPitch,
  });

  final List<MidiNote> notes;
  final int ticksPerBeat;
  final int tempoBpm;
  final int totalTicks;
  final ValueListenable<int> currentTick;
  final bool isPlaying;
  final int lowPitch;
  final int highPitch;

  @override
  State<_PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<_PianoRoll>
    with SingleTickerProviderStateMixin {
  late final _PianoRollTimeline _timeline =
      _PianoRollTimeline(widget.notes, widget.ticksPerBeat);
  late final AnimationController _frameController;
  late final ValueNotifier<double> _smoothTick;
  late final Stopwatch _clock;
  late double _anchorTick;
  late Duration _anchorTime;
  late Duration _lastNativeTime;
  late int _lastNativeTick;
  late double _ticksPerSecond;

  @override
  void initState() {
    super.initState();
    final tick = widget.currentTick.value.toDouble();
    _clock = Stopwatch()..start();
    _anchorTick = tick;
    _anchorTime = _clock.elapsed;
    _lastNativeTime = _anchorTime;
    _lastNativeTick = tick.round();
    _ticksPerSecond = widget.ticksPerBeat * widget.tempoBpm / 60;
    _smoothTick = ValueNotifier<double>(tick);
    _frameController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateSmoothedTick);
    if (widget.isPlaying) _frameController.repeat();
    widget.currentTick.addListener(_handlePositionChanged);
  }

  @override
  void didUpdateWidget(covariant _PianoRoll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTick != widget.currentTick) {
      oldWidget.currentTick.removeListener(_handlePositionChanged);
      widget.currentTick.addListener(_handlePositionChanged);
      _resetClock(widget.currentTick.value.toDouble());
    }
    if (oldWidget.tempoBpm != widget.tempoBpm) {
      _ticksPerSecond = widget.ticksPerBeat * widget.tempoBpm / 60;
    }
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _resetClock(_smoothTick.value);
        _frameController.repeat();
      } else {
        _frameController.stop();
        _resetClock(widget.currentTick.value.toDouble());
      }
    }
  }

  void _resetClock(double tick) {
    _anchorTick = tick;
    _anchorTime = _clock.elapsed;
    _lastNativeTick = widget.currentTick.value;
    _lastNativeTime = _anchorTime;
    _smoothTick.value = tick;
  }

  void _updateSmoothedTick() {
    final elapsed = _clock.elapsed - _anchorTime;
    final tick = (_anchorTick +
            elapsed.inMicroseconds /
                Duration.microsecondsPerSecond *
                _ticksPerSecond)
        .clamp(0.0, widget.totalTicks.toDouble())
        .toDouble();
    if ((tick - _smoothTick.value).abs() >= 0.001) {
      _smoothTick.value = tick;
    }
  }

  void _handlePositionChanged() {
    final nativeTick = widget.currentTick.value;
    final now = _clock.elapsed;
    final elapsed = now - _lastNativeTime;
    final tickDelta = nativeTick - _lastNativeTick;

    if (!widget.isPlaying || tickDelta < 0 || elapsed.inMilliseconds > 1000) {
      _resetClock(nativeTick.toDouble());
    } else {
      if (tickDelta > 0 && elapsed.inMicroseconds > 0) {
        final observedRate =
            tickDelta * Duration.microsecondsPerSecond / elapsed.inMicroseconds;
        _ticksPerSecond = _ticksPerSecond * 0.35 + observedRate * 0.65;
      }

      final elapsedSinceAnchor = now - _anchorTime;
      final predictedTick = _anchorTick +
          elapsedSinceAnchor.inMicroseconds /
              Duration.microsecondsPerSecond *
              _ticksPerSecond;
      final correction = nativeTick - predictedTick;
      if (correction.abs() > _ticksPerSecond * 0.5) {
        _anchorTick = nativeTick.toDouble();
      } else {
        _anchorTick = predictedTick + correction * 0.65;
      }
      _anchorTime = now;
      _lastNativeTick = nativeTick;
      _lastNativeTime = now;
    }
  }

  @override
  void dispose() {
    widget.currentTick.removeListener(_handlePositionChanged);
    _frameController.removeListener(_updateSmoothedTick);
    _frameController.dispose();
    _smoothTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('piano_roll_view'),
      color: const Color(0xFF090A0E),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _PianoGridPainter(
                      lowPitch: widget.lowPitch,
                      highPitch: widget.highPitch,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _PianoNotesPainter(
                      timeline: _timeline,
                      currentTick: _smoothTick,
                      lowPitch: widget.lowPitch,
                      highPitch: widget.highPitch,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 72,
            child: _PianoKeyboard(
              timeline: _timeline,
              currentTick: _smoothTick,
              lowPitch: widget.lowPitch,
              highPitch: widget.highPitch,
            ),
          ),
        ],
      ),
    );
  }
}

class _PianoRollTimeline {
  _PianoRollTimeline(this.notes, this.ticksPerBeat)
      : visibleTicks = ticksPerBeat * 8 {
    final mutableBuckets = <int, List<int>>{};
    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      if (note.endTick - note.startTick > visibleTicks) {
        _longNotes.add(index);
        continue;
      }
      final firstBucket = note.startTick ~/ ticksPerBeat;
      final lastBucket = note.endTick ~/ ticksPerBeat;
      for (var bucket = firstBucket; bucket <= lastBucket; bucket++) {
        mutableBuckets.putIfAbsent(bucket, () => <int>[]).add(index);
      }
    }
    _buckets = mutableBuckets;
  }

  final List<MidiNote> notes;
  final int ticksPerBeat;
  final int visibleTicks;
  late final Map<int, List<int>> _buckets;
  final List<int> _longNotes = [];

  Iterable<int> visibleNoteIndices(int currentTick) sync* {
    final indices = <int>{};
    final firstBucket = math.max(0, currentTick) ~/ ticksPerBeat;
    final lastBucket = (currentTick + visibleTicks) ~/ ticksPerBeat;
    for (var bucket = firstBucket; bucket <= lastBucket; bucket++) {
      indices.addAll(_buckets[bucket] ?? const <int>[]);
    }
    indices.addAll(_longNotes);

    final ordered = indices.toList()..sort();
    for (final index in ordered) {
      final note = notes[index];
      if (note.endTick >= currentTick &&
          note.startTick <= currentTick + visibleTicks) {
        yield index;
      }
    }
  }

  Set<int> activePitches(int currentTick) => {
        for (final index in visibleNoteIndices(currentTick))
          if (notes[index].startTick <= currentTick &&
              notes[index].endTick > currentTick)
            notes[index].pitch,
      };
}

class _PianoGridPainter extends CustomPainter {
  const _PianoGridPainter({
    required this.lowPitch,
    required this.highPitch,
  });

  final int lowPitch;
  final int highPitch;

  @override
  void paint(Canvas canvas, Size size) {
    final hitLine = size.height * 0.9;
    final pitchWidth = size.width / (highPitch - lowPitch);
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (var pitch = lowPitch; pitch <= highPitch; pitch++) {
      final x = (pitch - lowPitch) * pitchWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, hitLine), gridPaint);
    }
    for (var beat = 0; beat <= 8; beat++) {
      final y = hitLine - (beat / 8) * hitLine;
      gridPaint.strokeWidth = beat % 4 == 0 ? 1.5 : 0.7;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(
      Offset(0, hitLine),
      Offset(size.width, hitLine),
      Paint()
        ..color = Colors.pinkAccent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PianoGridPainter oldDelegate) =>
      oldDelegate.lowPitch != lowPitch || oldDelegate.highPitch != highPitch;
}

class _PianoNotesPainter extends CustomPainter {
  _PianoNotesPainter({
    required this.timeline,
    required this.currentTick,
    required this.lowPitch,
    required this.highPitch,
  }) : super(repaint: currentTick);

  final _PianoRollTimeline timeline;
  final ValueListenable<double> currentTick;
  final int lowPitch;
  final int highPitch;
  final Map<int, TextPainter> _labels = {};

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
    final visibleTicks = timeline.visibleTicks;
    final tick = currentTick.value;
    final notePaint = Paint()..style = PaintingStyle.fill;
    final radius = Radius.circular(pitchWidth.clamp(2, 8).toDouble());

    for (final index in timeline.visibleNoteIndices(tick.floor())) {
      final note = timeline.notes[index];
      if (note.pitch < lowPitch || note.pitch >= highPitch) continue;

      final startOffset = note.startTick - tick;
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
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), notePaint);
      if (rect.height > 22 && rect.width > 24) {
        final label = _labels.putIfAbsent(
          index,
          () => TextPainter(
            text: TextSpan(
              text: _noteName(note.pitch),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: rect.width - 4),
        );
        label.paint(
          canvas,
          Offset(rect.left + 2, rect.top + rect.height - label.height - 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PianoNotesPainter oldDelegate) =>
      oldDelegate.timeline != timeline ||
      oldDelegate.currentTick != currentTick ||
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
    required this.timeline,
    required this.currentTick,
    required this.lowPitch,
    required this.highPitch,
  });

  final _PianoRollTimeline timeline;
  final ValueListenable<double> currentTick;
  final int lowPitch;
  final int highPitch;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PianoKeyboardPainter(
        timeline: timeline,
        currentTick: currentTick,
        lowPitch: lowPitch,
        highPitch: highPitch,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PianoKeyboardPainter extends CustomPainter {
  _PianoKeyboardPainter({
    required this.timeline,
    required this.currentTick,
    required this.lowPitch,
    required this.highPitch,
  }) : super(repaint: currentTick);

  final _PianoRollTimeline timeline;
  final ValueListenable<double> currentTick;
  final int lowPitch;
  final int highPitch;

  static const _blackKeyClasses = {1, 3, 6, 8, 10};
  static const _whiteKeyClasses = {0, 2, 4, 5, 7, 9, 11};
  late final List<int> _whitePitches = [
    for (var pitch = lowPitch; pitch < highPitch; pitch++)
      if (_whiteKeyClasses.contains(pitch % 12)) pitch,
  ];
  final Map<int, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    final activePitches = timeline.activePitches(currentTick.value.floor());
    final whitePitches = _whitePitches;
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
        final label = _labels.putIfAbsent(
          pitch,
          () => TextPainter(
            text: TextSpan(
              text: 'C${pitch ~/ 12 - 1}',
              style: const TextStyle(color: Colors.black54, fontSize: 9),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: whiteWidth - 2),
        );
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
      oldDelegate.timeline != timeline ||
      oldDelegate.lowPitch != lowPitch ||
      oldDelegate.highPitch != highPitch;
}
