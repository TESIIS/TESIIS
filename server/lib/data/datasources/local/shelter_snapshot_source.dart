// lib/data/datasources/local/shelter_snapshot_source.dart
//
// The committed nationwide snapshot that makes the map work when the live
// NFA fetch is unavailable or looks implausible.
//
// Modelled on CoordinateSource (the Taipei-only coordinate table it
// complements, not replaces — see build_coordinates.dart's header comment).
// Built offline by `dart run tool/build_nationwide_snapshot.dart` and
// committed to the repo.

import 'dart:io';

import '../../../core/csv/csv_codec.dart';
import '../../../core/geo/taiwan_bounds.dart';
import '../../../domain/entities/shelter.dart';
import '../../../domain/entities/shelter_fields.dart';
import 'coordinate_source.dart' show CoordinateCoverage;

/// The columns `build_nationwide_snapshot.dart` writes, in order.
const shelterSnapshotCsvHeader = [
  'source_id',
  'source',
  'source_updated_at',
  'city_code',
  'city',
  'township',
  'village',
  'name',
  'address',
  'lng',
  'lat',
  'coordinate_confidence',
  'capacity',
  'flood',
  'quake',
  'landslide',
  'tsunami',
  'nuclear',
  'indoor',
  'outdoor',
  'accessible',
  'service_villages',
  'manager_name',
  'manager_phone',
];

class ShelterSnapshotSource {
  ShelterSnapshotSource._(
    this._shelters,
    this.snapshotUpdatedAt,
    this.coverage,
  );

  final List<Shelter> _shelters;

  /// The newest `source_updated_at` across every row, or null if the column
  /// was never populated (e.g. an empty snapshot).
  final DateTime? snapshotUpdatedAt;

  final CoordinateCoverage coverage;

  List<Shelter> get shelters => _shelters;

  Map<String, int> get countsByCity {
    final out = <String, int>{};
    for (final s in _shelters) {
      out[s.city] = (out[s.city] ?? 0) + 1;
    }
    return out;
  }

  factory ShelterSnapshotSource.empty() => ShelterSnapshotSource._(
    const [],
    null,
    const CoordinateCoverage(total: 0, withCoordinates: 0, bySource: {}),
  );

  static const _requiredColumns = ['source_id', 'city', 'lng', 'lat'];

  factory ShelterSnapshotSource.fromCsv(String csv) {
    final rows = parseCsvAsMaps(csv);
    if (rows.isEmpty) return ShelterSnapshotSource.empty();

    final missing = _requiredColumns
        .where((c) => !rows.first.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        'Nationwide snapshot is missing required column(s): ${missing.join(", ")}',
      );
    }

    final shelters = <Shelter>[];
    final bySource = <String, int>{};
    var withCoordinates = 0;
    DateTime? newest;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final city = (row['city'] ?? '').trim();
      final normalizedCity = ShelterText.normalizeName(city);
      final lng = double.tryParse((row['lng'] ?? '').trim());
      final lat = double.tryParse((row['lat'] ?? '').trim());

      // Re-apply the bounding-box gate at load time, same reasoning as
      // CoordinateSource: the build tool already filters, but this file is
      // hand-editable and a typo must not put a shelter in another county.
      // A row that fails here is dropped entirely rather than kept with a
      // null coordinate — unlike Taipei OpenData, NFA gives this system no
      // other way to know a shelter without a valid point "exists".
      final ok =
          lng != null &&
          lat != null &&
          TaiwanBounds.containsForCounty(normalizedCity, lng, lat);
      if (!ok) continue;

      withCoordinates++;
      final source = (row['source'] ?? 'nfa_point_file').trim();
      bySource[source] = (bySource[source] ?? 0) + 1;

      final updatedAtRaw = (row['source_updated_at'] ?? '').trim();
      final updatedAt = updatedAtRaw.isEmpty
          ? null
          : DateTime.tryParse(updatedAtRaw);
      if (updatedAt != null && (newest == null || updatedAt.isAfter(newest))) {
        newest = updatedAt;
      }

      shelters.add(
        Shelter(
          id: i,
          importDate: null,
          shelterCode: (row['source_id'] ?? '').trim(),
          name: (row['name'] ?? '').trim(),
          city: city,
          zipcode: '',
          township: (row['township'] ?? '').trim(),
          village: (row['village'] ?? '').trim(),
          address: (row['address'] ?? '').trim(),
          type: '',
          flood: row['flood'],
          quake: row['quake'],
          landslide: row['landslide'],
          tsunami: row['tsunami'],
          relief: null,
          accessible: row['accessible'],
          indoor: row['indoor'],
          outdoor: row['outdoor'],
          serviceVillages: row['service_villages'],
          capacity: ShelterNumber.parseInt(row['capacity']),
          area: null,
          contactName: null,
          contactPhone: null,
          managerName: (row['manager_name'] ?? '').trim().isEmpty
              ? null
              : row['manager_name'],
          managerPhone: (row['manager_phone'] ?? '').trim().isEmpty
              ? null
              : row['manager_phone'],
          notes: null,
          x: lng,
          y: lat,
          coordinateSource: source,
          coordinateConfidence: row['coordinate_confidence'],
          cityCode: (row['city_code'] ?? '').trim().isEmpty
              ? null
              : row['city_code'],
          nuclear: row['nuclear'],
          sourceName: source,
          sourceUpdatedAt: updatedAt,
        ),
      );
    }

    return ShelterSnapshotSource._(
      shelters,
      newest,
      CoordinateCoverage(
        total: rows.length,
        withCoordinates: withCoordinates,
        bySource: bySource,
      ),
    );
  }

  /// Loads the snapshot from [path]. Throws if the file is missing — the
  /// snapshot ships with the repo, so a missing file means the process was
  /// started from the wrong directory, not a runtime condition to degrade
  /// around. Same reasoning as `CoordinateSource.loadFromFile`.
  factory ShelterSnapshotSource.loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Nationwide snapshot not found', path);
    }
    return ShelterSnapshotSource.fromCsv(file.readAsStringSync());
  }
}
