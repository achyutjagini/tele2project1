import 'package:flutter/material.dart';

// Tele2 brand colors
const Color tele2Purple = Color(0xFF5C2D91);
const Color tele2DarkPurple = Color(0xFF3D1A6E);
const Color tele2LightPurple = Color(0xFF8B5FBF);
const Color tele2Black = Color(0xFF1A1A1A);
const Color tele2DarkGrey = Color(0xFF2D2D2D);
const Color tele2MediumGrey = Color(0xFF4A4A4A);
const Color tele2LightGrey = Color(0xFFF5F5F5);

final tele2Theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: tele2Purple,
    primary: tele2Purple,
    secondary: tele2LightPurple,
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: tele2Black,
    elevation: 0,
    scrolledUnderElevation: 1,
  ),
);

final tele2DarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: tele2Purple,
    primary: tele2Purple,
    secondary: tele2LightPurple,
    surface: tele2DarkGrey,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: tele2Black,
  appBarTheme: const AppBarTheme(
    backgroundColor: tele2DarkGrey,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 1,
  ),
  cardTheme: CardThemeData(
    color: tele2DarkGrey,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: tele2MediumGrey.withValues(alpha: 0.3)),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: tele2MediumGrey,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);
