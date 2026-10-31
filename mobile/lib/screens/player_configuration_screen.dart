import 'package:flutter/material.dart';

import '../services/midi_configuration.dart';

class PlayerConfigurationScreen extends StatefulWidget {
  const PlayerConfigurationScreen({
    required this.initialConfiguration,
    required this.onSave,
    super.key,
  });

  final MidiPlayerConfiguration initialConfiguration;
  final Future<void> Function(MidiPlayerConfiguration configuration) onSave;

  @override
  State<PlayerConfigurationScreen> createState() =>
      _PlayerConfigurationScreenState();
}

class _PlayerConfigurationScreenState extends State<PlayerConfigurationScreen> {
  late int _instrumentProgram = widget.initialConfiguration.instrumentProgram;
  late double _tempo = widget.initialConfiguration.tempoBpm.toDouble();
  late double _volume = widget.initialConfiguration.volumePercent.toDouble();
  bool _isSaving = false;

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await widget.onSave(MidiPlayerConfiguration(
      instrumentProgram: _instrumentProgram,
      tempoBpm: _tempo.round(),
      volumePercent: _volume.round(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration du lecteur')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Adaptez le son et le rythme avant de lancer la lecture.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('INSTRUMENT', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('instrument_selector'),
              initialValue: _instrumentProgram,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.piano),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final option in GeneralMidiInstrument.all)
                  DropdownMenuItem(
                    value: option.program,
                    child: Text(
                      '${option.program + 1}. ${option.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _isSaving
                  ? null
                  : (program) {
                      if (program != null) {
                        setState(() => _instrumentProgram = program);
                      }
                    },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Le canal de percussion conserve son timbre d’origine.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Icon(Icons.speed),
                const SizedBox(width: 10),
                const Expanded(child: Text('Tempo')),
                Text(
                  '${_tempo.round()} BPM',
                  key: const Key('tempo_value'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              key: const Key('tempo_slider'),
              min: 40,
              max: 240,
              divisions: 200,
              value: _tempo.clamp(40, 240),
              label: '${_tempo.round()} BPM',
              onChanged:
                  _isSaving ? null : (value) => setState(() => _tempo = value),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('40 BPM', style: TextStyle(color: Colors.white54)),
                Text('240 BPM', style: TextStyle(color: Colors.white54)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                const SizedBox(width: 10),
                const Expanded(child: Text('Volume')),
                Text(
                  '${_volume.round()} %',
                  key: const Key('volume_value'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Slider(
              key: const Key('volume_slider'),
              min: 0,
              max: 100,
              divisions: 100,
              value: _volume,
              label: '${_volume.round()} %',
              onChanged:
                  _isSaving ? null : (value) => setState(() => _volume = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('save_player_configuration'),
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSaving ? 'Application…' : 'Appliquer'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
