import 'package:flutter/foundation.dart';
import 'package:flutter_codefest/data/models/region_coordinate_stats.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart'
    as repo;

typedef FetchShelterStats = Future<Map<String, dynamic>> Function();

/// Drives the data-quality page: which townships have the most shelters
/// still missing a coordinate, worst first.
class DataQualityViewModel extends ChangeNotifier {
  DataQualityViewModel({
    FetchShelterStats fetchShelterStats = repo.fetchShelterStats,
  }) : _fetchShelterStats = fetchShelterStats;

  final FetchShelterStats _fetchShelterStats;

  List<RegionCoordinateStats> _townships = const [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RegionCoordinateStats> get townships => _townships;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final stats = await _fetchShelterStats();
      _townships = RegionCoordinateStats.listFromStatsJson(stats);
    } catch (_) {
      _errorMessage = '無法載入資料品質統計,請確認網路連線';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
