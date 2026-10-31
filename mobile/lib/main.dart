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
    const darkBackground = Color(0xFF0D1016);
    const surfaceColor = Color(0xFF171B24);
    const surfaceElevated = Color(0xFF202634);

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
          onPrimary: Colors.white,
          onSecondary: Colors.black,
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 1,
          shadowColor: Colors.black.withAlpha(70),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(12), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12151B),
          elevation: 0,
          centerTitle: false,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: const ScanScreen(),
    );
  }
}
