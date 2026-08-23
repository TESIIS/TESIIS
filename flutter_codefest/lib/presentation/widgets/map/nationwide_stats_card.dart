import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart'
    as repo;

/// A small "how big is this dataset" card for the desktop layout's empty
/// top-right corner — total shelters, counties covered, and how much of the
/// dataset has a usable coordinate.
///
/// Fetches `/shelters/stats` once on mount rather than sharing
/// [ShelterMapViewModel]'s state: this card's numbers are dataset-wide and
/// don't change with the map viewport, search, or filters, so tying it to
/// that view model would only mean re-rendering it on every pan for no
/// reason. A fetch failure just hides the card — the numbers are a nice-to
/// -have, not something worth an error banner over.
class NationwideStatsCard extends StatefulWidget {
  const NationwideStatsCard({super.key});

  @override
  State<NationwideStatsCard> createState() => _NationwideStatsCardState();
}

class _NationwideStatsCardState extends State<NationwideStatsCard> {
  _Stats? _stats;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await repo.fetchShelterStats();
      final coverage = json['coordinateCoverage'] as Map<String, dynamic>;
      final byRegion = json['byRegion'] as List<dynamic>? ?? const [];
      if (!mounted) return;
      setState(() {
        _stats = _Stats(
          total: json['total'] as int? ?? 0,
          counties: byRegion.length,
          coordinateRatio: (coverage['ratio'] as num?)?.toDouble() ?? 0,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stats = _stats;

    if (_failed) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: stats == null
          ? const SizedBox(
              height: 88,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.public, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '全國資料統計',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatRow(
                  icon: Icons.home_work_outlined,
                  label: '避難所總數',
                  value: '${stats.total} 處',
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  icon: Icons.map_outlined,
                  label: '涵蓋縣市',
                  value: '${stats.counties} 縣市',
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  icon: Icons.my_location,
                  label: '座標完整度',
                  value: '${(stats.coordinateRatio * 100).toStringAsFixed(1)}%',
                  colorScheme: colorScheme,
                ),
              ],
            ),
    );
  }
}

class _Stats {
  const _Stats({
    required this.total,
    required this.counties,
    required this.coordinateRatio,
  });

  final int total;
  final int counties;
  final double coordinateRatio;
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
