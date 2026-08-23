import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/transit_stop.dart';
import 'package:flutter_codefest/data/repositories/transit_repository.dart';

/// "附近交通" section for the shelter detail sheet.
///
/// Renders nothing at all — not even a loading spinner worth noticing — when
/// TDX is unconfigured, down, or simply has nothing nearby. This is an
/// optional enrichment on top of the shelter's own information, so a TDX
/// hiccup must never surface as an error the user has to make sense of.
typedef NearbyTransitFetcher =
    Future<TransitNearbyResult> Function({
      required double lat,
      required double lng,
      String? city,
    });

class NearbyTransitSection extends StatefulWidget {
  const NearbyTransitSection({
    super.key,
    required this.lat,
    required this.lng,
    required this.city,
    @visibleForTesting NearbyTransitFetcher? fetcher,
  }) : _fetcher = fetcher ?? fetchNearbyTransit;

  final double lat;
  final double lng;
  final String? city;

  /// Overridable only from tests — production always uses [fetchNearbyTransit].
  final NearbyTransitFetcher _fetcher;

  @override
  State<NearbyTransitSection> createState() => _NearbyTransitSectionState();
}

class _NearbyTransitSectionState extends State<NearbyTransitSection> {
  late final Future<TransitNearbyResult> _future = widget._fetcher(
    lat: widget.lat,
    lng: widget.lng,
    city: widget.city,
  );

  IconData _iconFor(TransitMode mode) => switch (mode) {
    TransitMode.bus => Icons.directions_bus,
    TransitMode.tra => Icons.train,
    TransitMode.thsr => Icons.directions_railway,
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TransitNearbyResult>(
      future: _future,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null || !result.available || result.stops.isEmpty) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              '附近交通',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final stop in result.stops)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(stop.mode),
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(stop.name, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '${stop.distanceMeters.round()} 公尺',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
