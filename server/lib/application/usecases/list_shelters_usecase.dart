import '../../domain/services/shelter_service.dart';
import '../../domain/entities/shelter.dart';

class ListSheltersUseCase {
  final ShelterService service;
  ListSheltersUseCase(this.service);

  Future<List<Shelter>> execute({
    String? q,
    String? city,
    String? township,
    String? village,
    List<String>? villages,
    String? type,
    Map<String, String>? hazards,
    String matchMode = 'and',
    int maxItems = 3000,
  }) async {
    final all = await service.fetchAllSheltersPaged(q: q, maxItems: maxItems);
    return service.filterShelters(
      data: all,
      city: city,
      township: township,
      village: village,
      villages: villages,
      type: type,
      keyword: q,
      hazards: hazards,
      matchMode: matchMode,
    );
  }
}
