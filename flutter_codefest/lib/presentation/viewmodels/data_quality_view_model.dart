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
  List<String> _cities = const [];
  String? _selectedCity;
  bool _isLoading = false;
  String? _errorMessage;

  List<RegionCoordinateStats> get townships => _townships;

  /// [townships] narrowed to [selectedCity], or everything when no city is
  /// selected.
  List<RegionCoordinateStats> get filteredTownships => _selectedCity == null
      ? _townships
      : _townships.where((t) => t.city == _selectedCity).toList();

  /// Cities in the order the server returned them (roughly administrative
  /// order), not re-sorted alphabetically by Chinese name.
  List<String> get cities => _cities;
  String? get selectedCity => _selectedCity;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void selectCity(String? city) {
    if (_selectedCity == city) return;
    _selectedCity = city;
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final stats = await _fetchShelterStats();
      _townships = RegionCoordinateStats.listFromStatsJson(stats);
      final byRegion = stats['byRegion'] as List<dynamic>? ?? const [];
      _cities = [
        for (final cityEntry in byRegion.cast<Map<String, dynamic>>())
          cityEntry['city'] as String,
      ];
    } catch (_) {
      _errorMessage = '無法載入資料品質統計,請確認網路連線';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
