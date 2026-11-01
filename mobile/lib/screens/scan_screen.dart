import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';
import '../widgets/melodiscan_logo.dart';
import '../widgets/melodiscan_background.dart';
import 'status_screen.dart';

class ScanScreen extends StatefulWidget {
  final http.Client? httpClient;

  const ScanScreen({
    super.key,
    this.httpClient,
  });

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
  final TextEditingController _serverUrlController = TextEditingController(
    text: const String.fromEnvironment(
      'MELODISCAN_API_URL',
      defaultValue: 'http://10.0.2.2:8080',
    ),
  );
  final TextEditingController _apiKeyController = TextEditingController(
    text: const String.fromEnvironment('MELODISCAN_API_KEY'),
  );

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
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MelodiScanLogo(size: 28),
            SizedBox(width: 10),
            Text('MelodiScan Scanner'),
          ],
        ),
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
                child: Row(
                  children: [
                    const MelodiScanLogo(size: 54),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Donnez vie à vos partitions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Importez un document et transformez-le en musique.',
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
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                height: hasFile ? 200 : 218,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasFile
                        ? theme.colorScheme.secondary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            5,
                            (_) => Container(
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.11),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          key: ValueKey(hasFile),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                hasFile
                                    ? _selectedFileIsPdf
                                        ? Icons.picture_as_pdf_rounded
                                        : Icons.document_scanner_rounded
                                    : Icons.photo_size_select_actual_rounded,
                                size: 30,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              hasFile
                                  ? _selectedFileIsPdf
                                      ? 'PDF prêt à être envoyé'
                                      : 'Image prête à être envoyée'
                                  : 'Aucun fichier sélectionné',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'La reconnaissance et la conversion sont effectuées par le serveur.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isUploading)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Envoi du document au serveur...',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isUploading || !hasFile ? null : _uploadAndProcess,
                icon: const Icon(Icons.rocket_launch_rounded),
                label: Text(_isUploading
                    ? 'Transfert en cours...'
                    : 'Lancer la reconnaissance OMR'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 18),
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
