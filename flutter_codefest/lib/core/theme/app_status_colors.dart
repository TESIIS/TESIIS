import 'package:flutter/material.dart';

/// Which situation a [StatusBanner] is reporting, e.g. a location error vs a
/// desktop-viewport hint.
enum StatusTone { info, success, warning, danger }

/// One tone's palette: background, border and content colours that stay
/// legible in both light and dark mode.
class StatusPalette {
  const StatusPalette({
    required this.container,
    required this.border,
    required this.onContainer,
  });

  final Color container;
  final Color border;
  final Color onContainer;
}

/// Replaces the hardcoded `Colors.orange.shade100` / `Colors.green.shade100`
/// / `Colors.red.shade100` / `Colors.blue.shade50` that used to be scattered
/// through the map screen — those hold their light-mode value and mostly
/// disappear against a dark background.
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final StatusPalette info;
  final StatusPalette success;
  final StatusPalette warning;
  final StatusPalette danger;

  StatusPalette of(StatusTone tone) => switch (tone) {
    StatusTone.info => info,
    StatusTone.success => success,
    StatusTone.warning => warning,
    StatusTone.danger => danger,
  };

  factory AppStatusColors.forBrightness(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return AppStatusColors(
      info: StatusPalette(
        container: isDark ? const Color(0xFF16324A) : const Color(0xFFE3F2FD),
        border: isDark ? const Color(0xFF3E80AC) : const Color(0xFF90CAF9),
        onContainer: isDark ? const Color(0xFFBFE0FF) : const Color(0xFF0D47A1),
      ),
      success: StatusPalette(
        container: isDark ? const Color(0xFF17351F) : const Color(0xFFE8F5E9),
        border: isDark ? const Color(0xFF4C8C58) : const Color(0xFFA5D6A7),
        onContainer: isDark ? const Color(0xFFB6E6BE) : const Color(0xFF1B5E20),
      ),
      warning: StatusPalette(
        container: isDark ? const Color(0xFF3E2E10) : const Color(0xFFFFF3E0),
        border: isDark ? const Color(0xFFB3812F) : const Color(0xFFFFB74D),
        onContainer: isDark ? const Color(0xFFFFD8A8) : const Color(0xFFE65100),
      ),
      danger: StatusPalette(
        container: isDark ? const Color(0xFF3E1717) : const Color(0xFFFFEBEE),
        border: isDark ? const Color(0xFFB35555) : const Color(0xFFEF9A9A),
        onContainer: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB71C1C),
      ),
    );
  }

  @override
  AppStatusColors copyWith({
    StatusPalette? info,
    StatusPalette? success,
    StatusPalette? warning,
    StatusPalette? danger,
  }) => AppStatusColors(
    info: info ?? this.info,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
  );

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    // Tones never need to animate between each other; the app has no
    // mid-transition state that would call this with a real `t`.
    if (other is! AppStatusColors) return this;
    return t < 0.5 ? this : other;
  }
}
