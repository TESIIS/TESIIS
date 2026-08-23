import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_codefest/presentation/widgets/search/edge_fade_overlay.dart';

class _FilterDef {
  const _FilterDef(this.label, this.type, this.icon);
  final String label;
  final String type;
  final IconData icon;
}

const _filterDefs = [
  _FilterDef('土石流', 'landslide', Icons.landscape),
  _FilterDef('海嘯', 'tsunami', Icons.waves),
  _FilterDef('地震', 'earthquake', Icons.warning),
  _FilterDef('水災', 'flood', Icons.water_drop),
  _FilterDef('核子事故', 'nuclear', Icons.dangerous),
  _FilterDef('室內', 'indoor', Icons.home),
  _FilterDef('室外', 'outdoor', Icons.park),
];

/// Horizontally scrolling row of disaster/space-type filter chips, shown
/// while searching.
class FilterChipBar extends StatefulWidget {
  const FilterChipBar({
    super.key,
    required this.isSelected,
    required this.onToggle,
  });

  final bool Function(String filterType) isSelected;
  final ValueChanged<String> onToggle;

  @override
  State<FilterChipBar> createState() => _FilterChipBarState();
}

class _FilterChipBarState extends State<FilterChipBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// A `SingleChildScrollView` only ever accepts drag input for its own
  /// axis — a mouse wheel (which reports a vertical delta regardless of
  /// which way the list actually scrolls) is never translated to it
  /// automatically. On desktop, where a wheel is the default pointer input,
  /// that reads as "the bar doesn't scroll at all". This reroutes the wheel's
  /// vertical delta onto the horizontal offset by hand.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // IntrinsicHeight, rather than a fixed pixel height, so the chips'
      // text never clips: a fixed height plus the ListView's and each
      // chip's own vertical padding left almost no margin for the actual
      // glyph metrics, and CJK line heights vary enough by platform/font
      // to blow through it.
      child: IntrinsicHeight(
        child: Stack(
          children: [
            Listener(
              onPointerSignal: _handlePointerSignal,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < _filterDefs.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _FilterChipButton(
                        label: _filterDefs[i].label,
                        icon: _filterDefs[i].icon,
                        selected: widget.isSelected(_filterDefs[i].type),
                        onTap: () => widget.onToggle(_filterDefs[i].type),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const EdgeFadeOverlay(side: FadeSide.left),
            const EdgeFadeOverlay(side: FadeSide.right),
          ],
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onChipColor = selected ? colorScheme.onPrimary : colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : colorScheme.surface,
          border: Border.all(color: colorScheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              scale: selected ? 1.1 : 1.0,
              child: Icon(icon, size: 18, color: onChipColor),
            ),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onChipColor,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
