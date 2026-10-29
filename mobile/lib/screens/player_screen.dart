import 'package:flutter/material.dart';

class PlayerScreen extends StatefulWidget {
  final String taskId;
  final String title;

  const PlayerScreen({
    super.key,
    required this.taskId,
    required this.title,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _isPlaying = false;
  double _tempo = 1.0;
  int _pitchTranspose = 0;
  bool _isAbLoopActive = false;
  RangeValues _abLoopRange = const RangeValues(1, 4);

  final Map<String, bool> _tracks = {
    'Flûte / Voix Principal (SoundFont sf2)': true,
    'Piano Accompagnement (FluidSynth)': true,
    'Basse & Contrebasse': true,
  };

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(40),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Verovio Score Viewport (Canvas Vectoriel)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
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
                            'Transposition : ${_pitchTranspose >= 0 ? "+$_pitchTranspose" : "$_pitchTranspose"} st | Tempo : ${_tempo.toStringAsFixed(2)}x',
                            style: TextStyle(color: theme.colorScheme.secondary, fontSize: 12),
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
                          'Boucle A/B : Mesures ${_abLoopRange.start.round()} à ${_abLoopRange.end.round()}',
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
                      onPressed: () {},
                    ),
                    FloatingActionButton(
                      key: const Key('play_pause_fab'),
                      onPressed: _togglePlayPause,
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.black,
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
