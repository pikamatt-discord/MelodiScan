import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';
import '../widgets/melodiscan_logo.dart';
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
  final TextEditingController _titleController =
      TextEditingController(text: 'Ma Partition Numérisée');
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
      )..fields['title'] = title.isEmpty ? 'Untitled Score' : title;
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
            title: title.isEmpty ? 'Untitled Score' : title,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const MelodiScanLogo(size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MelodiScan',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reconnaissance OMR d’une image ou d’un PDF',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
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
                        labelText: 'Titre de la partition',
                        prefixIcon: Icon(Icons.music_note_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading
                        ? null
                        : () => _selectImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Prendre en photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading
                        ? null
                        : () => _selectImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Choisir une image'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: Colors.black,
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
              ),
            ),
            if (hasFile) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(_selectedFileIsPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded),
                  title: Text(_selectedFileName!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_selectedFileIsPdf
                      ? 'Document PDF complet'
                      : 'Une image par traitement'),
                  trailing: IconButton(
                    tooltip: 'Retirer le fichier',
                    onPressed: _isUploading
                        ? null
                        : () => setState(() {
                              _selectedFile = null;
                              _selectedFileName = null;
                              _selectedFileIsPdf = false;
                            }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              height: 230,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: theme.colorScheme.primary.withAlpha(100)),
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
                              height: 1.5, color: Colors.white.withAlpha(50)),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasFile
                              ? _selectedFileIsPdf
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.document_scanner
                              : Icons.photo_size_select_actual_rounded,
                          size: 52,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasFile
                              ? _selectedFileIsPdf
                                  ? 'PDF prêt à être envoyé'
                                  : 'Image prête à être envoyée'
                              : 'Aucun fichier sélectionné',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'La reconnaissance et la conversion sont effectuées par le serveur.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isUploading)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
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
          ],
        ),
      ),
    );
  }
}
