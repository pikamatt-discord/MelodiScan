import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class MidiNoteInfo {
  final int noteNumber; // Original MIDI note
  final String noteName;
  final double startTimeInBeats;
  final double durationInBeats;

  MidiNoteInfo({
    required this.noteNumber,
    required this.noteName,
    required this.startTimeInBeats,
    required this.durationInBeats,
  });

  String getTransposedNoteName(int semitones) {
    return getPitchName(noteNumber + semitones);
  }

  static String getPitchName(int number) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (number ~/ 12) - 1;
    final name = names[(number % 12 + 12) % 12];
    return '$name$octave';
  }
}

List<MidiNoteInfo> parseMidiNotes(Uint8List bytes) {
  final List<MidiNoteInfo> notes = [];
  try {
    if (bytes.length < 14 || String.fromCharCodes(bytes.sublist(0, 4)) != 'MThd') {
      return _fallbackNotes();
    }

    int division = (bytes[12] << 8) | bytes[13];
    if (division <= 0) division = 480;

    int pos = 14;
    while (pos < bytes.length - 8) {
      if (String.fromCharCodes(bytes.sublist(pos, pos + 4)) == 'MTrk') {
        final trackLen = (bytes[pos + 4] << 24) |
            (bytes[pos + 5] << 16) |
            (bytes[pos + 6] << 8) |
            bytes[pos + 7];
        pos += 8;
        final trackEnd = pos + trackLen;

        int currentTicks = 0;
        final Map<int, int> activeNotesStartTick = {};

        while (pos < trackEnd && pos < bytes.length) {
          int deltaTime = 0;
          while (pos < bytes.length) {
            final byte = bytes[pos++];
            deltaTime = (deltaTime << 7) | (byte & 0x7F);
            if ((byte & 0x80) == 0) break;
          }
          currentTicks += deltaTime;

          if (pos >= bytes.length) break;
          final statusByte = bytes[pos];

          if (statusByte == 0xFF) {
            pos++;
            if (pos < bytes.length) {
              pos++;
              int len = 0;
              while (pos < bytes.length) {
                final b = bytes[pos++];
                len = (len << 7) | (b & 0x7F);
                if ((b & 0x80) == 0) break;
              }
              pos += len;
            }
          } else if ((statusByte & 0xF0) == 0x90) {
            pos++;
            if (pos + 1 < bytes.length) {
              final note = bytes[pos++];
              final velocity = bytes[pos++];
              if (velocity > 0) {
                activeNotesStartTick[note] = currentTicks;
              } else {
                if (activeNotesStartTick.containsKey(note)) {
                  final startTick = activeNotesStartTick.remove(note)!;
                  final durTicks = currentTicks - startTick;
                  notes.add(MidiNoteInfo(
                    noteNumber: note,
                    noteName: MidiNoteInfo.getPitchName(note),
                    startTimeInBeats: startTick / division,
                    durationInBeats: durTicks / division,
                  ));
                }
              }
            }
          } else if ((statusByte & 0xF0) == 0x80) {
            pos++;
            if (pos + 1 < bytes.length) {
              final note = bytes[pos++];
              pos++;
              if (activeNotesStartTick.containsKey(note)) {
                final startTick = activeNotesStartTick.remove(note)!;
                final durTicks = currentTicks - startTick;
                notes.add(MidiNoteInfo(
                  noteNumber: note,
                  noteName: MidiNoteInfo.getPitchName(note),
                  startTimeInBeats: startTick / division,
                  durationInBeats: durTicks / division,
                ));
              }
            }
          } else {
            pos++;
          }
        }
      } else {
        pos++;
      }
    }
  } catch (e) {
    return _fallbackNotes();
  }

  notes.sort((a, b) => a.startTimeInBeats.compareTo(b.startTimeInBeats));
  return notes.isEmpty ? _fallbackNotes() : notes;
}

List<MidiNoteInfo> _fallbackNotes() {
  const pitches = [60, 62, 64, 65, 67, 69, 71, 72];
  return List.generate(
    pitches.length,
    (i) => MidiNoteInfo(
      noteNumber: pitches[i],
      noteName: MidiNoteInfo.getPitchName(pitches[i]),
      startTimeInBeats: i.toDouble(),
      durationInBeats: 1.0,
    ),
  );
}

class PlayerView extends StatefulWidget {
  final Uint8List midiData;
  final VoidCallback onReset;

  const PlayerView({
    super.key,
    required this.midiData,
    required this.onReset,
  });

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> with TickerProviderStateMixin {
  late List<MidiNoteInfo> _notes;
  bool _isPlaying = false;
  double _tempoMultiplier = 1.0; // 0.5 to 1.5
  int _transpositionSemitones = 0; // -6 to +6
  double _currentBeat = 0.0;
  double _totalBeats = 8.0;
  String _selectedInstrument = 'Xylophone / Piano';
  int _visualizationMode = 0; // 0: Scrolling Recomposed Score Staff, 1: Falling Notes Xylophone

  Timer? _playbackTimer;
  late AnimationController _pulseController;
  late AnimationController _metronomeController;

  final List<String> _instruments = [
    'Xylophone / Piano',
    'Flûte à bec',
    'Saxophone',
    'Clavecin / Synth',
  ];

  final List<Color> _xylophoneBarColors = [
    Colors.redAccent,
    Colors.orangeAccent,
    Colors.amberAccent,
    Colors.greenAccent,
    Colors.tealAccent,
    Colors.lightBlueAccent,
    Colors.indigoAccent,
    Colors.purpleAccent,
  ];

  @override
  void initState() {
    super.initState();
    _notes = parseMidiNotes(widget.midiData);
    if (_notes.isNotEmpty) {
      final lastNote = _notes.last;
      _totalBeats = lastNote.startTimeInBeats + lastNote.durationInBeats;
    }
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);

    _metronomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _pulseController.dispose();
    _metronomeController.dispose();
    super.dispose();
  }

  void _play() {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
    });

    const intervalMs = 50;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      setState(() {
        final beatsPerTick = (2.0 * _tempoMultiplier) * (intervalMs / 1000.0);
        _currentBeat += beatsPerTick;

        if (_currentBeat.toInt() != (_currentBeat - beatsPerTick).toInt()) {
          _metronomeController.forward(from: 0.0);
        }

        if (_currentBeat >= _totalBeats) {
          _currentBeat = _totalBeats;
          _isPlaying = false;
          _playbackTimer?.cancel();
        }
      });
    });
  }

  void _pause() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _stop() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _currentBeat = 0.0;
    });
  }

  MidiNoteInfo? _getCurrentlyPlayingNote() {
    for (final note in _notes) {
      if (_currentBeat >= note.startTimeInBeats &&
          _currentBeat < (note.startTimeInBeats + note.durationInBeats)) {
        return note;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentNote = _getCurrentlyPlayingNote();
    final progress = _totalBeats > 0 ? (_currentBeat / _totalBeats).clamp(0.0, 1.0) : 0.0;
    final currentBpm = (120 * _tempoMultiplier).toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Studio Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                key: const Key('back_to_scan_button'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onReset,
                tooltip: "Scanner une autre partition",
              ),
              Column(
                children: [
                  Text(
                    'Lecteur OMR Interactif',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Score Audio Synth',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.music_note_rounded, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${_notes.length} notes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // View Mode Selector Segmented Button
          SegmentedButton<int>(
            key: const Key('view_mode_segmented_button'),
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Partition Recomposée'),
                icon: Icon(Icons.menu_book_rounded),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Mode Xylophone'),
                icon: Icon(Icons.waterfall_chart_rounded),
              ),
            ],
            selected: {_visualizationMode},
            onSelectionChanged: (Set<int> newSelection) {
              setState(() {
                _visualizationMode = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 14),

          // Active Mode High-Detail Canvas Viewport
          if (_visualizationMode == 0) ...[
            // Mode 1: Scrolling Recomposed Score Staff Canvas
            Container(
              height: 230,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 20,
                  )
                ],
              ),
              child: Stack(
                children: [
                  // 5 Detailed Staff Lines
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        5,
                        (index) => Container(
                          height: 2,
                          color: theme.colorScheme.onSurface.withOpacity(0.25),
                        ),
                      ),
                    ),
                  ),

                  // Treble Clef Graphic Badge
                  Positioned(
                    left: 8,
                    top: 24,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.6)),
                      ),
                      child: const Icon(
                        Icons.music_note_rounded,
                        size: 40,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),

                  // Horizontal Scrolling Recomposed Score
                  Positioned.fill(
                    left: 68,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final cursorX = totalWidth * progress;

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Score Notes Mapped on Staff
                            ..._notes.map((note) {
                              final noteProgress = _totalBeats > 0 ? (note.startTimeInBeats / _totalBeats) : 0.0;
                              final noteX = totalWidth * noteProgress;
                              final isCurrent = currentNote == note;

                              final minNote = 60; // C4
                              final maxNote = 72; // C5
                              final clampedNote = note.noteNumber.clamp(minNote, maxNote);
                              final relPitch = (clampedNote - minNote) / (maxNote - minNote);
                              final noteY = 160 - (relPitch * 120);

                              final noteName = note.getTransposedNoteName(_transpositionSemitones);

                              return Positioned(
                                left: noteX,
                                top: noteY,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Vertical Note Stem Line
                                    Positioned(
                                      left: 14,
                                      bottom: 12,
                                      child: Container(
                                        width: 2,
                                        height: 24,
                                        color: isCurrent ? Colors.cyanAccent : theme.colorScheme.primary,
                                      ),
                                    ),
                                    // Notehead Oval
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isCurrent ? Colors.cyanAccent : theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: isCurrent
                                            ? [
                                                BoxShadow(
                                                  color: Colors.cyanAccent.withOpacity(0.9),
                                                  blurRadius: 14,
                                                  spreadRadius: 3,
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: Text(
                                        noteName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            // Moving Blue Playhead Bar Illuminating Active Notes
                            Positioned(
                              left: cursorX,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 4,
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blueAccent.withOpacity(0.9),
                                      blurRadius: 14,
                                      spreadRadius: 3,
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Mode 2: Falling Notes Xylophone Mode Viewport
            Container(
              height: 230,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF090A10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    blurRadius: 16,
                  )
                ],
              ),
              child: Column(
                children: [
                  // Falling Tiles Waterfall Canvas
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final h = constraints.maxHeight;
                          final w = constraints.maxWidth;

                          const keyNotes = [60, 62, 64, 65, 67, 69, 71, 72];
                          final keyWidth = w / keyNotes.length;

                          return Stack(
                            children: [
                              // Target Key Baseline Neon Indicator
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    boxShadow: [
                                      BoxShadow(
                                        color: theme.colorScheme.primary,
                                        blurRadius: 8,
                                      )
                                    ],
                                  ),
                                ),
                              ),

                              // Render Falling Note Blocks
                              ..._notes.map((note) {
                                final timeDiff = note.startTimeInBeats - _currentBeat;
                                if (timeDiff < -0.5 || timeDiff > 2.5) {
                                  return const SizedBox.shrink();
                                }

                                final keyIndex = keyNotes.indexOf(note.noteNumber);
                                final colIdx = keyIndex != -1 ? keyIndex : (note.noteNumber % keyNotes.length);
                                final noteLeft = colIdx * keyWidth + 3;

                                final relTime = (timeDiff / 2.5).clamp(0.0, 1.0);
                                final topY = (1.0 - relTime) * (h - 30);
                                final isCurrent = currentNote == note;
                                final keyColor = _xylophoneBarColors[colIdx % _xylophoneBarColors.length];

                                return Positioned(
                                  left: noteLeft,
                                  top: topY,
                                  width: keyWidth - 6,
                                  height: 28,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isCurrent ? Colors.white : keyColor,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isCurrent ? Colors.white : keyColor.withOpacity(0.6),
                                          blurRadius: isCurrent ? 12 : 6,
                                        )
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        note.getTransposedNoteName(_transpositionSemitones),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Multicolor Xylophone Bars Baseline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(8, (index) {
                      const keyNotes = [60, 62, 64, 65, 67, 69, 71, 72];
                      final pitch = keyNotes[index];
                      final name = MidiNoteInfo.getPitchName(pitch + _transpositionSemitones);
                      final isHit = currentNote != null && (currentNote.noteNumber == pitch);
                      final barColor = _xylophoneBarColors[index % _xylophoneBarColors.length];

                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          height: 38,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isHit
                                  ? [Colors.white, barColor]
                                  : [barColor.withOpacity(0.8), barColor.withOpacity(0.4)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isHit ? Colors.white : barColor,
                              width: isHit ? 2 : 1,
                            ),
                            boxShadow: isHit
                                ? [
                                    BoxShadow(
                                      color: barColor.withOpacity(0.9),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isHit ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Seeking Progress Slider Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progression (${(progress * 100).toInt()}%)',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${_currentBeat.toStringAsFixed(1)} / ${_totalBeats.toStringAsFixed(1)} temps',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('seeking_slider'),
                    value: _currentBeat.clamp(0.0, _totalBeats),
                    min: 0.0,
                    max: _totalBeats > 0 ? _totalBeats : 1.0,
                    onChanged: (val) {
                      setState(() {
                        _currentBeat = val;
                      });
                    },
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('timeline_progress'),
                      value: progress,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.surfaceContainer,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Studio Playback Controls & Metronome Pulse Light
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const Key('stop_button'),
                iconSize: 32,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.15),
                  foregroundColor: Colors.redAccent,
                ),
                icon: const Icon(Icons.stop_rounded),
                onPressed: _stop,
                tooltip: 'Stop',
              ),
              const SizedBox(width: 20),
              IconButton.filled(
                key: const Key('play_pause_button'),
                iconSize: 56,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  elevation: 8,
                  shadowColor: theme.colorScheme.primary.withOpacity(0.5),
                ),
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: _isPlaying ? _pause : _play,
                tooltip: _isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 20),
              // Pulsing Metronome Beat Light
              AnimatedBuilder(
                animation: _metronomeController,
                builder: (context, child) {
                  return Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _metronomeController.isAnimating
                          ? Colors.cyanAccent
                          : theme.colorScheme.surfaceContainerHigh,
                      boxShadow: _metronomeController.isAnimating
                          ? [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: const Icon(Icons.timer_rounded, size: 14, color: Colors.black),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // SoundFont / Instrument & Audio Adjustments Studio Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Synthétiseur Audio Local (.sf2)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Instrument selector dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedInstrument,
                    decoration: InputDecoration(
                      labelText: 'SoundFont / Instrument',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.piano_rounded),
                    ),
                    items: _instruments.map((inst) {
                      return DropdownMenuItem(value: inst, child: Text(inst));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedInstrument = val;
                        });
                      }
                    },
                  ),
                  const Divider(height: 24),
                  // Tempo Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tempo (Vitesse) :'),
                      Text(
                        '${(_tempoMultiplier * 100).toInt()}% ($currentBpm BPM)',
                        key: const Key('tempo_value_text'),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('tempo_slider'),
                    value: _tempoMultiplier,
                    min: 0.5,
                    max: 1.5,
                    divisions: 10,
                    label: '${(_tempoMultiplier * 100).toInt()}%',
                    onChanged: (val) {
                      setState(() {
                        _tempoMultiplier = val;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  // Transposition Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Transposition (Hauteur) :'),
                      Text(
                        _transpositionSemitones == 0
                            ? 'Original'
                            : '${_transpositionSemitones > 0 ? "+$_transpositionSemitones" : _transpositionSemitones} demis-tons',
                        key: const Key('transposition_value_text'),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('transposition_slider'),
                    value: _transpositionSemitones.toDouble(),
                    min: -6,
                    max: 6,
                    divisions: 12,
                    label: '$_transpositionSemitones',
                    onChanged: (val) {
                      setState(() {
                        _transpositionSemitones = val.round();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Active Note Stats Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Note Actuelle', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        currentNote != null ? currentNote.getTransposedNoteName(_transpositionSemitones) : '--',
                        key: const Key('active_note_text'),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Total Notes', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${_notes.length}',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
