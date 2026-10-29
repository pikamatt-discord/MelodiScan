import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/scan_screen.dart';

void main() {
  runApp(const ProviderScope(child: MelodiScanApp()));
}

class MelodiScanApp extends StatelessWidget {
  const MelodiScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryAccent = Color(0xFF9D4EDD);
    const secondaryAccent = Color(0xFF06D6A0);
    const darkBackground = Color(0xFF0D0F12);
    const surfaceColor = Color(0xFF161A20);
    const surfaceElevated = Color(0xFF202630);

    return MaterialApp(
      title: 'MelodiScan Enterprise',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: primaryAccent,
        scaffoldBackgroundColor: darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: primaryAccent,
          secondary: secondaryAccent,
          surface: surfaceColor,
          background: darkBackground,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 4,
          shadowColor: Colors.black.withAlpha(120),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withAlpha(15), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12151B),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceElevated,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryAccent, width: 2),
          ),
          labelStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          prefixIconColor: primaryAccent,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: primaryAccent,
          inactiveTrackColor: Colors.white10,
          thumbColor: primaryAccent,
          overlayColor: primaryAccent.withAlpha(40),
          trackHeight: 6,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}
