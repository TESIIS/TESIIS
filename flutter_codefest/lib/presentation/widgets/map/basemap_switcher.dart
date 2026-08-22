import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/map/basemap.dart';

/// Popup button to swap between the three NLSC basemap layers.
class BasemapSwitcher extends StatelessWidget {
  const BasemapSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Basemap selected;
  final ValueChanged<Basemap> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: PopupMenuButton<Basemap>(
        tooltip: '切換底圖',
        icon: Icon(selected.icon, color: colorScheme.onSurfaceVariant),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final basemap in Basemap.values)
            PopupMenuItem(
              value: basemap,
              child: Row(
                children: [
                  Icon(
                    basemap.icon,
                    size: 20,
                    color: basemap == selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(basemap.label),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
