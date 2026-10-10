/// CAP identities include sender AND sent time. An identifier alone is not a
/// globally unique message, nor are equal event names an update relationship.
class CapReference {
  const CapReference(this.sender, this.identifier, this.sent);
  final String sender;
  final String identifier;
  final DateTime sent;
  String get key => '$sender|$identifier|${sent.microsecondsSinceEpoch}';
}

class AlertRegion {
  const AlertRegion(this.city, [this.township]);
  final String city;
  final String? township;
  String get key => '$city|${township ?? ''}';
  Map<String, dynamic> toJson() => {
    'city': city,
    if (township != null) 'township': township,
  };
}

class AlertInfo {
  const AlertInfo({
    required this.index,
    required this.event,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.senderName,
    required this.effective,
    required this.expires,
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.areas,
    required this.regions,
    this.web,
  });
  final int index;
  final String event;
  final String headline;
  final String description;
  final String instruction;
  final String senderName;
  final DateTime effective;
  final DateTime? expires;
  final String severity;
  final String urgency;
  final String certainty;
  final List<String> areas;
  final List<AlertRegion> regions;
  final Uri? web;

  String temporalState(DateTime now) {
    if (expires != null && !now.isBefore(expires!)) return 'expired';
    if (now.isBefore(effective)) return 'scheduled';
    return expires == null ? 'unknown' : 'active';
  }
}

class CapMessage {
  const CapMessage({
    required this.identity,
    required this.messageType,
    required this.infos,
    required this.references,
    required this.sourceUrl,
    this.invalidInfoCount = 0,
  });
  final CapReference identity;
  final String messageType;
  final List<AlertInfo> infos;
  final List<CapReference> references;
  final Uri sourceUrl;
  final int invalidInfoCount;
  String get key => identity.key;
}

class AlertBatch {
  const AlertBatch({
    required this.messages,
    required this.fetchedAt,
    required this.sourceUpdatedAt,
    required this.feedEntries,
    required this.failedDocuments,
    required this.truncated,
    required this.omittedExpired,
  });
  final List<CapMessage> messages;
  final DateTime fetchedAt;
  final DateTime? sourceUpdatedAt;
  final int feedEntries;
  final int failedDocuments;
  final bool truncated;
  final int omittedExpired;
  bool get partial => failedDocuments > 0 || truncated;
}
