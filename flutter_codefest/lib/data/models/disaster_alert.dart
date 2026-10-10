class AlertRegion {
  const AlertRegion(this.city, [this.township]);
  final String city;
  final String? township;
  String get key => '$city|${township ?? ''}';
  String get label => '$city${township ?? ''}';
  factory AlertRegion.fromJson(Map<String, dynamic> json) =>
      AlertRegion(json['city'] as String, json['township'] as String?);
  Map<String, dynamic> toJson() => {
    'city': city,
    if (township != null) 'township': township,
  };
}

Uri? _webUri(Object? value) {
  final uri = Uri.tryParse(value?.toString() ?? '');
  return uri != null &&
          {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class DisasterAlert {
  DisasterAlert.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      headline = json['headline'] as String? ?? '',
      event = json['event'] as String? ?? '',
      description = json['description'] as String? ?? '',
      instruction = json['instruction'] as String? ?? '',
      senderName = json['senderName'] as String? ?? '',
      serverState = json['state'] as String? ?? 'unknown',
      severity = json['severity'] as String? ?? '',
      sentAt = DateTime.tryParse(json['sentAt']?.toString() ?? ''),
      effectiveAt = DateTime.tryParse(json['effectiveAt']?.toString() ?? ''),
      expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      regions = (json['regions'] as List? ?? [])
          .map((e) => AlertRegion.fromJson(e as Map<String, dynamic>))
          .toList(),
      areas = (json['areas'] as List? ?? []).cast<String>(),
      regionMatch = json['regionMatch'] as String? ?? 'all',
      sourceUrl = _webUri(json['sourceUrl']),
      webUrl = _webUri(json['webUrl']);
  final String id;
  final String headline;
  final String event;
  final String description;
  final String instruction;
  final String senderName;
  final String serverState;
  final String severity;
  final DateTime? sentAt;
  final DateTime? effectiveAt;
  final DateTime? expiresAt;
  final List<AlertRegion> regions;
  final List<String> areas;
  final String regionMatch;
  final Uri? sourceUrl;
  final Uri? webUrl;

  String stateAt(DateTime now) {
    if ({'cancelled', 'superseded'}.contains(serverState)) return serverState;
    if (serverState == 'expired' ||
        (expiresAt != null && !now.isBefore(expiresAt!))) {
      return 'expired';
    }
    if (effectiveAt != null && now.isBefore(effectiveAt!)) return 'scheduled';
    return expiresAt == null || effectiveAt == null ? 'unknown' : 'active';
  }

  bool isCurrent(DateTime now) =>
      !{'cancelled', 'superseded', 'expired'}.contains(stateAt(now));
  String statusLabel(DateTime now, {required bool verified}) {
    final state = stateAt(now);
    if (!verified && isCurrent(now)) return '最新狀態待確認';
    return switch (state) {
      'cancelled' => '已解除',
      'superseded' => '已更新',
      'expired' => '已到期',
      'scheduled' => '尚未生效',
      'active' => '發布期間內',
      _ => '期限未提供',
    };
  }

  String get severityLabel => switch (severity) {
    'Extreme' => '極嚴重',
    'Severe' => '嚴重',
    'Moderate' => '中等',
    'Minor' => '輕微',
    _ => '未提供嚴重程度',
  };
}

class AlertFeed {
  AlertFeed.fromJson(Map<String, dynamic> json, {this.deviceCache = false})
    : alerts = (json['data'] as List)
          .map((e) => DisasterAlert.fromJson(e as Map<String, dynamic>))
          .toList(),
      freshness = json['freshness'] as String? ?? 'stale',
      fetchedAt = DateTime.parse(json['fetchedAt'] as String),
      sourceUpdatedAt = DateTime.tryParse(
        json['sourceUpdatedAt']?.toString() ?? '',
      ),
      refreshAfterSeconds = (json['refreshAfterSeconds'] as int? ?? 120).clamp(
        30,
        300,
      ),
      partial = json['partial'] == true || json['sourceTruncated'] == true,
      unknownRegionCount = json['unknownRegionCount'] as int? ?? 0,
      total = json['total'] as int? ?? 0,
      truncated = json['truncated'] == true;
  final List<DisasterAlert> alerts;
  final String freshness;
  final DateTime fetchedAt;
  final DateTime? sourceUpdatedAt;
  final int refreshAfterSeconds;
  final bool partial;
  final bool deviceCache;
  final int unknownRegionCount;
  final int total;
  final bool truncated;
  bool verifiedAt(DateTime now) =>
      !deviceCache &&
      !partial &&
      freshness == 'fresh' &&
      !now.isBefore(fetchedAt.subtract(const Duration(minutes: 1))) &&
      now.difference(fetchedAt).inSeconds <= refreshAfterSeconds;
}

String alertTime(DateTime? time) {
  if (time == null) return '未提供';
  final taipei = time.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${taipei.year}/${two(taipei.month)}/${two(taipei.day)} ${two(taipei.hour)}:${two(taipei.minute)}';
}
