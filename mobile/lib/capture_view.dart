import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

class CaptureView extends StatefulWidget {
  final ApiService apiService;
  final Function(List<int> midiData) onScanSuccess;

  const CaptureView({
    super.key,
    required this.apiService,
    required this.onScanSuccess,
  });

  @override
  State<CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<CaptureView> with SingleTickerProviderStateMixin {
  final TextEditingController _ipController =
      TextEditingController(text: "10.0.2.2:8000");
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  bool _isTestingConnection = false;
  bool? _isServerConnected;
  int? _pingLatencyMs;
  String? _errorMessage;
  File? _selectedImage;

  late AnimationController _scanLineController;

  final List<String> _ipPresets = [
    "10.0.2.2:8000",
    "192.168.1.50:8000",
    "localhost:8000",
  ];

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingConnection = true;
      _isServerConnected = null;
      _pingLatencyMs = null;
    });

    final stopwatch = Stopwatch()..start();
    final isConnected =
        await widget.apiService.checkConnection(_ipController.text);
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _isTestingConnection = false;
        _isServerConnected = isConnected;
        _pingLatencyMs = isConnected ? stopwatch.elapsedMilliseconds : null;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final XFile? photo = await _picker.pickImage(source: source);
      if (photo == null) return;

      setState(() {
        _selectedImage = File(photo.path);
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Impossible d'accéder à l'appareil photo/galerie.";
      });
    }
  }

  Future<void> _startScanning() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService
          .scanPartition(_selectedImage!, _ipController.text);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (result.isSuccess && result.midiData != null) {
        widget.onScanSuccess(result.midiData!);
      } else {
        setState(() {
          _errorMessage = result.errorMessage ??
              "Impossible de lire la partition. Veuillez reprendre la photo avec une meilleure luminosité.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            "Impossible de lire la partition. Veuillez reprendre la photo avec une meilleure luminosité.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cyber Hero Card
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.25),
                  theme.colorScheme.surfaceContainerHigh,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                    ),
                    child: Icon(
                      Icons.camera_enhance_rounded,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Numérisation OMR IA',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Capturez une mélodie monophonique (flûte, xylophone, chant)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Server Network Configuration Card with Latency Ping
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_rounded, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Serveur Ubuntu Local',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_isTestingConnection)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_isServerConnected != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isServerConnected!
                                ? Colors.green.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isServerConnected! ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isServerConnected! ? Icons.check_circle : Icons.error,
                                size: 14,
                                color: _isServerConnected! ? Colors.greenAccent : Colors.redAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isServerConnected!
                                    ? 'En ligne (${_pingLatencyMs ?? 12}ms)'
                                    : 'Inaccessible',
                                style: TextStyle(
                                  color: _isServerConnected! ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('ip_input_field'),
                          controller: _ipController,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Adresse IP:Port',
                            hintText: 'ex: 192.168.1.50:8000',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.lan_rounded, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('test_connection_button'),
                        onPressed: _testConnection,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Tester la connexion',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _ipPresets.map((preset) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            label: Text(preset, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              setState(() {
                                _ipController.text = preset;
                                _isServerConnected = null;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Scan Actions & Optical Scanner Animation Viewport
          if (_isLoading) ...[
            Container(
              height: 240,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                  )
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated Scanning Line Effect
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanLineController.value * 180,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary,
                                blurRadius: 12,
                                spreadRadius: 3,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Analyse OMR IA en cours...',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Analyse des portées et conversion MusicXML -> MIDI',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            if (_selectedImage != null) ...[
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.25),
                      blurRadius: 16,
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(
                            _selectedImage!,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xCC000000),
                              ),
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () {
                                setState(() {
                                  _selectedImage = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      Container(
                        color: theme.colorScheme.surfaceContainerHigh,
                        padding: const EdgeInsets.all(12.0),
                        child: ElevatedButton.icon(
                          key: const Key('start_scan_selected_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                          ),
                          onPressed: _startScanning,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text(
                            'LANCER L\'ANALYSE OMR',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      key: const Key('scan_button'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text(
                        'Prendre Photo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('gallery_button'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                      ),
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: const Text(
                        'Choisir Galerie',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              key: const Key('error_message_card'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          // Tips Expander
          ExpansionTile(
            key: const Key('photo_tips_expander'),
            leading: Icon(Icons.lightbulb_rounded, color: theme.colorScheme.primary),
            title: const Text('Conseils pour une numérisation réussie'),
            children: const [
              ListTile(
                dense: true,
                leading: Icon(Icons.brightness_high_rounded, size: 20),
                title: Text('Bonne luminosité uniforme sans ombres portées.'),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.crop_square_rounded, size: 20),
                title: Text('Partition monophonique bien à plat et cadrée.'),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.music_note_rounded, size: 20),
                title: Text('Lignes de portée et notes bien nettes.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
