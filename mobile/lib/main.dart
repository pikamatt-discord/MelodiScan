import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'capture_view.dart';
import 'player_view.dart';

void main() {
  runApp(const MelodiScanApp());
}

class MelodiScanApp extends StatefulWidget {
  const MelodiScanApp({super.key});

  @override
  State<MelodiScanApp> createState() => _MelodiScanAppState();
}

class _MelodiScanAppState extends State<MelodiScanApp> {
  Color _seedColor = const Color(0xFF00E676); // Neon Emerald Accent
  bool _isDarkMode = true; // Cyber Dark default

  void _changeSeedColor(Color color) {
    setState(() {
      _seedColor = color;
    });
  }

  void _toggleDarkMode(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MelodiScan',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
          surface: const Color(0xFF0F1118),
          surfaceContainer: const Color(0xFF161924),
          surfaceContainerHigh: const Color(0xFF1E2232),
          surfaceContainerHighest: const Color(0xFF262B3F),
        ),
        scaffoldBackgroundColor: const Color(0xFF08090E),
        useMaterial3: true,
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          color: const Color(0xFF161924),
          elevation: 6,
          shadowColor: Colors.black.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _seedColor.withOpacity(0.2), width: 1),
          ),
        ),
      ),
      home: HomeScreen(
        onColorChanged: _changeSeedColor,
        onDarkModeToggled: _toggleDarkMode,
        isDarkMode: _isDarkMode,
        selectedColor: _seedColor,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ApiService? apiService;
  final Function(Color)? onColorChanged;
  final Function(bool)? onDarkModeToggled;
  final bool isDarkMode;
  final Color selectedColor;

  const HomeScreen({
    super.key,
    this.apiService,
    this.onColorChanged,
    this.onDarkModeToggled,
    this.isDarkMode = true,
    this.selectedColor = const Color(0xFF00E676),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? _midiData;
  late final ApiService _apiService;

  final List<Color> _themeColors = [
    const Color(0xFF00E676), // Neon Emerald Green
    const Color(0xFF7C4DFF), // Electric Cyber Purple
    const Color(0xFF00B0FF), // Neon Cyan
    const Color(0xFFFF4081), // Neon Pink
    const Color(0xFFFFAB00), // Electric Amber
  ];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
  }

  void _handleScanSuccess(List<int> bytes) {
    setState(() {
      _midiData = Uint8List.fromList(bytes);
    });
  }

  void _resetToCapture() {
    setState(() {
      _midiData = null;
    });
  }

  void _showThemeSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            return AlertDialog(
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3)),
              ),
              title: Row(
                children: [
                  Icon(Icons.palette_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  const Text('Personnalisation Studio'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    activeColor: theme.colorScheme.primary,
                    title: const Text('Mode Sombre (Cyber Dark)'),
                    subtitle: const Text('Interface néon haute précision'),
                    value: widget.isDarkMode,
                    onChanged: (val) {
                      widget.onDarkModeToggled?.call(val);
                      setDialogState(() {});
                    },
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Couleur d\'Accent Neon :',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _themeColors.map((color) {
                      final isSelected = widget.selectedColor.value == color.value;
                      return GestureDetector(
                        onTap: () {
                          widget.onColorChanged?.call(color);
                          setDialogState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? color : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withOpacity(0.8),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                          child: CircleAvatar(
                            backgroundColor: color,
                            radius: 18,
                            child: isSelected
                                ? const Icon(Icons.check_rounded, color: Colors.black, size: 20)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.4),
                    blurRadius: 10,
                  )
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.black,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MelodiScan',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  'OMR Musical Studio',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            key: const Key('theme_settings_button'),
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Personnaliser l\'apparence',
            onPressed: _showThemeSettingsDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _midiData == null
              ? CaptureView(
                  key: const ValueKey('capture_view'),
                  apiService: _apiService,
                  onScanSuccess: _handleScanSuccess,
                )
              : PlayerView(
                  key: const ValueKey('player_view'),
                  midiData: _midiData!,
                  onReset: _resetToCapture,
                ),
        ),
      ),
    );
  }
}
