import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/csv/csv_codec.dart';
import '../../../core/errors/app_exception.dart';

/// Reads 消防署避難收容處所點位檔, the nationwide shelter point file.
///
/// Unlike Taipei OpenData (`ShelterApi`), this is a single CSV download with
/// no pagination and already carries 經度/緯度 — see `NfaShelterMapper` for
/// how a row becomes a `Shelter`.
class NfaShelterApi {
  NfaShelterApi({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? Env.upstreamTimeout;

  final http.Client _client;
  final Duration _timeout;

  Future<List<Map<String, String>>> fetchRawRows() async {
    final uri = Uri.parse(Env.nfaPointFileUrl);
    // Bounded on purpose: a hang here is worse than a failure, because the
    // repository's fallback to cached/snapshot data lives in a catch clause
    // that an unresolved future never reaches.
    final resp = await _client
        .get(uri)
        .timeout(
          _timeout,
          onTimeout: () => throw ServerException(
            'NFA point file timed out after ${_timeout.inSeconds}s',
          ),
        );

    if (resp.statusCode != 200) {
      throw ServerException(
        'Failed to load NFA point file: ${resp.statusCode}',
      );
    }

    // The export is UTF-8 but doesn't always say so in Content-Type, which
    // would make the http package fall back to latin-1 and mangle 中文.
    final body = utf8.decode(resp.bodyBytes);
    return parseCsvAsMaps(body);
  }
}
