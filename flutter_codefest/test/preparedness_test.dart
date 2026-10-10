import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/preparedness.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';
import 'package:flutter_codefest/data/repositories/shelter_gateway.dart';
import 'package:flutter_codefest/domain/family_card.dart';
import 'package:flutter_codefest/domain/offline_query.dart';
import 'package:flutter_codefest/domain/shelter_links.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

OfflinePackage packageOf(
  List<Shelter> shelters, {
  DateTime? at,
  String? township,
}) => OfflinePackage(
  city: shelters.first.city,
  township: township,
  version: 'test-v1',
  downloadedAt: at ?? DateTime.utc(2026, 10, 10),
  shelters: shelters,
);

void main() {
  final a = fakeShelter(id: 1, name: '臺北Ａ館', lat: 25, lng: 121.5);
  final b = fakeShelter(
    id: 2,
    name: '遠方Ｂ館',
    lat: 25.1,
    lng: 121.5,
    flood: 'N',
    indoor: 'N',
    outdoor: 'Y',
  );
  group('durable preparedness library', () {
    test(
      'bookmarks, family summaries, settings and packages survive reopening',
      () async {
        String? disk;
        final store = PreparednessStore(
          read: () async => disk,
          write: (s) async => disk = s,
        );
        await store.load();
        await store.saveFavorite(a, group: '住家', note: '東側入口');
        await store.savePlan(
          FamilyPlan(primary: a, backup: b, contact: '家人 02-00000000'),
        );
        await store.savePackage(packageOf([a, b]));
        await store.settings(
          theme: ThemeMode.dark,
          offlineMode: true,
          listMode: true,
        );
        await store.removeFavorite(a.shelterId);
        final reopened = PreparednessStore(
          read: () async => disk,
          write: (s) async => disk = s,
        );
        await reopened.load();
        expect(reopened.favorites, isEmpty);
        expect(reopened.plan.primary!.name, a.name);
        expect(reopened.savedShelter(a.shelterId)!.name, a.name);
        expect(reopened.packages.single.shelters, hasLength(2));
        expect(reopened.offlineMode, true);
        expect(reopened.themeMode, ThemeMode.dark);
      },
    );

    test('quota failure retains the previous package and settings', () async {
      String? disk;
      var fail = false;
      final store = PreparednessStore(
        read: () async => disk,
        write: (s) async {
          if (fail) throw StateError('quota');
          disk = s;
        },
      );
      await store.load();
      await store.savePackage(packageOf([a]));
      final previous = disk;
      fail = true;
      await expectLater(store.savePackage(packageOf([b])), throwsStateError);
      expect(store.packages.single.shelters.single.name, a.name);
      expect(disk, previous);
      fail = false;
      await store.saveFavorite(a);
      expect(
        store.favorites,
        hasLength(1),
        reason: 'failed writes must not poison the queue',
      );
    });

    test('concurrent writes serialize without losing an edit', () async {
      final gate = Completer<void>();
      var writes = 0;
      final store = PreparednessStore(
        read: () async => null,
        write: (s) async {
          writes++;
          if (writes == 1) await gate.future;
        },
      );
      await store.load();
      final first = store.saveFavorite(a);
      final second = store.saveFavorite(b);
      await Future<void>.delayed(Duration.zero);
      expect(
        store.favorites,
        isEmpty,
        reason: 'do not publish before durable commit',
      );
      gate.complete();
      await Future.wait([first, second]);
      expect(store.favorites, hasLength(2));
    });

    test(
      'a corrupt/unsupported document is not silently overwritten',
      () async {
        var writes = 0;
        final store = PreparednessStore(
          read: () async => '{"schemaVersion":99}',
          write: (_) async {
            writes++;
          },
        );
        await store.load();
        expect(store.storageError, isNotNull);
        await expectLater(store.saveFavorite(a), throwsStateError);
        expect(writes, 0);
      },
    );

    test(
      'newer overlapping packages win and deleting the last exits offline mode',
      () async {
        final store = PreparednessStore(
          read: () async => null,
          write: (_) async {},
        );
        await store.load();
        final updated = fakeShelter(
          id: 99,
          shelterId: a.shelterId,
          name: '新名稱',
        );
        await store.savePackage(packageOf([a]));
        await store.savePackage(
          packageOf(
            [updated],
            township: a.district,
            at: DateTime.utc(2026, 10, 11),
          ),
        );
        expect(store.offlineShelters.single.name, '新名稱');
        await store.settings(offlineMode: true);
        for (final p in [...store.packages]) {
          await store.removePackage(p.key);
        }
        expect(store.offlineMode, false);
      },
    );
  });

  group('offline query and online fallback', () {
    test(
      'requeries new words, groups, regions and radii against stored rows',
      () {
        expect(queryOffline([a, b], {'q': '台北a'}).single.name, a.name);
        expect(
          queryOffline(
            [a, b],
            {'disasters': 'flood,tsunami', 'spaces': 'outdoor'},
          ),
          isEmpty,
        );
        expect(
          queryOffline(
            [a, b],
            {'disasters': 'flood,earthquake', 'spaces': 'outdoor'},
          ).single.name,
          b.name,
        );
        expect(queryOffline([a, b], {'city': '高雄市'}), isEmpty);
        expect(
          queryOffline(
            [b, a],
            {'lat': '25', 'lng': '121.5', 'radius': '1000'},
          ).single.name,
          a.name,
        );
      },
    );

    test('package validation rejects truncation, count and scope mismatch', () {
      final good = packageOf([a]).toJson();
      expect(OfflinePackage.fromJson(good).shelters, hasLength(1));
      for (final invalid in [
        {...good, 'truncated': true},
        {...good, 'total': 2},
        {
          ...good,
          'coverage': {'city': '高雄市'},
        },
        {...good, 'schemaVersion': 2},
      ]) {
        expect(() => OfflinePackage.fromJson(invalid), throwsFormatException);
      }
    });

    test(
      'forced offline never calls the API; network failure can fall back',
      () async {
        final store = PreparednessStore(
          read: () async => null,
          write: (_) async {},
        );
        await store.load();
        await store.savePackage(packageOf([a, b]));
        await store.settings(offlineMode: true);
        var calls = 0;
        final gateway = ShelterGateway(
          store,
          online: () => true,
          get: (path, {queryParams}) async {
            calls++;
            throw StateError('network down');
          },
        );
        final result = await gateway.page({'q': '台北a', 'limit': '50'});
        expect(result.dataFreshness, 'offline');
        expect(result.shelters.single.name, a.name);
        expect(calls, 0);
        expect((await gateway.clusters({'zoom': '13'})).clusters, isNotEmpty);
        await store.settings(offlineMode: false);
        expect(
          (await gateway.nearby(
            lat: 25,
            lng: 121.5,
            radiusMeters: 500,
          )).single.name,
          a.name,
        );
        expect(calls, 1);
      },
    );

    test(
      '404 does not resurrect a deleted source record as a fresh response',
      () async {
        final store = PreparednessStore(
          read: () async => null,
          write: (_) async {},
        );
        await store.load();
        await store.saveFavorite(a);
        final gateway = ShelterGateway(
          store,
          online: () => true,
          get: (path, {queryParams}) async => throw const ApiException(404),
        );
        await expectLater(
          gateway.detail(a.shelterId),
          throwsA(isA<ApiException>()),
        );
        expect(store.favorite(a.shelterId), isNotNull);
      },
    );
  });

  test(
    'share URL uses the source code without leaking search/GPS parameters',
    () {
      final link = shelterLink(
        a,
        base: Uri.parse('https://example.tw/app/?lat=25&lng=121&q=home#x'),
      );
      expect(link.queryParameters, {'shelter': a.shelterId});
      expect(link.fragment, '');
    },
  );

  test('printable card escapes user content and embeds QR graphics', () {
    final plan = FamilyPlan(
      title: '<script>alert(1)</script>',
      contact: '<img src=x onerror=alert(1)>',
      primary: a,
    );
    final html = familyPlanHtml(plan);
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;'));
    expect(html, isNot(contains('<img src=x')));
    expect(html, contains('<svg'));
    expect(html, contains('主要集合點'));
    expect(jsonEncode(plan.toJson()), isNotEmpty);
  });
}
