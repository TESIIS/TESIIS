import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/theme/app_status_colors.dart';

/// A rounded, coloured notice card. Replaces three near-identical
/// `Container` + `BoxDecoration` + `BoxShadow` blocks that used to be
/// duplicated in the map screen for the out-of-range warning, the location
/// message, and the desktop-viewport hint.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.message,
    this.margin = const EdgeInsets.only(top: 8),
  });

  final StatusTone tone;
  final IconData icon;
  final String message;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppStatusColors>()!.of(tone);

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.onContainer, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.onContainer,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
