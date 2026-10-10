import 'package:flutter/material.dart';

/// A label/value pair in the shelter detail sheet. Renders nothing when
/// [value] is empty, since most detail fields are optional in the source
/// data.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    final labelWidth = 132 * MediaQuery.textScalerOf(context).scale(1);
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
    );
    final valueWidget = Text(
      value,
      style: Theme.of(context).textTheme.bodyMedium,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            labelWidth > constraints.maxWidth * 0.48
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 4), valueWidget],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: labelWidget,
                    ),
                  ),
                  Expanded(child: valueWidget),
                ],
              ),
      ),
    );
  }
}
