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
    const primaryAccent = Color(0xFFB69CFF);
    const secondaryAccent = Color(0xFF74E6D1);
    const darkBackground = Color(0xFF0B101B);
    const surfaceColor = Color(0xFF151C2B);
    const surfaceElevated = Color(0xFF1B2638);

    return MaterialApp(
      title: 'MelodiScan',
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
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: Colors.white.withAlpha(14), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: Colors.white,
          ),
          surfaceTintColor: Colors.transparent,
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
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: const Color(0xFFF4F1FA),
              displayColor: const Color(0xFFF4F1FA),
            ),
      ),
      home: const ScanScreen(),
    );
  }
}
