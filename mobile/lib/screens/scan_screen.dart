import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';
import '../widgets/melodiscan_background.dart';
import '../widgets/melodiscan_logo.dart';
import 'status_screen.dart';

class ScanScreen extends StatefulWidget {
  final http.Client? httpClient;
  final String profileId;
  final String profileName;
  final String initialServerUrl;
  final String initialApiKey;
  final Future<void> Function() onChangeProfile;
  final Future<void> Function(String serverUrl, String apiKey)?
      onConnectionChanged;

  const ScanScreen({
    super.key,
    this.httpClient,
    this.profileId = 'profile-1',
    this.profileName = 'Profil 1',
    this.initialServerUrl = const String.fromEnvironment(
      'MELODISCAN_API_URL',
      defaultValue: 'http://10.0.2.2:8080',
    ),
    this.initialApiKey = const String.fromEnvironment('MELODISCAN_API_KEY'),
    this.onChangeProfile = _noProfileChange,
    this.onConnectionChanged,
  });

  static Future<void> _noProfileChange() async {}

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isUploading = false;
  XFile? _selectedFile;
  String? _selectedFileName;
  bool _selectedFileIsPdf = false;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _serverUrlController =
      TextEditingController(text: widget.initialServerUrl);
  late final TextEditingController _apiKeyController =
      TextEditingController(text: widget.initialApiKey);

  @override
  void dispose() {
    _titleController.dispose();
    _serverUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source);
      if (mounted && image != null) {
        setState(() {
          _selectedFile = image;
          _selectedFileName = image.name;
          _selectedFileIsPdf = false;
        });
      }
    } catch (error) {
      _showError('Impossible de sélectionner l’image : $error');
    }
  }

  Future<void> _selectPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final pdf = result.files.single;
      final path = pdf.path;
      if (path == null) {
        _showError('Impossible d’accéder au fichier PDF sélectionné.');
        return;
      }

      setState(() {
        _selectedFile = XFile(path, name: pdf.name);
        _selectedFileName = pdf.name;
        _selectedFileIsPdf = true;
      });
    } catch (error) {
      _showError('Impossible de sélectionner le PDF : $error');
    }
  }

  Future<void> _uploadAndProcess() async {
    final file = _selectedFile;
    final fileName = _selectedFileName;
    if (file == null || fileName == null) {
      _showError('Sélectionnez une image ou un PDF avant de lancer le scan.');
      return;
    }

    final title = _titleController.text.trim();
    final serverUrl =
        _serverUrlController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final parsedServerUrl = Uri.tryParse(serverUrl);
    if (parsedServerUrl == null ||
        !parsedServerUrl.hasAuthority ||
        !{'http', 'https'}.contains(parsedServerUrl.scheme)) {
      _showError('Saisissez une URL de serveur HTTP ou HTTPS valide.');
      return;
    }

    final client = widget.httpClient ?? createApiClient();
    setState(() {
      _isUploading = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/v1/scan'),
      )..fields['title'] = title;
      final apiKey = _apiKeyController.text.trim();
      if (apiKey.isNotEmpty) {
        request.headers['X-API-Key'] = apiKey;
      }
      request.files.add(
        http.MultipartFile(
          'file',
          http.ByteStream(file.openRead()),
          await file.length(),
          filename: fileName,
        ),
      );
      request.fields['profile_id'] = widget.profileId;
      await widget.onConnectionChanged?.call(serverUrl, apiKey);

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode != 200) {
        _showError(_responseError(response));
        return;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['task_id'] is! String ||
          body['status'] != 'STATUS_QUEUED') {
        _showError(
            'Réponse invalide du serveur lors de la création de la tâche.');
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StatusScreen(
            taskId: body['task_id'] as String,
            title: title.isEmpty ? 'Analyse de la partition' : title,
            serverUrl: serverUrl,
            apiKey: apiKey,
            profileId: widget.profileId,
            httpClient: client,
          ),
        ),
      );
    } catch (error) {
      _showError('Échec de l’envoi au serveur : $error');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
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
    return 'Le serveur a refusé la demande (${response.statusCode}).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _selectedFile != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MelodiScanLogo(size: 28),
            const SizedBox(width: 10),
            Text('MelodiScan · ${widget.profileName}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Changer de profil',
            onPressed: widget.onChangeProfile,
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
      body: MelodiScanBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.22),
                      theme.colorScheme.surface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Votre partition, prête à écouter.',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Photographiez-la ou importez un PDF ou une image pour démarrer.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const _ScanSectionHeading(
                icon: Icons.library_music_rounded,
                title: 'Choisissez une partition',
                subtitle: 'Prenez une photo, ou importez une image ou un PDF.',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _selectImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Prendre en photo'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _selectImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text('Choisir une image'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _selectPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Importer un PDF'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (hasFile) ...[
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          theme.colorScheme.secondary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor:
                          theme.colorScheme.secondary.withValues(alpha: 0.16),
                      child: Icon(
                        _selectedFileIsPdf
                            ? Icons.picture_as_pdf_rounded
                            : Icons.image_rounded,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    title: Text(
                      _selectedFileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_selectedFileIsPdf
                        ? 'Document PDF complet'
                        : 'Image prête à être analysée'),
                    trailing: IconButton(
                      tooltip: 'Retirer le fichier',
                      onPressed: _isUploading
                          ? null
                          : () => setState(() {
                                _selectedFile = null;
                                _selectedFileName = null;
                                _selectedFileIsPdf = false;
                              }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isUploading || !hasFile ? null : _uploadAndProcess,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(
                    _isUploading ? 'Envoi en cours…' : 'Analyser la partition'),
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: Icon(
                      Icons.tune_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: const Text('Réglages avancés'),
                    subtitle:
                        const Text('Serveur, clé API et titre du morceau'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    children: [
                      TextField(
                        controller: _serverUrlController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'URL du serveur',
                          helperText:
                              'Sur un téléphone, utilisez l’adresse IP du serveur sur le réseau.',
                          prefixIcon: Icon(Icons.dns_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Clé API (si configurée sur le serveur)',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Titre (facultatif)',
                          helperText:
                              'Utilisé seulement si aucun titre n’est présent dans la partition.',
                          prefixIcon: Icon(Icons.music_note_rounded),
                        ),
                      ),
                    ],
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

class _ScanSectionHeading extends StatelessWidget {
  const _ScanSectionHeading({
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
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
