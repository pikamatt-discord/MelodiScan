import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  bool _isBinarized = false;
  bool _isPerspectiveCorrected = false;
  bool _isUploading = false;
  final TextEditingController _titleController = TextEditingController(text: 'Symphonie No. 5 (Beethoven)');
  final TextEditingController _serverUrlController = TextEditingController(text: 'http://localhost:8080');

  void _applyEdgeBinarization() {
    setState(() {
      _isBinarized = !_isBinarized;
    });
  }

  void _applyPerspectiveCorrection() {
    setState(() {
      _isPerspectiveCorrected = !_isPerspectiveCorrected;
    });
  }

  Future<void> _uploadAndProcess() async {
    final title = _titleController.text.trim();
    final serverUrl = _serverUrlController.text.trim();
    final client = widget.httpClient ?? http.Client();

    setState(() {
      _isUploading = true;
    });

    try {
      final uri = Uri.parse('$serverUrl/api/v1/scan');
      final request = http.MultipartRequest('POST', uri);
      request.fields['title'] = title.isEmpty ? 'Untitled Score' : title;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          filename: 'score.png',
        ),
      );

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final taskId = data['task_id'] as String;

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StatusScreen(
                taskId: taskId,
                title: title,
                serverUrl: serverUrl,
                httpClient: client,
              ),
            ),
          );
        }
      } else {
        _navigateToFallbackStatus(client, title, serverUrl);
      }
    } catch (_) {
      _navigateToFallbackStatus(client, title, serverUrl);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _navigateToFallbackStatus(http.Client client, String title, String serverUrl) {
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StatusScreen(
            taskId: taskId,
            title: title.isEmpty ? 'Untitled Score' : title,
            serverUrl: serverUrl,
            httpClient: client,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Banner with Logo
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const MelodiScanLogo(size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MelodiScan Enterprise',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Numérisation OMR & Synthèse Audio',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Server & Score inputs card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Serveur Domestique (URL)',
                        prefixIcon: Icon(Icons.dns_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Titre de la Partition',
                        prefixIcon: Icon(Icons.music_note_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live Camera/Sheet Canvas Edge Preview
            Container(
              height: 290,
              decoration: BoxDecoration(
                color: _isBinarized ? const Color(0xFFF8F9FA) : const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: _isPerspectiveCorrected ? theme.colorScheme.secondary : theme.colorScheme.primary.withAlpha(100),
                  width: _isPerspectiveCorrected ? 3.0 : 1.5,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          5,
                          (i) => Container(
                            height: 1.5,
                            color: _isBinarized ? Colors.black.withAlpha(200) : Colors.white.withAlpha(50),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isBinarized ? Icons.document_scanner : Icons.camera_alt_rounded,
                          size: 56,
                          color: _isBinarized ? Colors.black87 : theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isBinarized ? '1-Bit Sauvola Binarized PNG (< 500 KB)' : 'Aperçu Numérisation Edge OpenCV',
                          style: TextStyle(
                            color: _isBinarized ? Colors.black87 : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              avatar: Icon(
                                _isBinarized ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 16,
                                color: _isBinarized ? Colors.black87 : Colors.grey,
                              ),
                              label: Text(
                                _isBinarized ? 'Filtre Monochrome 1-bit' : 'Couleur / Brute',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isBinarized ? Colors.black87 : Colors.white70,
                                ),
                              ),
                              backgroundColor: _isBinarized ? Colors.grey.shade300 : Colors.black26,
                            ),
                            Chip(
                              avatar: Icon(
                                _isPerspectiveCorrected ? Icons.crop_rotate : Icons.crop_free,
                                size: 16,
                                color: _isPerspectiveCorrected ? theme.colorScheme.secondary : Colors.grey,
                              ),
                              label: Text(
                                _isPerspectiveCorrected ? 'Grille Hough Réglée' : 'Grille Standard',
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: Colors.black26,
                            ),
                          ],
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
                            Text(
                              'Envoi vers le conteneur Docker API...',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Edge Processing Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _applyEdgeBinarization,
                    icon: Icon(_isBinarized ? Icons.refresh_rounded : Icons.auto_awesome),
                    label: Text(_isBinarized ? 'Réinitialiser' : 'Binarisation Sauvola'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _applyPerspectiveCorrection,
                    icon: const Icon(Icons.grid_on_rounded),
                    label: Text(_isPerspectiveCorrected ? 'Grille Init' : 'Warp Quadrilatère'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: theme.colorScheme.secondary),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Submit Button
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withAlpha(200),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withAlpha(80),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isUploading ? null : _uploadAndProcess,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.rocket_launch_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      _isUploading ? 'Transfert en cours...' : 'Lancer le Pipeline OMR (Audiveris)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
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
