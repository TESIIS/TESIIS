import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/theme/app_theme.dart';
import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_codefest/data/models/disaster_alert.dart';
import 'package:flutter_codefest/data/repositories/alerts_repository.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';
import 'package:flutter_codefest/data/repositories/shelter_gateway.dart';
import 'package:flutter_codefest/presentation/pages/alerts_page.dart';
import 'package:flutter_codefest/presentation/viewmodels/alerts_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 10, 8, 30);
Map<String, dynamic> _item({
  String id = 'A',
  String state = 'active',
  String? expires = '2026-10-10T09:00:00Z',
}) => {
  'id': id,
  'headline': '測試降雨公告',
  'event': '降雨',
  'state': state,
  'senderName': '測試發布單位',
  'description': '測試內容',
  'instruction': '測試說明',
  'sentAt': '2026-10-10T08:00:00Z',
  'effectiveAt': '2026-10-10T08:00:00Z',
  'expiresAt': expires,
  'severity': 'Severe',
  'regions': [
    {'city': '臺北市', 'township': '中正區'},
  ],
  'areas': ['臺北市中正區'],
  'sourceUrl': 'https://alerts.ncdr.nat.gov.tw/Capstorage/test.cap',
};
Map<String, dynamic> _body({
  List<Map<String, dynamic>>? data,
  String freshness = 'fresh',
  bool partial = false,
}) => {
  'available': true,
  'data': data ?? [_item()],
  'freshness': freshness,
  'partial': partial,
  'fetchedAt': _now.toIso8601String(),
  'sourceUpdatedAt': _now.toIso8601String(),
  'refreshAfterSeconds': 120,
  'unknownRegionCount': 0,
  'total': data?.length ?? 1,
  'truncated': false,
};

void main() {
  test('expiry advances on the client, terminal states do not resurrect', () {
    final alert = DisasterAlert.fromJson(_item());
    expect(alert.stateAt(_now), 'active');
    expect(alert.stateAt(DateTime.utc(2026, 10, 10, 9)), 'expired');
    expect(
      DisasterAlert.fromJson(_item(state: 'cancelled')).stateAt(_now),
      'cancelled',
    );
    expect(
      DisasterAlert.fromJson(_item(expires: null)).stateAt(_now),
      'unknown',
    );
    expect(alert.statusLabel(_now, verified: false), '最新狀態待確認');
  });
  test(
    'device cache, partial results, server stale and overdue fetches are unverified',
    () {
      expect(AlertFeed.fromJson(_body()).verifiedAt(_now), true);
      expect(
        AlertFeed.fromJson(_body(), deviceCache: true).verifiedAt(_now),
        false,
      );
      expect(AlertFeed.fromJson(_body(partial: true)).verifiedAt(_now), false);
      expect(
        AlertFeed.fromJson(_body(freshness: 'stale')).verifiedAt(_now),
        false,
      );
      expect(
        AlertFeed.fromJson(
          _body(),
        ).verifiedAt(_now.add(const Duration(minutes: 3))),
        false,
      );
      expect(alertTime(DateTime.utc(2026, 12, 31, 17)), '2027/01/01 01:00');
    },
  );
  test(
    'repository uses only the exact cached scope and does not refresh its original timestamp',
    () async {
      final cache = <String, Map<String, dynamic>>{};
      var online = true;
      var calls = 0;
      final repository = AlertsRepository(
        online: () => online,
        get: (path, {queryParams}) async {
          calls++;
          return _body();
        },
        cacheGet: (key) async => cache[key] == null
            ? null
            : CachedResponse(body: cache[key]!, cachedAt: _now),
        cachePut: (key, body) async {
          cache[key] = body;
        },
      );
      await repository.fetch(region: const AlertRegion('臺北市'));
      online = false;
      final restored = await repository.fetch(region: const AlertRegion('臺北市'));
      expect(restored.deviceCache, true);
      expect(restored.fetchedAt, _now);
      expect(calls, 1);
      await expectLater(
        repository.fetch(region: const AlertRegion('高雄市')),
        throwsStateError,
      );
      await expectLater(
        repository.fetch(region: const AlertRegion('臺北市'), history: true),
        throwsStateError,
      );
    },
  );
  test(
    'storage failure does not discard a successful response; bad queries do not use cache',
    () async {
      final repository = AlertsRepository(
        online: () => true,
        get: (path, {queryParams}) async => _body(),
        cacheGet: (_) async => null,
        cachePut: (_, _) async => throw StateError('quota'),
      );
      expect((await repository.fetch()).alerts, hasLength(1));
      var readCache = false;
      final invalid = AlertsRepository(
        online: () => true,
        get: (path, {queryParams}) async => throw const ApiException(400),
        cacheGet: (_) async {
          readCache = true;
          return null;
        },
      );
      await expectLater(invalid.fetch(), throwsA(isA<ApiException>()));
      expect(readCache, false);
    },
  );
  test(
    'out-of-order regional responses cannot replace the newly selected region',
    () async {
      final old = Completer<AlertFeed>();
      final vm = AlertsViewModel(
        now: () => _now,
        fetch: ({region, history = false, offline = false}) =>
            region?.city == '臺北市'
            ? old.future
            : Future.value(AlertFeed.fromJson(_body(data: []))),
      );
      final first = vm.selectRegion(const AlertRegion('臺北市'));
      await vm.selectRegion(const AlertRegion('高雄市'));
      old.complete(AlertFeed.fromJson(_body()));
      await first;
      expect(vm.region!.city, '高雄市');
      expect(vm.visible, isEmpty);
      vm.dispose();
    },
  );
  test(
    'refresh failure keeps old content but cannot claim it is current',
    () async {
      var fail = false;
      final vm = AlertsViewModel(
        now: () => _now,
        fetch: ({region, history = false, offline = false}) async {
          if (fail) throw StateError('network');
          return AlertFeed.fromJson(_body());
        },
      );
      await vm.load();
      expect(vm.verified, true);
      fail = true;
      await vm.load();
      expect(vm.visible, hasLength(1));
      expect(vm.verified, false);
      expect(vm.error, contains('最新狀態待確認'));
      vm.dispose();
    },
  );
  test(
    'a successful empty feed differs from unavailable and stale empty data',
    () async {
      final fresh = AlertsViewModel(
        now: () => _now,
        fetch: ({region, history = false, offline = false}) async =>
            AlertFeed.fromJson(_body(data: [])),
      );
      await fresh.load();
      expect(fresh.emptyMessage, '本次來源清單沒有符合條件的公告。');
      final offline = AlertsViewModel(
        now: () => _now,
        fetch: ({region, history = false, offline = false}) async =>
            AlertFeed.fromJson(_body(data: []), deviceCache: true),
      );
      await offline.load();
      expect(offline.emptyMessage, contains('無法確認'));
      fresh.dispose();
      offline.dispose();
    },
  );
  test(
    'followed regions survive reopening without changing family data',
    () async {
      String? disk;
      final store = PreparednessStore(
        read: () async => disk,
        write: (value) async {
          disk = value;
        },
      );
      await store.load();
      await store.followAlertRegion(const AlertRegion('臺北市', '中正區'));
      await store.followAlertRegion(const AlertRegion('臺北市', '中正區'));
      final reopened = PreparednessStore(
        read: () async => disk,
        write: (_) async {},
      );
      await reopened.load();
      expect(reopened.alertRegions.single.key, '臺北市|中正區');
      await reopened.unfollowAlertRegion(const AlertRegion('臺北市', '中正區'));
      expect(reopened.alertRegions, isEmpty);
    },
  );
  testWidgets(
    'unavailable page shows retry/source instead of a no-alert message',
    (tester) async {
      final store = PreparednessStore(
        read: () async => null,
        write: (_) async {},
      );
      await store.load();
      var attempts = 0;
      final repository = AlertsRepository(
        online: () => false,
        cacheGet: (_) async {
          attempts++;
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AlertsPage(
            store: store,
            gateway: ShelterGateway(store),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('目前無法取得警報資料，請重試或查看官方平台。'), findsOneWidget);
      expect(find.text('本次來源清單沒有符合條件的公告。'), findsNothing);
      expect(attempts, 1);
      await tester.tap(find.byTooltip('重新整理警報'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
