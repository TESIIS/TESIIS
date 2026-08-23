import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/presentation/widgets/common/disaster_chip.dart';
import 'package:geolocator/geolocator.dart';

/// The nearest-shelter summary, plus the floating user-manual button.
///
/// Below [MapConstants.desktopBreakpoint] this renders as the mobile
/// full-width bottom band; at or above it, as a fixed-width floating card
/// so it doesn't stretch across a wide window.
class NearbyShelterPanel extends StatelessWidget {
  const NearbyShelterPanel({
    super.key,
    required this.nearest,
    required this.currentPosition,
    required this.onNavigate,
    required this.onViewDetail,
    required this.onOpenManual,
    required this.onClose,
    this.wide = false,
  });

  final Shelter nearest;
  final Position currentPosition;
  final VoidCallback onNavigate;
  final VoidCallback onViewDetail;
  final VoidCallback onOpenManual;
  final VoidCallback onClose;
  final bool wide;

  String get _distanceText {
    if (!nearest.hasCoordinate) return '尚無座標';
    final meters = distanceToShelter(
      nearest,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    return '距離 ${(meters / 1000).toStringAsFixed(2)} 公里';
  }

  String? get _walkingTimeText {
    if (!nearest.hasCoordinate) return null;
    return formatWalkingTime(
      distanceToShelter(
        nearest,
        currentPosition.latitude,
        currentPosition.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return wide ? _buildWideCard(context) : _buildMobileBand(context);
  }

  // ---------------------------------------------------------------------
  // Desktop: a fixed-width floating card, bottom-left.
  // ---------------------------------------------------------------------

  Widget _buildWideCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      left: 16,
      bottom: 16,
      width: MapConstants.desktopPanelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ManualButton(colorScheme: colorScheme, onTap: onOpenManual),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _Header(colorScheme: colorScheme)),
                    _CloseButton(colorScheme: colorScheme, onTap: onClose),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoBlock(
                  nearest: nearest,
                  distanceText: _distanceText,
                  walkingTimeText: _walkingTimeText,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 12),
                _ActionButtons(
                  colorScheme: colorScheme,
                  onNavigate: onNavigate,
                  onViewDetail: onViewDetail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mobile: the persistent full-width bottom band.
  // ---------------------------------------------------------------------

  Widget _buildMobileBand(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Anchored at bottom:0 with no top/height, so the card sizes itself to
    // its content and is guaranteed to sit flush with the bottom of the
    // screen — no gap, regardless of viewport height. The previous version
    // computed the card's height as a fraction of MediaQuery's *full*
    // screen height while actually living inside the Scaffold's SafeArea
    // (a *smaller* box), so the two never quite lined up and left a gap
    // that grew with any top/bottom inset.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 12),
            child: _ManualButton(colorScheme: colorScheme, onTap: onOpenManual),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: _Header(colorScheme: colorScheme)),
                    _CloseButton(colorScheme: colorScheme, onTap: onClose),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoBlock(
                  nearest: nearest,
                  distanceText: _distanceText,
                  walkingTimeText: _walkingTimeText,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 12),
                _ActionButtons(
                  colorScheme: colorScheme,
                  onNavigate: onNavigate,
                  onViewDetail: onViewDetail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.colorScheme, required this.onTap});

  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '關閉',
      icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant, size: 20),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _ManualButton extends StatelessWidget {
  const _ManualButton({required this.colorScheme, required this.onTap});

  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(14),
          child: Icon(Icons.menu_book, color: colorScheme.primary, size: 28),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.near_me, color: colorScheme.primary, size: 24),
        const SizedBox(width: 8),
        Text(
          '最近的避難設施',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.nearest,
    required this.distanceText,
    required this.walkingTimeText,
    required this.colorScheme,
  });

  final Shelter nearest;
  final String distanceText;
  final String? walkingTimeText;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          nearest.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                nearest.address,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.straighten,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              distanceText,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (walkingTimeText != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.directions_walk,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                walkingTimeText!,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (nearest.flood == 'Y')
              const CompactChip(label: '水災', icon: Icons.water_drop),
            if (nearest.earthquake == 'Y')
              const CompactChip(label: '地震', icon: Icons.warning),
            if (nearest.landslide == 'Y')
              const CompactChip(label: '土石流', icon: Icons.landscape),
            if (nearest.tsunami == 'Y')
              const CompactChip(label: '海嘯', icon: Icons.waves),
            if (nearest.indoor == 'Y')
              const CompactChip(label: '室內', icon: Icons.home),
            if (nearest.outdoor == 'Y')
              const CompactChip(label: '室外', icon: Icons.park),
          ],
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.colorScheme,
    required this.onNavigate,
    required this.onViewDetail,
  });

  final ColorScheme colorScheme;
  final VoidCallback onNavigate;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onNavigate,
            icon: Icon(
              Icons.navigation,
              color: colorScheme.onPrimary,
              size: 20,
            ),
            label: Text(
              '開始導航',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimary,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: onViewDetail,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            side: BorderSide(color: colorScheme.primary, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            '詳情',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
