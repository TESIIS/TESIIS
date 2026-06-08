import '../entities/shelter.dart';

abstract class ShelterRepository {
  Future<List<Shelter>> getShelters({String? q, int limit = 1000, int offset = 0});
  Future<List<Shelter>> getAllShelters({String? q, int maxItems = 2000});
}
