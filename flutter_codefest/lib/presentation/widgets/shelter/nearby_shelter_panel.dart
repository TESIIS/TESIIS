import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/presentation/widgets/common/disaster_chip.dart';
import 'package:geolocator/geolocator.dart';

/// The persistent bottom panel showing the single nearest shelter, plus the
/// floating user-manual button above it. Shown whenever a fix is available
/// and neither search nor the detail sheet is open.
class NearbyShelterPanel extends StatelessWidget {
  const NearbyShelterPanel({
    super.key,
    required this.nearest,
    required this.currentPosition,
    required this.onNavigate,
    required this.onViewDetail,
    required this.onOpenManual,
  });

  final Shelter nearest;
  final Position currentPosition;
  final VoidCallback onNavigate;
  final VoidCallback onViewDetail;
  final VoidCallback onOpenManual;

  String get _distanceText {
    if (!nearest.hasCoordinate) return '尚無座標';
    final meters = distanceToShelter(
      nearest,
      currentPosition.latitude,
      currentPosition.longitude,
    );
    return '距離 ${(meters / 1000).toStringAsFixed(2)} 公里';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: 16,
            bottom: screenHeight * 0.6 + 16,
            child: Material(
              color: colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 6,
              child: InkWell(
                onTap: onOpenManual,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.menu_book,
                    color: colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),

          // 底部往上提升後，補一個背景避免透明露出地圖
          Positioned(
            bottom: AppPlatform.isWeb ? -16 : 0,
            left: 0,
            right: 0,
            child: Container(
              height: screenHeight * 0.10 + (AppPlatform.isWeb ? 16 : 0),
              color: colorScheme.surface,
            ),
          ),
          Positioned(
            bottom: screenHeight * 0.10 + (AppPlatform.isWeb ? -16 : 0),
            left: 0,
            right: 0,
            child: Container(
              height: screenHeight * 0.25,
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
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          color: colorScheme.primary,
                          size: 24,
                        ),
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Scrolls instead of overflowing when a shelter has
                          // enough hazard/space tags for the Wrap to run onto
                          // a second line — there's no ceiling on how many of
                          // the six tags can be 'Y' at once.
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        _distanceText,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (nearest.flood == 'Y')
                                        const CompactChip(
                                          label: '水災',
                                          icon: Icons.water_drop,
                                        ),
                                      if (nearest.earthquake == 'Y')
                                        const CompactChip(
                                          label: '地震',
                                          icon: Icons.warning,
                                        ),
                                      if (nearest.landslide == 'Y')
                                        const CompactChip(
                                          label: '土石流',
                                          icon: Icons.landscape,
                                        ),
                                      if (nearest.tsunami == 'Y')
                                        const CompactChip(
                                          label: '海嘯',
                                          icon: Icons.waves,
                                        ),
                                      if (nearest.indoor == 'Y')
                                        const CompactChip(
                                          label: '室內',
                                          icon: Icons.home,
                                        ),
                                      if (nearest.outdoor == 'Y')
                                        const CompactChip(
                                          label: '室外',
                                          icon: Icons.park,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 20,
                                  ),
                                  side: BorderSide(
                                    color: colorScheme.primary,
                                    width: 2,
                                  ),
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
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
