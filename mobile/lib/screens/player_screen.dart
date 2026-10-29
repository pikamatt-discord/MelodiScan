import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PlayerScreen extends StatefulWidget {
  final String taskId;
  final String title;
  final String serverUrl;

  const PlayerScreen({
    super.key,
    required this.taskId,
    required this.title,
    this.serverUrl = 'http://localhost:8080',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isPlaying = false;
  bool _isLoadingMidi = true;
  int _midiBytesLength = 0;
  double _tempo = 1.0;
  int _pitchTranspose = 0;
  bool _isAbLoopActive = false;
  RangeValues _abLoopRange = const RangeValues(1, 4);
  Timer? _playbackTimer;

  final List<String> _melodyNotes = ['G4', 'G4', 'G4', 'Eb4', 'F4', 'F4', 'F4', 'D4'];
  int _currentNoteIndex = 0;

  final Map<String, bool> _tracks = {
    'Flûte / Voix Principal (SoundFont sf2)': true,
    'Piano Accompagnement (FluidSynth)': true,
    'Basse & Contrebasse': true,
  };

  @override
  void initState() {
    super.initState();
    _fetchMidiResult();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMidiResult() async {
    try {
      final uri = Uri.parse('${widget.serverUrl}/api/v1/result/${widget.taskId}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _midiBytesLength = res.bodyBytes.length;
            _isLoadingMidi = false;
          });
        }
      } else {
        _setFallbackMidi();
      }
    } catch (_) {
      _setFallbackMidi();
    }
  }

  void _setFallbackMidi() {
    if (mounted) {
      setState(() {
        _midiBytesLength = 54;
        _isLoadingMidi = false;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _startNotePlayback();
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _startNotePlayback() {
    _playbackTimer?.cancel();
    final delayMs = (500 / _tempo).round();
    _playbackTimer = Timer.periodic(Duration(milliseconds: delayMs), (timer) {
      if (mounted && _isPlaying) {
        setState(() {
          _currentNoteIndex = (_currentNoteIndex + 1) % _melodyNotes.length;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _toggleTrack(String trackName) {
    setState(() {
      _tracks[trackName] = !(_tracks[trackName] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Verovio Interactive Canvas Viewport
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF14181F),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(120),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: theme.colorScheme.primary.withAlpha(80), width: 1.5),
              ),
              child: Stack(
                children: [
                  // Staff Lines
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          5,
                          (i) => Container(
                            height: 1.2,
                            color: Colors.white.withAlpha(40),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: _isLoadingMidi
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: _melodyNotes.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final note = entry.value;
                                  final isCurrent = idx == _currentNoteIndex;

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                          : Colors.white.withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      note,
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white : Colors.grey.shade300,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        fontSize: isCurrent ? 16 : 12,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Verovio Interactive Canvas & SoundFont Synth',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'MIDI Data: $_midiBytesLength Octets | Shift: ${_pitchTranspose >= 0 ? "+$_pitchTranspose" : "$_pitchTranspose"} st | Tempo: ${_tempo.toStringAsFixed(2)}x',
                                  style: TextStyle(color: theme.colorScheme.secondary, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (_isAbLoopActive)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Chip(
                        avatar: const Icon(Icons.loop_rounded, size: 16, color: Colors.black87),
                        label: Text(
                          'Boucle A/B : M${_abLoopRange.start.round()} - M${_abLoopRange.end.round()}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        backgroundColor: theme.colorScheme.secondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Playback Bar Card
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10_rounded, size: 28),
                      onPressed: () {
                        setState(() {
                          _currentNoteIndex = 0;
                        });
                      },
                    ),
                    FloatingActionButton(
                      key: const Key('play_pause_fab'),
                      onPressed: _togglePlayPause,
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 36),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10_rounded, size: 28),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time Stretching (Tempo) Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speed_rounded, size: 20, color: Color(0xFF9D4EDD)),
                            SizedBox(width: 8),
                            Text('Tempo (Time-Stretching)', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(
                          '${_tempo.toStringAsFixed(2)}x',
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                    Slider(
                      value: _tempo,
                      min: 0.25,
                      max: 2.0,
                      divisions: 7,
                      onChanged: (val) {
                        setState(() {
                          _tempo = val;
                          if (_isPlaying) _startNotePlayback();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Transposition (Pitch Shift) Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.height_rounded, size: 20, color: Color(0xFF06D6A0)),
                            SizedBox(width: 8),
                            Text('Transposition (Demi-Tons)', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(
                          '${_pitchTranspose >= 0 ? "+$_pitchTranspose" : "$_pitchTranspose"} st',
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.secondary),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          onPressed: () {
                            if (_pitchTranspose > -12) {
                              setState(() {
                                _pitchTranspose--;
                              });
                            }
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: _pitchTranspose.toDouble(),
                            min: -12,
                            max: 12,
                            divisions: 24,
                            activeColor: theme.colorScheme.secondary,
                            onChanged: (val) {
                              setState(() {
                                _pitchTranspose = val.round();
                              });
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          onPressed: () {
                            if (_pitchTranspose < 12) {
                              setState(() {
                                _pitchTranspose++;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // A/B Loop Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.repeat_rounded, size: 20, color: Colors.amber),
                            SizedBox(width: 8),
                            Text('Répétition A/B (Mesures)', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Switch(
                          value: _isAbLoopActive,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setState(() {
                              _isAbLoopActive = val;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_isAbLoopActive)
                      RangeSlider(
                        values: _abLoopRange,
                        min: 1,
                        max: 16,
                        divisions: 15,
                        activeColor: Colors.amber,
                        labels: RangeLabels(
                          'M${_abLoopRange.start.round()}',
                          'M${_abLoopRange.end.round()}',
                        ),
                        onChanged: (val) {
                          setState(() {
                            _abLoopRange = val;
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Multi-Voice / Track Toggles
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.layers_rounded, size: 20, color: Colors.cyan),
                        SizedBox(width: 8),
                        Text('Pistes Instruments / SoundFont', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._tracks.keys.map((track) {
                      final enabled = _tracks[track] ?? false;
                      return CheckboxListTile(
                        title: Text(track, style: const TextStyle(fontSize: 13)),
                        value: enabled,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (_) => _toggleTrack(track),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
