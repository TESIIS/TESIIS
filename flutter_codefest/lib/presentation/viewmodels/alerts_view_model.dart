import 'package:flutter/foundation.dart';
import 'package:flutter_codefest/data/models/disaster_alert.dart';

typedef FetchAlerts =
    Future<AlertFeed> Function({
      AlertRegion? region,
      bool history,
      bool offline,
    });

class AlertsViewModel extends ChangeNotifier {
  AlertsViewModel({
    required FetchAlerts fetch,
    this.region,
    DateTime Function()? now,
  }) : _fetch = fetch,
       _now = now ?? DateTime.now;
  final FetchAlerts _fetch;
  final DateTime Function() _now;
  AlertRegion? region;
  bool history = false;
  bool loading = false;
  bool refreshFailed = false;
  String? error;
  AlertFeed? feed;
  DateTime? lastAttempt;
  int _request = 0;
  bool _disposed = false;
  DateTime get now => _now();
  bool get verified => !refreshFailed && (feed?.verifiedAt(now) ?? false);
  List<DisasterAlert> get visible =>
      feed?.alerts.where((a) => history || a.isCurrent(now)).toList() ?? [];
  String get emptyMessage => feed == null
      ? '目前無法取得警報資料'
      : !verified
      ? '目前資料無法確認是否有新的公告，請連線更新或查看官方平台。'
      : '本次來源清單沒有符合條件的公告。';

  Future<void> load({bool offline = false}) async {
    if (_disposed) return;
    final request = ++_request;
    loading = true;
    error = null;
    lastAttempt = now;
    notifyListeners();
    try {
      final result = await _fetch(
        region: region,
        history: history,
        offline: offline,
      );
      if (request != _request || _disposed) return;
      feed = result;
      refreshFailed = false;
    } catch (_) {
      if (request != _request || _disposed) return;
      refreshFailed = true;
      error = feed == null
          ? '目前無法取得警報資料，請重試或查看官方平台。'
          : '更新失敗，以下保留先前資料，最新狀態待確認。';
    } finally {
      if (request == _request && !_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectRegion(AlertRegion? value, {bool offline = false}) {
    region = value;
    feed = null;
    return load(offline: offline);
  }

  Future<void> setHistory(bool value, {bool offline = false}) {
    history = value;
    feed = null;
    return load(offline: offline);
  }

  void tick() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
