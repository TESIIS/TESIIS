import 'dart:io' show stderr;

import 'package:get_it/get_it.dart';

import '../../data/datasources/external/nfa_shelter_api.dart';
import '../../data/datasources/external/tdx_client.dart';
import '../../data/datasources/local/shelter_snapshot_source.dart';
import '../../data/repositories_impl/shelter_repository_impl.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../../domain/services/shelter_service.dart';
import '../../domain/services/transit_service.dart';
import '../../presentation/controllers/shelter_controller.dart';
import '../../presentation/controllers/transit_controller.dart';
import '../config/env.dart';

final getIt = GetIt.instance;

/// Raised when the nationwide snapshot cannot be loaded at startup.
class SnapshotUnavailable implements Exception {
  SnapshotUnavailable(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() =>
      '''
Nationwide snapshot unavailable at "$path": $cause

This file is the floor the server falls back to when the live NFA fetch is
unavailable or looks implausible — starting without it would mean a fetch
failure on the very first request serves nothing at all.

The snapshot is committed to the repo at ${Env.defaultSnapshotCsvPath}, so a
missing file usually means the server was started from the wrong directory —
the path is relative to the working directory. Run it from server/, or:

  dart run tool/build_nationwide_snapshot.dart --report   # rebuild the snapshot
  SNAPSHOT_CSV=/path/to/snapshot.csv ...                  # point at another copy''';
}

/// Loads the nationwide snapshot, or throws [SnapshotUnavailable].
///
/// Called by `main` *before* [setupDependencies] rather than from inside a DI
/// factory. get_it wraps anything a factory throws in its own error and prints
/// a stack trace, which buries the explanation the operator actually needs.
/// Checking the precondition up front keeps DI a pure wiring step.
///
/// Deliberately fatal: a missing snapshot is a deployment error (the file
/// ships with the repo), not a runtime condition worth degrading around.
ShelterSnapshotSource loadShelterSnapshot() {
  final path = Env.snapshotCsvPath;
  try {
    final source = ShelterSnapshotSource.loadFromFile(path);
    stderr.writeln(
      '[DI] Nationwide snapshot: $path '
      '(${source.shelters.length} shelters, '
      '${source.countsByCity.length} counties, '
      'updated ${source.snapshotUpdatedAt?.toIso8601String() ?? "unknown"})',
    );
    return source;
  } catch (e) {
    throw SnapshotUnavailable(path, e);
  }
}

void setupDependencies({required ShelterSnapshotSource snapshot}) {
  getIt.registerLazySingleton<NfaShelterApi>(NfaShelterApi.new);
  getIt.registerSingleton<ShelterSnapshotSource>(snapshot);

  getIt.registerLazySingleton<ShelterRepository>(
    () => ShelterRepositoryImpl(api: getIt(), snapshot: getIt()),
  );
  getIt.registerLazySingleton<ShelterService>(
    () => ShelterService(repository: getIt()),
  );
  getIt.registerFactory<ShelterController>(
    () => ShelterController(service: getIt()),
  );

  getIt.registerLazySingleton<TdxClient>(TdxClient.new);
  getIt.registerLazySingleton<TransitService>(
    () => TransitService(client: getIt()),
  );
  getIt.registerFactory<TransitController>(
    () => TransitController(service: getIt()),
  );
}
