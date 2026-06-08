import 'package:get_it/get_it.dart';
import '../../data/datasources/external/shelter_api.dart';
import '../../data/datasources/database/shelter_database.dart';
import '../config/env.dart';
import 'dart:io' show Platform, File;
import '../../data/repositories_impl/shelter_repository_impl.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../../domain/services/shelter_service.dart';
import '../../presentation/controllers/shelter_controller.dart';

final getIt = GetIt.instance;

void setupDependencies() {
	// Data sources
	getIt.registerLazySingleton<ShelterApi>(() => ShelterApi());

	// local DB (geocoding) — tries configured file; if missing or unreadable, falls back to in-memory
	getIt.registerLazySingleton<ShelterDatabase>(() {
		final configuredPath = Platform.environment['GEOCODING_DB'] ?? Env.geocodingDbPath;
		final file = File(configuredPath);
		if (!file.existsSync()) {
			print('[DI] Geocoding DB not found at "$configuredPath" -> using in-memory (no coords will be filled).');
			return ShelterDatabase.open(':memory:');
		}
		try {
			print('[DI] Opening geocoding DB at: $configuredPath');
			final db = ShelterDatabase.open(configuredPath);
			// Build index immediately for deterministic behavior
			db.buildAddressIndex();
			return db;
		} catch (e) {
			print('[DI] Failed opening "$configuredPath" -> in-memory fallback. Error: $e');
			return ShelterDatabase.open(':memory:');
		}
	});

	// Repositories
	getIt.registerLazySingleton<ShelterRepository>(() => ShelterRepositoryImpl(api: getIt(), db: getIt()));
	// Services
	getIt.registerLazySingleton<ShelterService>(() => ShelterService(repository: getIt()));
	// Controllers
	getIt.registerFactory<ShelterController>(() => ShelterController(service: getIt()));
}
