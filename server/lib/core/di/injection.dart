import 'dart:io' show stderr;

import 'package:get_it/get_it.dart';

import '../../data/datasources/external/shelter_api.dart';
import '../../data/datasources/local/coordinate_source.dart';
import '../../data/repositories_impl/shelter_repository_impl.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../../domain/services/shelter_service.dart';
import '../../presentation/controllers/shelter_controller.dart';
import '../config/env.dart';

final getIt = GetIt.instance;

/// Raised when the coordinate table cannot be loaded at startup.
class CoordinateTableUnavailable implements Exception {
  CoordinateTableUnavailable(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() =>
      '''
Coordinate table unavailable at "$path": $cause

The Taipei OpenData dataset carries no 座標x/座標y, so this file is the only
source of coordinates in the system. Starting without it would serve all 401
shelters with null coordinates and render a map with zero markers.

The table is committed to the repo at ${Env.defaultCoordinatesCsvPath}, so a
missing file usually means the server was started from the wrong directory —
the path is relative to the working directory. Run it from server/, or:

  dart run tool/build_coordinates.dart      # rebuild the table
  COORDINATES_CSV=/path/to/table.csv ...    # point at another copy''';
}

/// Loads the coordinate table, or throws [CoordinateTableUnavailable].
///
/// Called by `main` *before* [setupDependencies] rather than from inside a DI
/// factory. get_it wraps anything a factory throws in its own error and prints
/// a stack trace, which buries the explanation the operator actually needs.
/// Checking the precondition up front keeps DI a pure wiring step.
///
/// Deliberately fatal: the previous SQLite implementation fell back to an
/// in-memory database at this point, which is exactly how the map ended up
/// empty with nothing but a warning scrolling past in the logs. The table
/// ships with the repo, so a missing one is a deployment error, not a runtime
/// condition worth degrading around.
CoordinateSource loadCoordinateSource() {
  final path = Env.coordinatesCsvPath;
  try {
    final source = CoordinateSource.loadFromFile(path);
    final coverage = source.coverage;
    stderr.writeln(
      '[DI] Coordinate table: $path '
      '(${coverage.withCoordinates}/${coverage.total} shelters located, '
      '${(coverage.ratio * 100).toStringAsFixed(1)}%)',
    );
    return source;
  } catch (e) {
    throw CoordinateTableUnavailable(path, e);
  }
}

void setupDependencies({required CoordinateSource coordinates}) {
  getIt.registerLazySingleton<ShelterApi>(ShelterApi.new);
  getIt.registerSingleton<CoordinateSource>(coordinates);

  getIt.registerLazySingleton<ShelterRepository>(
    () => ShelterRepositoryImpl(api: getIt(), coordinates: getIt()),
  );
  getIt.registerLazySingleton<ShelterService>(
    () => ShelterService(repository: getIt()),
  );
  getIt.registerFactory<ShelterController>(
    () => ShelterController(service: getIt()),
  );
}
