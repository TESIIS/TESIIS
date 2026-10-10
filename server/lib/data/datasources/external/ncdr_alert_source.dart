import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/entities/disaster_alert.dart';
import '../../mappers/cap_alert_mapper.dart';

abstract interface class AlertSource {
  Future<AlertBatch> fetch();
}

class NcdrAlertSource implements AlertSource {
  NcdrAlertSource({
    required this.feedUri,
    http.Client? client,
    DateTime Function()? now,
    this.maxDocuments = 128,
    this.requestTimeout = const Duration(seconds: 5),
    this.refreshBudget = const Duration(seconds: 12),
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;
  final Uri feedUri;
  final http.Client _client;
  final DateTime Function() _now;
  final int maxDocuments;
  final Duration requestTimeout;
  final Duration refreshBudget;
  final Map<String, CapMessage?> _documents = {};

  Future<String> _download(Uri uri, int maxBytes, Duration timeout) async {
    final abort = Completer<void>();
    try {
      return await (() async {
        final request =
            http.AbortableRequest('GET', uri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['accept'] =
                  'application/atom+xml, application/cap+xml, application/xml, text/xml'
              ..headers['user-agent'] =
                  'TESIIS/2 (https://github.com/TESIIS/TESIIS)';
        final response = await _client.send(request);
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > maxBytes) {
          throw StateError('Alert upstream response rejected');
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw StateError('Alert response too large');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(timeout);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<AlertBatch> fetch() async {
    final watch = Stopwatch()..start();
    final now = _now().toUtc();
    final feed = CapAlertMapper.parseFeed(
      await _download(feedUri, 2 * 1024 * 1024, requestTimeout),
      feedUri,
    );
    final current = feed.entries
        .where(
          (e) =>
              e.messageType != 'Cancel' &&
              (e.expires == null || now.isBefore(e.expires!)),
        )
        .toList();
    // Expired updates/cancellations can retire a message that still appears
    // current in Atom. Fetch those controls back to the oldest current message.
    final cutoff = current.isEmpty
        ? now.subtract(const Duration(hours: 24))
        : current.map((e) => e.updated).reduce((a, b) => a.isBefore(b) ? a : b);
    final historyCutoff = now.subtract(const Duration(hours: 24));
    final relevant = feed.entries
        .where(
          (e) =>
              current.contains(e) ||
              !e.updated.isBefore(historyCutoff) ||
              (e.messageType != 'Alert' && !e.updated.isBefore(cutoff)),
        )
        .toList();
    // Current messages first; truncation is always disclosed, never silently
    // advertised as a complete list. Documents are immutable per ID + update.
    relevant.sort((a, b) {
      final active = (current.contains(b) ? 1 : 0).compareTo(
        current.contains(a) ? 1 : 0,
      );
      return active != 0 ? active : b.updated.compareTo(a.updated);
    });
    final selected = relevant.take(maxDocuments).toList();
    final messages = <CapMessage>[];
    var failures = feed.invalidEntries;
    var next = 0;
    Future<void> worker() async {
      while (next < selected.length) {
        final entry = selected[next++];
        final key =
            '${entry.url}|${entry.id}|${entry.updated.toIso8601String()}';
        if (_documents.containsKey(key)) {
          if (_documents[key] case final message?) {
            messages.add(message);
            if (message.invalidInfoCount > 0) failures++;
          }
          continue;
        }
        final remaining = refreshBudget - watch.elapsed;
        if (remaining <= Duration.zero) {
          failures++;
          continue;
        }
        try {
          final xml = await _download(
            entry.url,
            1024 * 1024,
            remaining < requestTimeout ? remaining : requestTimeout,
          );
          final message = CapAlertMapper.parseCap(xml, entry.url);
          if (message != null && message.identity.identifier != entry.id) {
            throw const FormatException('CAP/feed identity mismatch');
          }
          _documents[key] = message;
          if (message != null) {
            messages.add(message);
            if (message.invalidInfoCount > 0) failures++;
          }
        } catch (_) {
          failures++;
        }
      }
    }

    await Future.wait(List.generate(6, (_) => worker()));
    final keep = selected
        .map((e) => '${e.url}|${e.id}|${e.updated.toIso8601String()}')
        .toSet();
    _documents.removeWhere((key, _) => !keep.contains(key));
    if (messages.isEmpty && failures > 0) {
      throw StateError('No usable alert documents');
    }
    return AlertBatch(
      messages: messages,
      fetchedAt: _now().toUtc(),
      sourceUpdatedAt: feed.updatedAt,
      feedEntries: feed.entries.length,
      failedDocuments: failures,
      truncated: relevant.length > selected.length,
      omittedExpired: feed.entries.length - relevant.length,
    );
  }
}
