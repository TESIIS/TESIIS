import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/theme/app_status_colors.dart';
import 'package:flutter_codefest/data/models/disaster_alert.dart';
import 'package:flutter_codefest/data/repositories/alerts_repository.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';
import 'package:flutter_codefest/data/repositories/shelter_gateway.dart';
import 'package:flutter_codefest/presentation/pages/preparedness_page.dart';
import 'package:flutter_codefest/presentation/viewmodels/alerts_view_model.dart';
import 'package:flutter_codefest/presentation/widgets/common/status_banner.dart';
import 'package:flutter_codefest/presentation/widgets/search/region_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.store,
    required this.gateway,
    this.initialRegion,
    this.repository,
  });
  final PreparednessStore store;
  final ShelterGateway gateway;
  final AlertRegion? initialRegion;
  final AlertsRepository? repository;
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with WidgetsBindingObserver {
  late final AlertsViewModel _vm;
  Timer? _timer;
  bool _foreground = true;
  static final _officialSite = Uri.parse('https://alerts.ncdr.nat.gov.tw/');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vm = AlertsViewModel(
      fetch: (widget.repository ?? AlertsRepository()).fetch,
      region: widget.initialRegion ?? widget.store.alertRegions.firstOrNull,
    );
    widget.store.addListener(_storeChanged);
    unawaited(_refresh());
    // Time continues moving while the page is open, even when offline. The
    // server snapshot's "active" label is never treated as a permanent state.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_foreground) return;
      _vm.tick();
      final last = _vm.lastAttempt;
      if (!_vm.loading &&
          last != null &&
          _vm.now.difference(last) >= const Duration(minutes: 2)) {
        unawaited(_refresh());
      }
    });
  }

  void _storeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() => _vm.load(offline: widget.store.offlineMode);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _vm.tick();
      if (!_vm.loading) unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_storeChanged);
    _vm.dispose();
    super.dispose();
  }

  Future<void> _chooseScope() async {
    final choice = await pickRegion(
      context,
      widget.gateway,
      city: _vm.region?.city,
      township: _vm.region?.township,
      forAlerts: true,
    );
    if (!mounted || choice == null) return;
    await _vm.selectRegion(
      choice.city == null ? null : AlertRegion(choice.city!, choice.township),
      offline: widget.store.offlineMode,
    );
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
        throw StateError('Cannot open URL');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟來源連結，請稍後再試')));
      }
    }
  }

  Future<void> _shelters(DisasterAlert alert) async {
    final scope = _vm.region;
    final regions = alert.regions
        .where((r) => scope == null || r.city == scope.city)
        .toList();
    if (regions.isEmpty) return;
    AlertRegion? selected;
    if (scope?.township != null &&
        regions.any(
          (r) => r.township == null || r.township == scope!.township,
        )) {
      selected = scope;
    } else if (regions.length == 1) {
      selected = regions.single;
    } else {
      selected = await showModalBottomSheet<AlertRegion>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('選擇要查詢避難所的行政區'),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: regions.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(regions[i].label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, regions[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (selected != null && mounted) Navigator.pop(context, selected);
  }

  Widget _metadata(AlertFeed feed) {
    final message =
        _vm.error ??
        (feed.deviceCache
            ? '裝置快取：目前無法取得新公告，以下資料的最新狀態待確認。'
            : feed.freshness == 'stale'
            ? '來源更新失敗，顯示伺服器先前取得的公告。最新狀態待確認。'
            : feed.partial || feed.freshness == 'partial'
            ? '部分公告未能完整取得或解析，這份清單可能不完整。'
            : !_vm.verified
            ? '距離上次取得資料已超過更新間隔，請重新整理以確認最新狀態。'
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message != null)
          StatusBanner(
            tone: StatusTone.info,
            icon: Icons.history,
            message: message,
          ),
        Text('資料取得：${alertTime(feed.fetchedAt)}'),
        Text('來源清單更新：${alertTime(feed.sourceUpdatedAt)}'),
        const Text('時間為臺灣時間（UTC+8）；頁面開啟時約每兩分鐘更新。'),
        if (feed.unknownRegionCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '另有 ${feed.unknownRegionCount} 筆公告未能比對行政區，可切換「全國」查看原始範圍。',
            ),
          ),
        if (feed.truncated)
          Text('此次回傳前 ${feed.alerts.length} 筆／共 ${feed.total} 筆，完整內容請見官方平台。'),
      ],
    );
  }

  Widget _alertCard(DisasterAlert alert) {
    final scheme = Theme.of(context).colorScheme;
    final state = alert.stateAt(_vm.now);
    final historical = !alert.isCurrent(_vm.now);
    final tone = historical || !_vm.verified
        ? scheme.onSurfaceVariant
        : (alert.severity == 'Extreme' || alert.severity == 'Severe')
        ? scheme.error
        : scheme.primary;
    return Card(
      key: ValueKey(alert.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(
                    alert.statusLabel(_vm.now, verified: _vm.verified),
                  ),
                  avatar: Icon(
                    historical ? Icons.history : Icons.info_outline,
                    size: 18,
                    color: tone,
                  ),
                ),
                Text(alert.severityLabel, style: TextStyle(color: tone)),
                if (state == 'unknown' && !_vm.verified) const Text('來源未提供期限'),
              ],
            ),
            Text(
              alert.headline.isEmpty ? alert.event : alert.headline,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text('${alert.senderName} · ${alert.event}'),
            Text('發布：${alertTime(alert.sentAt)}'),
            Text(
              '生效：${alertTime(alert.effectiveAt)}　到期：${alertTime(alert.expiresAt)}',
            ),
            const SizedBox(height: 8),
            Text(
              alert.areas.isEmpty
                  ? '公告未提供可顯示的範圍說明'
                  : '${alert.areas.take(3).join('、')}${alert.areas.length > 3 ? '…（共 ${alert.areas.length} 個範圍）' : ''}',
            ),
            if (alert.regionMatch == 'city')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('此筆僅能比對到縣市，是否涉及所選鄉鎮請依公告範圍確認。'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: const Text('公告內容與發布單位說明'),
              children: [
                if (alert.description.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(alert.description),
                  ),
                if (alert.instruction.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText('發布單位說明：\n${alert.instruction}'),
                    ),
                  ),
                if (alert.areas.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('完整範圍：${alert.areas.join('、')}'),
                    ),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (alert.webUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _open(alert.webUrl!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('官方說明'),
                  ),
                if (alert.sourceUrl != null)
                  TextButton(
                    onPressed: () => _open(alert.sourceUrl!),
                    child: const Text('原始 CAP 公告'),
                  ),
                if (alert.regions.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _shelters(alert),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('查詢此區避難所'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('區域災害警報'),
      actions: [
        ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => IconButton(
            tooltip: '重新整理警報',
            onPressed: _vm.loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final region = _vm.region;
        final following =
            region != null &&
            widget.store.alertRegions.any((r) => r.key == region.key);
        final alerts = _vm.visible;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text('資料來源：NCDR 民生示警公開資料平台。各公告保留原發布單位、有效時間及來源連結。'),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseScope,
                    icon: const Icon(Icons.tune),
                    label: Text(region?.label ?? '全國'),
                  ),
                  if (region != null)
                    TextButton.icon(
                      onPressed:
                          !following && widget.store.alertRegions.length >= 8
                          ? null
                          : () => saveAction(
                              context,
                              () => following
                                  ? widget.store.unfollowAlertRegion(region)
                                  : widget.store.followAlertRegion(region),
                              message: following ? '已取消關注區域' : '已保存關注區域',
                            ),
                      icon: Icon(
                        following ? Icons.bookmark : Icons.bookmark_outline,
                      ),
                      label: Text(
                        following
                            ? '取消關注'
                            : widget.store.alertRegions.length >= 8
                            ? '已達 8 個關注區域'
                            : '關注這個區域',
                      ),
                    ),
                  if (region != null)
                    TextButton(
                      onPressed: () => _vm.selectRegion(
                        null,
                        offline: widget.store.offlineMode,
                      ),
                      child: const Text('查看全國'),
                    ),
                ],
              ),
              if (widget.store.alertRegions.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in widget.store.alertRegions)
                      InputChip(
                        label: Text(r.label),
                        selected: region?.key == r.key,
                        onPressed: () => _vm.selectRegion(
                          r,
                          offline: widget.store.offlineMode,
                        ),
                        onDeleted: () => saveAction(
                          context,
                          () => widget.store.unfollowAlertRegion(r),
                        ),
                        deleteButtonTooltipMessage: '取消關注 ${r.label}',
                      ),
                  ],
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('包含近期歷史公告'),
                subtitle: const Text('顯示已解除、已更新與到期的公告；歷史範圍以來源清單及近期資料為限。'),
                value: _vm.history,
                onChanged: (value) =>
                    _vm.setHistory(value, offline: widget.store.offlineMode),
              ),
              if (_vm.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(semanticsLabel: '正在取得警報資料'),
                ),
              if (_vm.feed case final feed?) _metadata(feed),
              if (!_vm.loading && _vm.feed == null)
                StatusBanner(
                  tone: StatusTone.info,
                  icon: Icons.cloud_off,
                  message: _vm.error ?? _vm.emptyMessage,
                ),
              const SizedBox(height: 12),
              if (!_vm.loading && alerts.isEmpty && _vm.feed != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_vm.emptyMessage),
                ),
              for (final alert in alerts) _alertCard(alert),
              TextButton.icon(
                onPressed: () => _open(_officialSite),
                icon: const Icon(Icons.open_in_new),
                label: const Text('前往 NCDR 官方平台'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
