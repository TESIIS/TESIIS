import 'package:flutter/material.dart';

import 'app_status_colors.dart';

/// Brand seed. Material 3's tonal palette generation shifts the exact hue
/// slightly to guarantee contrast in both brightnesses — this is expected,
/// not a bug.
const Color _seed = Color(0xFF5AB4C5);

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [AppStatusColors.forBrightness(brightness)],
    );
  }
}
