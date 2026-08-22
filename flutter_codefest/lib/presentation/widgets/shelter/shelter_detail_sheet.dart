import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/presentation/widgets/common/coordinate_notice.dart';
import 'package:flutter_codefest/presentation/widgets/common/disaster_chip.dart';
import 'package:flutter_codefest/presentation/widgets/common/info_row.dart';
import 'package:geolocator/geolocator.dart';

/// The draggable bottom sheet showing a shelter's full detail.
class ShelterDetailSheet extends StatelessWidget {
  const ShelterDetailSheet({
    super.key,
    required this.shelter,
    required this.currentPosition,
    required this.onClose,
    required this.onNavigate,
  });

  final Shelter shelter;
  final Position? currentPosition;
  final VoidCallback onClose;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final position = currentPosition;
    final canNavigate =
        position != null && shelter.latitude != null && shelter.longitude != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.35,
      maxChildSize: 0.8,
      snap: true,
      snapSizes: const [0.35, 0.8],
      builder: (context, scrollController) {
        return Container(
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
                  children: [
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
                        IconButton(icon: const Icon(Icons.close), onPressed: onClose),
                      ],
                    ),
                    const Divider(height: 24),

                    if (canNavigate) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onNavigate,
                          icon: Icon(Icons.navigation, color: colorScheme.onPrimary),
                          label: Text(
                            '開始導航 '
                            '(${(distanceToShelter(shelter, position.latitude, position.longitude) / 1000).toStringAsFixed(2)} 公里)',
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
                    InfoRow(
                      label: '無障礙設施',
                      value: shelter.accessible == 'Y' ? '有' : '無',
                    ),
                    InfoRow(
                      label: '救濟站',
                      value: shelter.reliefStation == 'Y' ? '是' : '否',
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
