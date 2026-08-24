import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/data/models/transit_stop.dart';
import 'package:flutter_codefest/data/repositories/transit_repository.dart';
import 'package:flutter_codefest/domain/navigation_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.currentPosition,
    @visibleForTesting NearbyTransitFetcher? fetcher,
  }) : _fetcher = fetcher ?? fetchNearbyTransit;

  final double lat;
  final double lng;
  final String? city;

  /// Used as the walking-directions origin, same as the shelter's own
  /// "開始導航" button — null just means the map URL opens without one.
  final Position? currentPosition;

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

  /// Same URL-building and launch behaviour as the shelter's own "開始導航"
  /// button (`map_page.dart`'s `_openNavigation`) — TDX stops always have a
  /// coordinate, so this always uses [buildDirectionsUri] directly rather
  /// than [buildNavigationUri]'s address-search fallback.
  Future<void> _openDirections(TransitStop stop) async {
    final uri = buildDirectionsUri(
      lat: stop.lat,
      lng: stop.lng,
      from: widget.currentPosition,
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: AppPlatform.isWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!launched && mounted) _showSnackBar('無法開啟地圖應用程式');
    } catch (_) {
      if (mounted) _showSnackBar('開啟導航失敗');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _arrivalText(TransitArrival a) {
    final delay = a.delayMinutes;
    final delaySuffix = delay != null ? '（誤點$delay分）' : '';
    return '${a.label} · ${a.minutesUntil}分$delaySuffix';
  }

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _iconFor(stop.mode),
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stop.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${stop.distanceMeters.round()} 公尺',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.directions),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: '導航到這裡',
                          color: colorScheme.primary,
                          onPressed: () => _openDirections(stop),
                        ),
                      ],
                    ),
                    if (stop.arrivals.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 26),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            for (final arrival in stop.arrivals)
                              Text(
                                _arrivalText(arrival),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                ),
                              ),
                          ],
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
