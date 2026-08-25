import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/presentation/widgets/common/coordinate_notice.dart';
import 'package:flutter_codefest/presentation/widgets/common/disaster_chip.dart';
import 'package:flutter_codefest/presentation/widgets/common/info_row.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/nearby_transit_section.dart';
import 'package:geolocator/geolocator.dart';

/// A shelter's full detail.
///
/// Below [MapConstants.desktopBreakpoint] this renders as a draggable
/// bottom sheet; at or above it, as a fixed-width sidebar docked to the
/// right edge, full height, so it reads like a normal desktop side panel
/// instead of a mobile sheet stretched thin.
///
/// Stays mounted across open/close so it can animate out instead of just
/// vanishing — the caller keeps passing the last-known [shelter] while
/// [visible] is false and the close animation plays.
class ShelterDetailSheet extends StatefulWidget {
  const ShelterDetailSheet({
    super.key,
    required this.shelter,
    required this.currentPosition,
    required this.onClose,
    required this.onNavigate,
    this.wide = false,
    this.visible = true,
  });

  final Shelter shelter;
  final Position? currentPosition;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final bool wide;
  final bool visible;

  @override
  State<ShelterDetailSheet> createState() => _ShelterDetailSheetState();
}

class _ShelterDetailSheetState extends State<ShelterDetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant ShelterDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _animated(Widget child) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return IgnorePointer(
      ignoring: !widget.visible,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: widget.wide ? const Offset(1, 0) : const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.wide
        ? _buildWideSidebar(context)
        : _buildMobileSheet(context);
  }

  // ---------------------------------------------------------------------
  // Desktop: a full-height sidebar docked to the right edge.
  // ---------------------------------------------------------------------

  Widget _buildWideSidebar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned(
      top: 16,
      right: 16,
      bottom: 16,
      width: MapConstants.desktopPanelWidth,
      child: _animated(
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: _content(context, colorScheme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mobile: the draggable bottom sheet.
  // ---------------------------------------------------------------------

  Widget _buildMobileSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: MapConstants.mobileDetailSheetInitialFraction,
      minChildSize: MapConstants.mobileDetailSheetInitialFraction,
      maxChildSize: 0.8,
      snap: true,
      snapSizes: const [0.35, 0.8],
      builder: (context, scrollController) {
        return _animated(
          Container(
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
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: _content(context, colorScheme),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Shared content, reused by both layouts.
  // ---------------------------------------------------------------------

  List<Widget> _content(BuildContext context, ColorScheme colorScheme) {
    final shelter = widget.shelter;
    final position = widget.currentPosition;
    final canNavigate =
        shelter.hasCoordinate || shelter.address.trim().isNotEmpty;
    final distanceMeters = position != null && shelter.hasCoordinate
        ? distanceToShelter(shelter, position.latitude, position.longitude)
        : null;

    return [
      Row(
        children: [
          Icon(Icons.location_on, color: colorScheme.primary, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              shelter.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
        ],
      ),
      const Divider(height: 24),

      if (canNavigate) ...[
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onNavigate,
            icon: Icon(Icons.navigation, color: colorScheme.onPrimary),
            label: Text(
              distanceMeters == null
                  ? '開始導航'
                  : '開始導航 '
                        '(${(distanceMeters / 1000).toStringAsFixed(2)} 公里)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimary,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (distanceMeters != null)
          Row(
            children: [
              Icon(
                Icons.directions_walk,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                formatWalkingTime(distanceMeters),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
      ],

      CoordinateNotice(shelter: shelter),

      InfoRow(label: '地址', value: shelter.address),
      InfoRow(label: '行政區', value: shelter.district),
      InfoRow(label: '里', value: shelter.village),
      InfoRow(label: '郵遞區號', value: shelter.postalCode),

      if (shelter.flood == 'Y' ||
          shelter.earthquake == 'Y' ||
          shelter.landslide == 'Y' ||
          shelter.tsunami == 'Y') ...[
        const SizedBox(height: 16),
        _SectionTitle('災害類型'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (shelter.flood == 'Y')
              const DisasterChip(label: '水災', icon: Icons.water_drop),
            if (shelter.earthquake == 'Y')
              const DisasterChip(label: '地震', icon: Icons.warning),
            if (shelter.landslide == 'Y')
              const DisasterChip(label: '土石流', icon: Icons.landscape),
            if (shelter.tsunami == 'Y')
              const DisasterChip(label: '海嘯', icon: Icons.waves),
          ],
        ),
        const SizedBox(height: 16),
      ],

      _SectionTitle('設施資訊'),
      const SizedBox(height: 8),
      InfoRow(label: '類型', value: shelter.type),
      InfoRow(label: '收容人數', value: '${shelter.capacity} 人'),
      if (shelter.area.isNotEmpty)
        InfoRow(
          label: '面積',
          // 上游此欄位偶爾是中文說明("俟搬遷後重新評估"),
          // 直接加單位會變成 "俟搬遷後重新評估 ㎡"。
          value: double.tryParse(shelter.area.replaceAll(',', '')) != null
              ? '${shelter.area} ㎡'
              : shelter.area,
        ),
      InfoRow(label: '室內空間', value: shelter.indoor == 'Y' ? '有' : '無'),
      InfoRow(label: '室外空間', value: shelter.outdoor == 'Y' ? '有' : '無'),
      InfoRow(label: '無障礙設施', value: shelter.accessible == 'Y' ? '有' : '無'),
      // Unlike indoor/outdoor/accessible, NFA carries no equivalent of this
      // field at all — every nationwide shelter's reliefStation arrives as
      // '', not a real 'N'. Falling through to "否" the way the other three
      // do would tell 5,854 shelters "not a relief station" when the honest
      // answer is "no data". InfoRow already hides an empty value, so
      // leaving it '' here reads as "not stated" instead of a false no.
      InfoRow(
        label: '救濟站',
        value: switch (shelter.reliefStation) {
          'Y' => '是',
          'N' => '否',
          _ => '',
        },
      ),

      if (shelter.hasCoordinate)
        NearbyTransitSection(
          // Without a key tied to the shelter, selecting a different one
          // reuses the same State object — its `late final` fetch Future
          // was already resolved for the *previous* shelter's coordinates
          // and never re-runs, so the section keeps showing stale transit
          // data. Keying on the shelter forces Flutter to tear down and
          // recreate the widget (and re-fetch) whenever the selection changes.
          key: ValueKey(shelter.id),
          lat: shelter.latitude!,
          lng: shelter.longitude!,
          city: shelter.city,
          currentPosition: position,
        ),

      const SizedBox(height: 16),
      _SectionTitle('聯絡資訊'),
      const SizedBox(height: 8),
      InfoRow(label: '聯絡人', value: shelter.contactName),
      InfoRow(label: '聯絡電話', value: shelter.contactPhone),
      InfoRow(label: '管理人', value: shelter.managerName),
      InfoRow(label: '管理人電話', value: shelter.managerPhone),

      if (shelter.remarks.isNotEmpty) ...[
        const SizedBox(height: 16),
        _SectionTitle('備註'),
        const SizedBox(height: 8),
        Text(
          shelter.remarks,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}
