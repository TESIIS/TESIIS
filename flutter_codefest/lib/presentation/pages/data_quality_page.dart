import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/data/models/region_coordinate_stats.dart';
import 'package:flutter_codefest/presentation/viewmodels/data_quality_view_model.dart';

/// Shows which townships have the most avalanche-of-missing-座標 shelters, so
/// anyone touching the coordinate pipeline can see where the gaps actually
/// are instead of only the dataset-wide percentage.
class DataQualityPage extends StatefulWidget {
  const DataQualityPage({super.key});

  @override
  State<DataQualityPage> createState() => _DataQualityPageState();
}

class _DataQualityPageState extends State<DataQualityPage> {
  late final DataQualityViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DataQualityViewModel();
    _viewModel.load();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '座標資料品質',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.primary,
        iconTheme: IconThemeData(color: colorScheme.onPrimary),
        elevation: 0,
      ),
      body: Container(
        color: colorScheme.surfaceContainerLowest,
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.errorMessage != null) {
      return Center(child: Text(_viewModel.errorMessage!));
    }
    if (_viewModel.townships.isEmpty) {
      return const Center(child: Text('沒有資料'));
    }

    final isDesktop =
        MediaQuery.sizeOf(context).width >= MapConstants.desktopBreakpoint;
    final townships = _viewModel.filteredTownships;

    return Column(
      children: [
        _CityFilterBar(
          cities: _viewModel.cities,
          selectedCity: _viewModel.selectedCity,
          onSelect: _viewModel.selectCity,
        ),
        Expanded(
          child: townships.isEmpty
              ? const Center(child: Text('這個縣市沒有資料'))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: isDesktop
                        ? _buildGrid(townships)
                        : _buildList(townships),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildList(List<RegionCoordinateStats> townships) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: townships.length,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _TownshipTile(stats: townships[index]),
    );
  }

  Widget _buildGrid(List<RegionCoordinateStats> townships) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 108,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: townships.length,
      itemBuilder: (context, index) => _TownshipTile(stats: townships[index]),
    );
  }
}

/// City picker for the data-quality page — a wrapping row of choice chips
/// rather than `FilterChipBar`'s horizontal scroller, since there are ~20+
/// counties/cities and wrapping reads better than a long scroll on desktop.
class _CityFilterBar extends StatelessWidget {
  const _CityFilterBar({
    required this.cities,
    required this.selectedCity,
    required this.onSelect,
  });

  final List<String> cities;
  final String? selectedCity;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: colorScheme.surface,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: selectedCity == null,
            onSelected: (_) => onSelect(null),
          ),
          for (final city in cities)
            ChoiceChip(
              label: Text(city),
              selected: selectedCity == city,
              onSelected: (_) => onSelect(selectedCity == city ? null : city),
            ),
        ],
      ),
    );
  }
}

class _TownshipTile extends StatelessWidget {
  const _TownshipTile({required this.stats});

  final RegionCoordinateStats stats;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final missingRatio = stats.total == 0 ? 0.0 : stats.missing / stats.total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${stats.city} ${stats.township}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              _CountBadge(
                label: '缺座標',
                count: stats.missing,
                color: stats.missing == 0
                    ? colorScheme.primary
                    : colorScheme.error,
              ),
              const SizedBox(width: 8),
              _CountBadge(
                label: '共',
                count: stats.total,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: missingRatio,
              minHeight: 6,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $count',
      style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
    );
  }
}
