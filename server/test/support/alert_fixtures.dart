import 'package:server/data/mappers/cap_alert_mapper.dart';
import 'package:server/domain/entities/disaster_alert.dart';

final alertNow = DateTime.utc(2026, 10, 10, 8, 30);
const alertSent = '2026-10-10T08:00:00+00:00';
const alertSender = 'weather@example.gov.tw';

String capInfo({
  String language = 'zh-TW',
  String area = '臺北市中正區',
  String effective = alertSent,
  String? expires = '2026-10-10T10:00:00+00:00',
  String headline = '測試用降雨公告',
  String severity = 'Severe',
  String parameters = '',
  String web = 'https://example.gov.tw/warnings',
}) =>
    '''
<info><language>$language</language><event>降雨</event><headline>$headline</headline><description>這是自動測試資料，不是真實警報。</description><instruction>測試用說明</instruction>
<senderName>測試發布單位</senderName><effective>$effective</effective>${expires == null ? '' : '<expires>$expires</expires>'}<severity>$severity</severity><urgency>Immediate</urgency><certainty>Observed</certainty>
<web>$web</web>$parameters<area><areaDesc>$area</areaDesc></area></info>''';

String capXml({
  String id = 'A',
  String sender = alertSender,
  String sent = alertSent,
  String type = 'Alert',
  String status = 'Actual',
  String scope = 'Public',
  String references = '',
  String? infos,
}) => '''<?xml version="1.0" encoding="UTF-8"?>
<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>$id</identifier><sender>$sender</sender><sent>$sent</sent><status>$status</status><msgType>$type</msgType><scope>$scope</scope><references>$references</references>${infos ?? capInfo()}</alert>''';

String atomEntry({
  String id = 'A',
  String type = 'Alert',
  String status = 'Actual',
  String updated = alertSent,
  String expires = '2026/10/10 下午 06:00:00',
  String? url,
}) =>
    '''<entry><id>$id</id><title>測試警報</title><updated>$updated</updated><link rel="alternate" href="${url ?? 'https://alerts.example/Capstorage/$id.cap'}"/><cap:status>$status</cap:status><cap:msgType>$type</cap:msgType><cap:expires>$expires</cap:expires></entry>''';

String atomFeed(String entries) =>
    '''<feed xmlns="http://www.w3.org/2005/Atom" xmlns:cap="urn:oasis:names:tc:emergency:cap:1.1"><updated>$alertSent</updated>$entries</feed>''';

CapMessage parseTestCap(String xml) => CapAlertMapper.parseCap(
  xml,
  Uri.parse('https://alerts.example/Capstorage/test.cap'),
)!;

AlertBatch alertBatch(
  List<CapMessage> messages, {
  int failures = 0,
  bool truncated = false,
  DateTime? fetchedAt,
}) => AlertBatch(
  messages: messages,
  fetchedAt: fetchedAt ?? alertNow,
  sourceUpdatedAt: DateTime.parse(alertSent),
  feedEntries: messages.length,
  failedDocuments: failures,
  truncated: truncated,
  omittedExpired: 0,
);
