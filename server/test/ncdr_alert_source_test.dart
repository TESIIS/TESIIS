import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/data/datasources/external/ncdr_alert_source.dart';
import 'package:test/test.dart';

import 'support/alert_fixtures.dart';

http.Response xmlResponse(String text) => http.Response.bytes(
  utf8.encode(text),
  200,
  headers: {'content-type': 'application/xml; charset=utf-8'},
);

void main() {
  final feedUri = Uri.parse('https://alerts.example/feed');
  test(
    'fetches CAP files with bounded fanout and reuses immutable documents',
    () async {
      var docs = 0;
      var feedCalls = 0;
      final source = NcdrAlertSource(
        feedUri: feedUri,
        now: () => alertNow,
        client: MockClient((request) async {
          if (request.url.path == '/feed') {
            feedCalls++;
            return xmlResponse(atomFeed(atomEntry()));
          }
          docs++;
          return xmlResponse(capXml());
        }),
      );
      expect((await source.fetch()).messages, hasLength(1));
      await source.fetch();
      expect(feedCalls, 2);
      expect(docs, 1);
    },
  );
  test(
    'an expired cancel is still downloaded if it can retire a current alert',
    () async {
      final paths = <String>[];
      final source = NcdrAlertSource(
        feedUri: feedUri,
        now: () => alertNow,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/feed') {
            return xmlResponse(
              atomFeed(
                atomEntry() +
                    atomEntry(
                      id: 'C',
                      type: 'Cancel',
                      updated: '2026-10-10T08:10:00Z',
                      expires: '2026/10/10 下午 04:15:00',
                    ),
              ),
            );
          }
          return xmlResponse(
            request.url.path.endsWith('/C.cap')
                ? capXml(
                    id: 'C',
                    type: 'Cancel',
                    references: '$alertSender,A,$alertSent',
                  )
                : capXml(),
          );
        }),
      );
      expect((await source.fetch()).partial, false);
      expect(paths, contains('/Capstorage/C.cap'));
    },
  );
  test(
    'one failed CAP is partial and all failed CAPs are unavailable',
    () async {
      var allFail = false;
      final source = NcdrAlertSource(
        feedUri: feedUri,
        now: () => alertNow,
        client: MockClient((request) async {
          if (request.url.path == '/feed') {
            return xmlResponse(
              atomFeed(
                atomEntry(id: allFail ? 'NEW' : 'A') + atomEntry(id: 'B'),
              ),
            );
          }
          if (!allFail && request.url.path.endsWith('/A.cap')) {
            return xmlResponse(capXml());
          }
          return http.Response('unavailable', 503);
        }),
      );
      expect((await source.fetch()).failedDocuments, 1);
      allFail = true;
      await expectLater(source.fetch(), throwsStateError);
    },
  );
  test(
    'cap limit is visible and mismatched CAP identities are rejected',
    () async {
      final source = NcdrAlertSource(
        feedUri: feedUri,
        maxDocuments: 1,
        now: () => alertNow,
        client: MockClient(
          (r) async => xmlResponse(
            r.url.path == '/feed'
                ? atomFeed(atomEntry() + atomEntry(id: 'B'))
                : capXml(),
          ),
        ),
      );
      expect((await source.fetch()).truncated, true);
      final mismatch = NcdrAlertSource(
        feedUri: feedUri,
        now: () => alertNow,
        client: MockClient(
          (r) async => xmlResponse(
            r.url.path == '/feed' ? atomFeed(atomEntry(id: 'WRONG')) : capXml(),
          ),
        ),
      );
      await expectLater(mismatch.fetch(), throwsStateError);
    },
  );
  test(
    'hanging feed respects the timeout instead of parking all queries',
    () async {
      final source = NcdrAlertSource(
        feedUri: feedUri,
        requestTimeout: const Duration(milliseconds: 5),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(source.fetch(), throwsA(isA<TimeoutException>()));
    },
  );
}
