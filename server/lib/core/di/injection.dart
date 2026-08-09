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

/// The coordinate table is the only source of coordinates — the OpenData
/// dataset carries no 座標x/座標y. Losing it degrades into an API that serves
/// every shelter with null coordinates and a map with zero markers, so say so
/// loudly rather than starting up as if nothing happened.
void _warnNoCoordinates(String reason) {
  stderr.writeln('''
!! [DI] Coordinate table unavailable: $reason
!!      Every shelter will be returned with 座標x/座標y = null and the map will
!!      render zero markers.
!!      The table is committed to the repo at ${Env.defaultCoordinatesCsvPath};
!!      rebuild it with:  dart run tool/build_coordinates.dart
!!      or point COORDINATES_CSV at another copy.''');
}

void setupDependencies() {
  getIt.registerLazySingleton<ShelterApi>(ShelterApi.new);

  getIt.registerLazySingleton<CoordinateSource>(() {
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
      _warnNoCoordinates('$e');
      return CoordinateSource.empty();
    }
  });

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
