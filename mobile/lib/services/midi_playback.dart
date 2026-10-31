import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';

import 'general_midi_soundfont.dart';

abstract interface class MidiPlayback {
  bool get isSupported;

  Future<void> prepare(Uint8List midiBytes);
  Future<void> testNote({
    required int instrumentProgram,
    required int volumePercent,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(int tick);
  Future<MidiPlaybackPosition> getPosition();
  Future<void> dispose();
}

class MidiPlaybackPosition {
  const MidiPlaybackPosition({
    required this.currentTick,
    required this.totalTicks,
    required this.isPlaying,
    required this.isComplete,
  });

  final int currentTick;
  final int totalTicks;
  final bool isPlaying;
  final bool isComplete;
}

class FlutterMidiPlayback implements MidiPlayback {
  final MidiPro _midi = MidiPro();
  final GeneralMidiSoundfont _soundfont = GeneralMidiSoundfont();
  int? _soundfontId;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<void> prepare(Uint8List midiBytes) async {
    if (!isSupported) {
      throw UnsupportedError('La lecture MIDI est disponible sur Android.');
    }

    if (!_midi.isInitialized) {
      await _midi.init(sampleRate: 48000, bufferSize: 256, polyphony: 128);
    }

    try {
      if (_soundfontId == null) {
        final file = await _soundfont.getFile();
        _soundfontId = await _midi.loadSoundfontFile(filePath: file.path);
      }
      await _midi.loadMidiData(data: midiBytes, sfId: _soundfontId!);
    } catch (_) {
      if (_soundfontId == null && _midi.isInitialized) {
        await _midi.dispose();
      }
      rethrow;
    }
  }

  @override
  Future<void> testNote({
    required int instrumentProgram,
    required int volumePercent,
  }) async {
    final soundfontId = _soundfontId;
    if (!_midi.isInitialized || soundfontId == null) {
      throw StateError('Le moteur MIDI n’est pas préparé.');
    }

    await _midi.selectInstrument(
      sfId: soundfontId,
      channel: 0,
      bank: 0,
      program: instrumentProgram,
    );
    await _midi.controlChange(
      sfId: soundfontId,
      channel: 0,
      controller: 7,
      value: volumePercent.clamp(0, 100),
    );
    await _midi.playNote(channel: 0, key: 60, velocity: 110, sfId: soundfontId);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } finally {
      await _midi.stopNote(channel: 0, key: 60, sfId: soundfontId);
    }
  }

  @override
  Future<void> play() => _midi.playMidi();

  @override
  Future<void> pause() => _midi.pauseMidi();

  @override
  Future<void> stop() => _midi.stopMidi();

  @override
  Future<void> seek(int tick) => _midi.seekMidi(tick);

  @override
  Future<MidiPlaybackPosition> getPosition() async {
    final state = await _midi.getMidiPlayerState();
    return MidiPlaybackPosition(
      currentTick: state.currentTick,
      totalTicks: state.totalTicks,
      isPlaying: state.isPlaying,
      isComplete: state.status == MidiPlayerStatus.done,
    );
  }

  @override
  Future<void> dispose() async {
    if (_midi.isInitialized) {
      await _midi.dispose();
    }
    _soundfontId = null;
  }
}
