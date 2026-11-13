import 'package:flutter/material.dart';

/// Signtech File Sharing themes — Team Drive blue, glassy Dark & Light.
///
/// Accent is the Team Drive indigo blue from the user's reference
/// screenshots (#4F5BD5 light, a touch brighter #5B6BE0 on dark so
/// it stays readable on black). Glassy = translucent surfaces,
/// soft 1px borders, big 16px radii, no hard shadows.
///
/// (The Signtech Digital shop software keeps its own red logo —
/// this file-sharing app follows the blue reference the user sent.)
class SigntechTheme {
  static const Color brandBlue = Color(0xFF4F5BD5);
  static const Color brandBlueDark = Color(0xFF5B6BE0);
  static const Color brandBlueSoft = Color(0xFFE7EBFF);

  // Kept for callers that used the old name — same blue now.
  static const Color brandRed = brandBlue;

  static const Color _darkBg = Color(0xFF0F0F12);
  static const Color _darkSurface = Color(0xFF1B1B22);
  static const Color _darkCard = Color(0xFF232330);

  static const Color _lightBg = Color(0xFFF7F7F9);
  static const Color _lightSurface = Colors.white;
  static const Color _lightCard = Colors.white;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: brandBlueDark,
      secondary: brandBlueDark,
      surface: _darkSurface,
      onSurface: Colors.white,
      onSurfaceVariant: Colors.white70,
    );
    return _base(scheme, _darkBg, _darkCard, Brightness.dark);
  }

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: brandBlue,
      secondary: brandBlue,
      surface: _lightSurface,
      onSurface: Color(0xFF141419),
      onSurfaceVariant: Color(0xFF5B5B66),
    );
    return _base(scheme, _lightBg, _lightCard, Brightness.light);
  }

  static ThemeData _base(
    ColorScheme scheme,
    Color bg,
    Color card,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? brandBlueDark : brandBlue;
    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      // Team Drive screenshot-er font — Poppins (Google Fonts, OFL).
      // Bundled in assets/fonts, no internet needed at runtime.
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: bg,
      cardColor: card,
      appBarTheme: AppBarTheme(
        backgroundColor: (dark ? _darkSurface : _lightSurface)
            .withOpacity(dark ? 0.85 : 0.9),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: card.withOpacity(dark ? 0.92 : 0.95),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: dark ? Colors.white12 : const Color(0xFFE4E4E9),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: dark ? Colors.white24 : const Color(0xFFD4D4DA),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card.withOpacity(dark ? 0.85 : 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? Colors.white24 : const Color(0xFFD4D4DA),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: dark ? Colors.white24 : const Color(0xFFD4D4DA),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        labelStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerColor:
          dark ? Colors.white12 : const Color(0xFFE4E4E9),
    );
  }
}
