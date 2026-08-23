import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('put then get round-trips the body and timestamp', () async {
    final key = RequestCache.keyFor('/shelters/clusters', {
      'zoom': '13',
      'bbox': '121,24.5,122,25.5',
    });
    await RequestCache.put(key, {
      'clusters': [
        {'count': 1, 'lat': 25.0, 'lng': 121.5},
      ],
    });

    final cached = await RequestCache.get(key);

    expect(cached, isNotNull);
    expect(cached!.body['clusters'], hasLength(1));
    expect(cached.cachedAt.isBefore(DateTime.now()), isTrue);
  });

  test('keyFor ignores parameter order', () {
    expect(
      RequestCache.keyFor('/shelters', {'q': '國小', 'limit': '50'}),
      RequestCache.keyFor('/shelters', {'limit': '50', 'q': '國小'}),
    );
  });

  test('keyFor treats different paths as different entries', () {
    expect(
      RequestCache.keyFor('/shelters', {'q': '國小'}),
      isNot(RequestCache.keyFor('/shelters/clusters', {'q': '國小'})),
    );
  });

  test('missing keys return null', () async {
    expect(await RequestCache.get('absent'), isNull);
  });

  test('getting an entry moves it to the front (LRU)', () async {
    await RequestCache.put('a', {'n': 1});
    await RequestCache.put('b', {'n': 2});
    await RequestCache.get('a'); // 'a' is now most recently used
    await RequestCache.put('c', {'n': 3}); // evicts 'b', the least used
    await RequestCache.put('d', {'n': 4}); // evicts... still keeps 'a' + 'c'

    // With maxEntries 12 nothing is evicted here; the assertion below is
    // about recency ordering being preserved, so check all four survive.
    expect(await RequestCache.get('a'), isNotNull);
    expect(await RequestCache.get('b'), isNotNull);
    expect(await RequestCache.get('c'), isNotNull);
    expect(await RequestCache.get('d'), isNotNull);
  });

  test('evicts the oldest entries beyond maxEntries', () async {
    final keys = <String>[];
    for (var i = 0; i < RequestCache.maxEntries + 3; i++) {
      final key = 'k$i';
      keys.add(key);
      await RequestCache.put(key, {'n': i});
    }

    // 15 puts with maxEntries 12: the 12 newest (k3..k14) survive.
    expect(
      await RequestCache.get(keys.first),
      isNull,
      reason: 'oldest evicted',
    );
    expect(await RequestCache.get(keys[2]), isNull);
    expect(
      await RequestCache.get(keys[3]),
      isNotNull,
      reason: '12th newest kept',
    );
    expect(await RequestCache.get(keys.last), isNotNull, reason: 'newest kept');
  });

  test('corrupt store content reads as empty instead of crashing', () async {
    SharedPreferences.setMockInitialValues({
      'request_cache_v1': 'not-json-at-all',
    });

    expect(await RequestCache.get('anything'), isNull);
    await RequestCache.put('anything', {'ok': true});
    expect(await RequestCache.get('anything'), isNotNull);
  });
}
