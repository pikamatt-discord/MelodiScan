import 'package:flutter/material.dart';

import '../services/midi_configuration.dart';

class PlayerConfigurationScreen extends StatefulWidget {
  const PlayerConfigurationScreen({
    required this.initialConfiguration,
    required this.onSave,
    required this.onTestAudio,
    super.key,
  });

  final MidiPlayerConfiguration initialConfiguration;
  final Future<void> Function(MidiPlayerConfiguration configuration) onSave;
  final Future<void> Function(MidiPlayerConfiguration configuration)
      onTestAudio;

  @override
  State<PlayerConfigurationScreen> createState() =>
      _PlayerConfigurationScreenState();
}

class _PlayerConfigurationScreenState extends State<PlayerConfigurationScreen> {
  late int _instrumentProgram = widget.initialConfiguration.instrumentProgram;
  late double _tempo = widget.initialConfiguration.tempoBpm.toDouble();
  late double _volume = widget.initialConfiguration.volumePercent.toDouble();
  late bool _followScoreInstrument =
      widget.initialConfiguration.followScoreInstrument;
  late bool _followScoreTempo = widget.initialConfiguration.followScoreTempo;
  bool _isSaving = false;
  bool _isTestingAudio = false;
  String? _testAudioError;
  String? _saveError;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(MidiPlayerConfiguration(
        instrumentProgram: _instrumentProgram,
        tempoBpm: _tempo.round(),
        volumePercent: _volume.round(),
        followScoreInstrument: _followScoreInstrument,
        followScoreTempo: _followScoreTempo,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testAudio() async {
    setState(() {
      _isTestingAudio = true;
      _testAudioError = null;
    });
    try {
      await widget.onTestAudio(MidiPlayerConfiguration(
        instrumentProgram: _instrumentProgram,
        tempoBpm: _tempo.round(),
        volumePercent: _volume.round(),
        followScoreInstrument: _followScoreInstrument,
        followScoreTempo: _followScoreTempo,
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _testAudioError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _isTestingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration du lecteur')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.2),
                      theme.colorScheme.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.tune_rounded,
                          color: theme.colorScheme.primary, size: 25),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Votre son, à votre façon',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ajustez le timbre et le rythme de lecture.',
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
              ),
            ),
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ConfigurationHeading(
                      icon: Icons.piano_rounded,
                      title: 'Instrument',
                      subtitle: 'Choisissez le timbre principal.',
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      key: const Key('instrument_selector'),
                      initialValue: _instrumentProgram,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.graphic_eq_rounded),
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
                      onChanged: _isSaving || _followScoreInstrument
                          ? null
                          : (program) {
                              if (program != null) {
                                setState(() => _instrumentProgram = program);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      key: const Key('follow_score_instrument'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Suivre les instruments de la partition'),
                      subtitle: Text(
                        _followScoreInstrument
                            ? 'Les changements notés sont conservés.'
                            : 'Un instrument unique remplacera les indications.',
                      ),
                      value: _followScoreInstrument,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(
                                () => _followScoreInstrument = value,
                              ),
                    ),
                    Text(
                      'Sans indication explicite, le son reste neutre. '
                      'Les percussions gardent leur canal dédié.',
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: _ConfigurationHeading(
                            icon: Icons.speed_rounded,
                            title: 'Tempo',
                            subtitle: 'Vitesse de lecture personnalisée.',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_tempo.round()} BPM',
                            key: const Key('tempo_value'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
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
                      onChanged: _isSaving || _followScoreTempo
                          ? null
                          : (value) => setState(() => _tempo = value),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('40 BPM', style: TextStyle(color: Colors.white54)),
                        Text('240 BPM',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                    SwitchListTile(
                      key: const Key('follow_score_tempo'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Suivre les changements de tempo'),
                      subtitle: Text(
                        _followScoreTempo
                            ? 'Le rythme varie selon la partition.'
                            : 'Le tempo choisi conserve les variations relatives.',
                      ),
                      value: _followScoreTempo,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _followScoreTempo = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: _ConfigurationHeading(
                            icon: Icons.volume_up_rounded,
                            title: 'Volume',
                            subtitle: 'Niveau sonore de la partition.',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_volume.round()} %',
                            key: const Key('volume_value'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
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
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _volume = value),
                    ),
                  ],
                ),
              ),
            ),
            if (_testAudioError != null) ...[
              const SizedBox(height: 12),
              Text(
                'Échec du test audio : $_testAudioError',
                key: const Key('test_audio_error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              Text(
                'Échec de l’enregistrement : $_saveError',
                key: const Key('save_player_configuration_error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('test_audio_button'),
                  onPressed: _isTestingAudio || _isSaving ? null : _testAudio,
                  icon: _isTestingAudio
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.volume_up_rounded),
                  label: Text(_isTestingAudio ? 'Test…' : 'Tester le son'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('save_player_configuration'),
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_isSaving ? 'Application…' : 'Appliquer'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigurationHeading extends StatelessWidget {
  const _ConfigurationHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
