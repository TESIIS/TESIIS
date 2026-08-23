import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:geolocator/geolocator.dart';

/// The result-count summary plus the scrollable list of matching shelters
/// shown under the search bar. Loads the next page when scrolled to the
/// bottom while [hasMore].
class SearchResultsList extends StatelessWidget {
  const SearchResultsList({
    super.key,
    required this.shelters,
    required this.total,
    required this.hasMore,
    required this.isLoadingMore,
    required this.hasFilters,
    required this.currentPosition,
    required this.selectedShelter,
    required this.onSelect,
    required this.onLoadMore,
  });

  final List<Shelter> shelters;

  /// How many shelters matched before paging — what the header shows, so it
  /// reads "共 200 筆" while only the first page is in memory.
  final int total;

  final bool hasMore;
  final bool isLoadingMore;
  final bool hasFilters;
  final Position? currentPosition;
  final Shelter? selectedShelter;
  final ValueChanged<Shelter> onSelect;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (shelters.isEmpty) {
      return _EmptyState(hasFilters: hasFilters);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ResultSummary(shelters: shelters, total: total),
        Flexible(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (!hasMore ||
                  isLoadingMore ||
                  notification.metrics.extentAfter > 200) {
                return false;
              }
              onLoadMore();
              return false;
            },
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: shelters.length + (hasMore ? 1 : 0),
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                if (index == shelters.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final shelter = shelters[index];
                return _ShelterResultTile(
                  shelter: shelter,
                  isSelected: selectedShelter?.name == shelter.name,
                  currentPosition: currentPosition,
                  onTap: () => onSelect(shelter),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '找不到相似的結果',
              style: TextStyle(
                fontSize: 16,
                color: onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters ? '請嘗試調整篩選條件' : '請嘗試其他關鍵字',
              style: TextStyle(fontSize: 14, color: onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result count, plus a note when some results cannot be mapped.
///
/// Without this the list and the map disagree — a search can return 30 hits
/// while only 28 pins appear — and the user has no way to know why.
class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.shelters, required this.total});

  final List<Shelter> shelters;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final missing = shelters.where((s) => !s.hasCoordinate).length;
    final hasMore = shelters.length < total;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            hasMore ? '共 $total 筆（已載入 ${shelters.length} 筆）' : '共 $total 筆',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (missing > 0) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.location_off_outlined,
              size: 14,
              color: colorScheme.tertiary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '其中 $missing 筆尚無座標,不會出現在地圖上',
                style: TextStyle(fontSize: 12, color: colorScheme.tertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShelterResultTile extends StatelessWidget {
  const _ShelterResultTile({
    required this.shelter,
    required this.isSelected,
    required this.currentPosition,
    required this.onTap,
  });

  final Shelter shelter;
  final bool isSelected;
  final Position? currentPosition;
  final VoidCallback onTap;

  /// Nationwide there are many facilities that share a generic name
  /// ("活動中心", "○○國小") or even a full name across different counties —
  /// without the region prefix a search result is unidentifiable at a
  /// glance.
  String get _locationText {
    final region = [
      shelter.city,
      shelter.district,
    ].where((s) => s.isNotEmpty).join('');
    return region.isEmpty ? shelter.address : '$region・${shelter.address}';
  }

  String get _distanceText {
    // These facilities exist, they just have no coordinate on record — still
    // listed, with an external map offered instead.
    if (!shelter.hasCoordinate) return '尚無座標';
    final position = currentPosition;
    if (position == null) return '距離未知';
    final meters = distanceToShelter(
      shelter,
      position.latitude,
      position.longitude,
    );
    return '距離 ${(meters / 1000).toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return ListTile(
      dense: true,
      tileColor: isSelected ? colorScheme.primaryContainer : null,
      leading: Icon(Icons.location_on, color: accent, size: 20),
      title: Text(
        shelter.name,
        style: TextStyle(
          color: accent,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _locationText,
            style: TextStyle(color: accent, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(_distanceText, style: TextStyle(color: accent, fontSize: 14)),
        ],
      ),
      trailing: Icon(Icons.arrow_forward_ios, color: accent, size: 16),
      onTap: onTap,
    );
  }
}
