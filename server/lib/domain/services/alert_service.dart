import 'dart:async';

import '../../data/datasources/external/ncdr_alert_source.dart';
import '../entities/disaster_alert.dart';

class AlertService {
  AlertService({
    required AlertSource source,
    DateTime Function()? now,
    this.ttl = const Duration(minutes: 2),
    this.retryDelay = const Duration(seconds: 30),
  }) : _source = source,
       _now = now ?? DateTime.now;
  final AlertSource _source;
  final DateTime Function() _now;
  final Duration ttl;
  final Duration retryDelay;
  AlertBatch? _batch;
  Future<AlertBatch>? _inFlight;
  DateTime? _nextRefresh;
  bool _refreshFailed = false;

  Future<AlertBatch> _load() {
    if (_inFlight != null) return _inFlight!;
    if (_nextRefresh != null && _now().isBefore(_nextRefresh!)) {
      return _batch == null
          ? Future.error(StateError('Alert source unavailable'))
          : Future.value(_batch!);
    }
    final future = _refresh();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<AlertBatch> _refresh() async {
    try {
      final batch = await _source.fetch();
      _batch = batch;
      _refreshFailed = false;
      _nextRefresh = _now().add(batch.partial ? retryDelay : ttl);
      return batch;
    } catch (_) {
      _refreshFailed = true;
      _nextRefresh = _now().add(retryDelay);
      if (_batch != null) return _batch!;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> query({
    String? city,
    String? township,
    bool includeHistory = false,
    int limit = 200,
  }) async {
    final batch = await _load();
    final now = _now().toUtc();
    final messages = {for (final m in batch.messages) m.key: m};
    final retired = <String, String>{};
    final controls =
        messages.values
            .where(
              (m) => m.messageType != 'Alert' && !m.identity.sent.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.identity.sent.compareTo(b.identity.sent));
    for (final control in controls) {
      final seen = <String>{control.key};
      void retire(CapReference ref) {
        if (!seen.add(ref.key) || ref.sent.isAfter(control.identity.sent)) {
          return;
        }
        retired[ref.key] = control.messageType == 'Cancel'
            ? 'cancelled'
            : 'superseded';
        final previous = messages[ref.key];
        if (previous != null) {
          for (final ancestor in previous.references) {
            retire(ancestor);
          }
        }
      }

      for (final ref in control.references) {
        retire(ref);
      }
    }
    final rows = <Map<String, dynamic>>[];
    var unknownRegionCount = 0;
    for (final message in messages.values) {
      var infos = message.infos;
      // CAP permits a cancellation without info. Carry the referenced areas
      // solely to make that cancellation findable in regional history.
      if (infos.isEmpty && message.messageType == 'Cancel') {
        infos = [
          for (final ref in message.references) ...?messages[ref.key]?.infos,
        ];
      }
      for (var i = 0; i < infos.length; i++) {
        final info = infos[i];
        final state =
            retired[message.key] ??
            (message.messageType == 'Cancel'
                ? 'cancelled'
                : info.temporalState(now));
        if (!includeHistory &&
            {'expired', 'cancelled', 'superseded'}.contains(state)) {
          continue;
        }
        if (info.regions.isEmpty) unknownRegionCount++;
        final matches = info.regions
            .where(
              (r) =>
                  (city == null || r.city == city) &&
                  (township == null ||
                      r.township == null ||
                      r.township == township),
            )
            .toList();
        if (city != null && matches.isEmpty) continue;
        rows.add({
          'id': '${message.key}#$i',
          'messageId': message.identity.identifier,
          'event': info.event,
          'headline': message.infos.isEmpty
              ? '${info.headline}（解除公告）'
              : info.headline,
          'description': message.infos.isEmpty
              ? '發布單位已解除引用的公告。詳情請開啟原始 CAP 公告。'
              : info.description,
          'instruction': message.infos.isEmpty ? '' : info.instruction,
          'senderName': info.senderName,
          'messageType': message.messageType,
          'state': state,
          'sentAt': message.identity.sent.toIso8601String(),
          'effectiveAt':
              (message.infos.isEmpty ? message.identity.sent : info.effective)
                  .toIso8601String(),
          'expiresAt': message.infos.isEmpty
              ? null
              : info.expires?.toIso8601String(),
          'severity': info.severity,
          'urgency': info.urgency,
          'certainty': info.certainty,
          'areas': info.areas,
          'regions': info.regions.map((r) => r.toJson()).toList(),
          'regionMatch': city == null
              ? 'all'
              : township != null && !matches.any((r) => r.township == township)
              ? 'city'
              : 'exact',
          'sourceUrl': message.sourceUrl.toString(),
          'webUrl': info.web?.toString(),
        });
      }
    }
    rows.sort(
      (a, b) => (b['sentAt'] as String).compareTo(a['sentAt'] as String),
    );
    return {
      'success': true,
      'available': true,
      'source': 'NCDR 民生示警公開資料平台',
      'sourceUrl': 'https://alerts.ncdr.nat.gov.tw/',
      'freshness': _refreshFailed
          ? 'stale'
          : batch.partial
          ? 'partial'
          : 'fresh',
      'fetchedAt': batch.fetchedAt.toIso8601String(),
      'sourceUpdatedAt': batch.sourceUpdatedAt?.toIso8601String(),
      'asOf': now.toIso8601String(),
      'refreshAfterSeconds': ttl.inSeconds,
      'partial': batch.partial,
      'failedDocuments': batch.failedDocuments,
      'sourceTruncated': batch.truncated,
      'feedEntries': batch.feedEntries,
      'omittedExpired': batch.omittedExpired,
      'unknownRegionCount': unknownRegionCount,
      'filters': {
        'city': city,
        'township': township,
        'history': includeHistory,
      },
      'data': rows.take(limit).toList(),
      'total': rows.length,
      'truncated': rows.length > limit,
    };
  }
}
