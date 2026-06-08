import '../../domain/services/shelter_service.dart';

class ShelterStatsUseCase {
  final ShelterService service;
  ShelterStatsUseCase(this.service);

  Future<Map<String, dynamic>> execute({
    String? q,
    String? city,
    String? township,
    String? village,
    List<String>? villages,
    String? type,
    Map<String, String>? hazards,
    String matchMode = 'and',
    int maxItems = 2000,
  }) async {
    final list = await service.fetchAllSheltersPaged(q: q, maxItems: maxItems);
    return service.computeStats(
      data: list,
      city: city,
      township: township,
      village: village,
      villages: villages,
      type: type,
      hazards: hazards,
      keyword: q,
      matchMode: matchMode,
    );
  }
}
