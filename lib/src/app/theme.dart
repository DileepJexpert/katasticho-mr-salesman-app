import 'package:flutter/material.dart';

/// Flat, dense, mobile-first theme. Small radius (8px), hairline dividers,
/// minimal borders — cards are reserved for genuinely isolated information.
ThemeData buildFieldTheme() {
  const primary = Color(0xFF2563EB);
  const ink = Color(0xFF111827);
  const surface = Color(0xFFF6F8FC);
  const hairline = Color(0xFFE9EBF0);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    ),
    scaffoldBackgroundColor: surface,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.compact,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(
      thickness: 1,
      space: 1,
      color: hairline,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: hairline),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      horizontalTitleGap: 10,
      minVerticalPadding: 8,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// Shared flat-UI tokens.
class FieldUi {
  FieldUi._();
  static const Color hairline = Color(0xFFE9EBF0);
  static const Color ink = Color(0xFF111827);
  static const Color muted = Color(0xFF6B7280);
  static const double radius = 8;
  static const double gap = 12;
  static const double gapSm = 8;
}
