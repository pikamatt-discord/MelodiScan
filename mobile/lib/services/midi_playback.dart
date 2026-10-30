import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';

abstract interface class MidiPlayback {
  bool get isSupported;

  Future<void> prepare(Uint8List midiBytes);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
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
  static const _soundfontPath = 'assets/soundfonts/VintageDreamsWaves-v2.sf2';

  final MidiPro _midi = MidiPro();
  int? _soundfontId;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<void> prepare(Uint8List midiBytes) async {
    if (!isSupported) {
      throw UnsupportedError('La lecture MIDI est disponible sur Android.');
    }

    if (!_midi.isInitialized) {
      await _midi.init();
    }

    try {
      _soundfontId ??= await _midi.loadSoundfontAsset(
        assetPath: _soundfontPath,
        bank: 0,
        program: 0,
      );
      await _midi.loadMidiData(data: midiBytes, sfId: _soundfontId!);
    } catch (_) {
      if (_soundfontId == null && _midi.isInitialized) {
        await _midi.dispose();
      }
      rethrow;
    }
  }

  @override
  Future<void> play() => _midi.playMidi();

  @override
  Future<void> pause() => _midi.pauseMidi();

  @override
  Future<void> stop() => _midi.stopMidi();

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
