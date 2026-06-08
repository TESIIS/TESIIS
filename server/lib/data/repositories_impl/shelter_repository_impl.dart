import '../../domain/entities/shelter.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../datasources/external/shelter_api.dart';
import '../datasources/database/shelter_database.dart';
import '../models/shelter_model.dart';

class ShelterRepositoryImpl implements ShelterRepository {
  final ShelterApi api;
  final ShelterDatabase db;

  ShelterRepositoryImpl({required this.api, required this.db});

  // Removed old per-row extraction helper (no longer needed with prebuilt index)

  Shelter _buildEntityFromModel(ShelterModel m) {
    double? x = m.x;
    double? y = m.y;
    if ((x == null || y == null) && m.address.isNotEmpty) {
      final hit = db.lookupAddress(m.address);
      if (hit != null) {
        x = x ?? hit.$1;
        y = y ?? hit.$2;
      }
    }
    return Shelter(
      id: m.id,
      importDate: m.importDate,
      shelterCode: m.shelterCode,
      name: m.name,
      city: m.city,
      zipcode: m.zipcode,
      township: m.township,
      village: m.village,
      address: m.address,
      type: m.type,
      flood: m.flood,
      quake: m.quake,
      landslide: m.landslide,
      tsunami: m.tsunami,
      relief: m.relief,
      accessible: m.accessible,
      indoor: m.indoor,
      outdoor: m.outdoor,
      serviceVillages: m.serviceVillages,
      capacity: m.capacity,
      area: m.area,
      contactName: m.contactName,
      contactPhone: m.contactPhone,
      managerName: m.managerName,
      managerPhone: m.managerPhone,
      notes: m.notes,
      x: x,
      y: y,
    );
  }

  @override
  Future<List<Shelter>> getShelters({String? q, int limit = 1000, int offset = 0}) async {
    // Ensure index built once before mapping
    db.buildAddressIndex();
    final models = await api.fetchShelters(q: q, limit: limit, offset: offset);
    return models.map((m) => _buildEntityFromModel(m)).toList();
  }

  @override
  Future<List<Shelter>> getAllShelters({String? q, int maxItems = 2000}) async {
    db.buildAddressIndex();
    final models = await api.fetchAllShelters(q: q, maxItems: maxItems);
    return models.map((m) => _buildEntityFromModel(m)).toList();
  }
}
