import 'package:xml/xml.dart';

import '../../core/geo/city_codes.dart';
import '../../domain/entities/disaster_alert.dart';
import '../../domain/entities/shelter_fields.dart';

class AlertFeedEntry {
  const AlertFeedEntry({
    required this.id,
    required this.url,
    required this.updated,
    required this.messageType,
    required this.expires,
  });
  final String id;
  final Uri url;
  final DateTime updated;
  final String messageType;
  final DateTime? expires;
}

typedef ParsedAlertFeed = ({
  List<AlertFeedEntry> entries,
  DateTime? updatedAt,
  int invalidEntries,
});

/// The NCDR feed uses Atom + CAP 1.1 fields; linked documents use CAP 1.2.
/// Same-language info blocks remain separate (different severity/areas/times).
class CapAlertMapper {
  static Iterable<XmlElement> _children(XmlElement root, String name) =>
      root.childElements.where((e) => e.name.local == name);
  static String _text(XmlElement root, String name) =>
      _children(root, name).firstOrNull?.innerText.trim() ?? '';
  static XmlElement _root(String xml, String name) {
    if (RegExp(r'<!DOCTYPE', caseSensitive: false).hasMatch(xml)) {
      throw const FormatException('DTD is not supported');
    }
    final root = XmlDocument.parse(xml).rootElement;
    final ns = root.getAttribute(
      root.name.prefix == null ? 'xmlns' : 'xmlns:${root.name.prefix}',
    );
    final accepted = name == 'feed'
        ? {'http://www.w3.org/2005/Atom'}
        : {
            'urn:oasis:names:tc:emergency:cap:1.1',
            'urn:oasis:names:tc:emergency:cap:1.2',
          };
    if (root.name.local != name || !accepted.contains(ns)) {
      throw const FormatException('Unexpected XML document');
    }
    return root;
  }

  /// Date-only or timezone-less strings cannot be interpreted as live times.
  static DateTime? capDate(String raw) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
    ).firstMatch(raw);
    if (m == null) return null;
    final year = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        int.parse(m[4]!) > 23 ||
        int.parse(m[5]!) > 59 ||
        int.parse(m[6]!) > 59 ||
        int.parse(m[7] ?? '0') > 23 ||
        int.parse(m[8] ?? '0') > 59) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// NCDR's Atom extension currently formats these fields in zh-TW local time.
  static DateTime? feedDate(String raw) {
    final iso = capDate(raw);
    if (iso != null) return iso;
    final match = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(上午|下午)\s+(\d{1,2}):(\d{2}):(\d{2})$',
    ).firstMatch(raw);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[5]!);
    final minute = int.parse(match[6]!);
    final second = int.parse(match[7]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour < 1 ||
        hour > 12 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final local = DateTime.utc(
      year,
      month,
      day,
      hour % 12 + (match[4] == '下午' ? 12 : 0),
      minute,
      second,
    );
    if (local.month != month || local.day != day) return null;
    return local.subtract(const Duration(hours: 8));
  }

  static ParsedAlertFeed parseFeed(String xml, Uri feedUri) {
    final root = _root(xml, 'feed');
    final entries = <AlertFeedEntry>[];
    var invalid = 0;
    for (final entry in _children(root, 'entry')) {
      if (_text(entry, 'status') != 'Actual') continue;
      final type = _text(entry, 'msgType');
      if (!{'Alert', 'Update', 'Cancel'}.contains(type)) continue;
      final id = _text(entry, 'id');
      final updated = capDate(_text(entry, 'updated'));
      final link = _children(
        entry,
        'link',
      ).where((e) => e.getAttribute('rel') == 'alternate').firstOrNull;
      final rawUrl = link?.getAttribute('href');
      final url = rawUrl == null ? null : feedUri.resolve(rawUrl);
      // Feed contents do not get to choose arbitrary server-side fetch targets.
      if (id.isEmpty ||
          updated == null ||
          url == null ||
          url.scheme != feedUri.scheme ||
          url.host != feedUri.host ||
          url.port != feedUri.port ||
          url.userInfo.isNotEmpty ||
          !url.path.startsWith('/Capstorage/') ||
          !url.path.toLowerCase().endsWith('.cap') ||
          url.hasQuery ||
          url.hasFragment) {
        invalid++;
        continue;
      }
      entries.add(
        AlertFeedEntry(
          id: id,
          url: url,
          updated: updated,
          messageType: type,
          expires: feedDate(_text(entry, 'expires')),
        ),
      );
    }
    entries.sort((a, b) => b.updated.compareTo(a.updated));
    return (
      entries: entries,
      updatedAt: capDate(_text(root, 'updated')),
      invalidEntries: invalid,
    );
  }

  static CapMessage? parseCap(String xml, Uri sourceUrl) {
    final root = _root(xml, 'alert');
    if (_text(root, 'status') != 'Actual' || _text(root, 'scope') != 'Public') {
      return null;
    }
    final type = _text(root, 'msgType');
    if (!{'Alert', 'Update', 'Cancel'}.contains(type)) return null;
    final identifier = _text(root, 'identifier');
    final sender = _text(root, 'sender');
    final sent = capDate(_text(root, 'sent'));
    if (identifier.isEmpty || sender.isEmpty || sent == null) {
      throw const FormatException('Missing CAP identity');
    }
    final references = <CapReference>[];
    var invalidReferences = 0;
    for (final ref in _text(root, 'references').split(RegExp(r'\s+'))) {
      if (ref.isEmpty) continue;
      final parts = ref.split(',');
      if (parts.length != 3) {
        invalidReferences++;
        continue;
      }
      final time = capDate(parts[2]);
      if (time != null && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        references.add(CapReference(parts[0], parts[1], time));
      } else {
        invalidReferences++;
      }
    }
    final blocks = _children(root, 'info').toList();
    String language(XmlElement e) => _text(e, 'language').toLowerCase();
    final preferred =
        blocks
            .where(
              (e) => {'zh-tw', 'zh-hant', 'zh-hant-tw'}.contains(language(e)),
            )
            .firstOrNull ??
        blocks.firstOrNull;
    final infos = <AlertInfo>[];
    var invalidInfos = 0;
    for (var i = 0; i < blocks.length; i++) {
      final info = blocks[i];
      if (language(info) != language(preferred!)) continue;
      try {
        final effectiveText = _text(info, 'effective');
        final effective = effectiveText.isEmpty ? sent : capDate(effectiveText);
        final expiresText = _text(info, 'expires');
        final expires = expiresText.isEmpty ? null : capDate(expiresText);
        if (effective == null ||
            (expiresText.isNotEmpty && expires == null) ||
            (expires != null && expires.isBefore(effective))) {
          throw const FormatException('Invalid CAP interval');
        }
        final event = _text(info, 'event');
        final areas = _children(info, 'area').toList();
        final descriptions = [
          for (final area in areas)
            if (_text(area, 'areaDesc').isNotEmpty) _text(area, 'areaDesc'),
        ];
        final parameters = <String, String>{
          for (final p in _children(info, 'parameter'))
            _text(p, 'valueName').toLowerCase(): _text(p, 'value'),
        };
        final targets = <String, AlertRegion>{};
        for (final text in [
          ...descriptions,
          parameters['counties'] ?? '',
          parameters['townships'] ?? '',
        ]) {
          for (final region in _regions(text)) {
            targets[region.key] = region;
          }
        }
        // Township names from CAP parameters disambiguate county summaries
        // such as "臺北市(共3個鄉鎮)"; do not expand those to the entire county.
        final specificCities = targets.values
            .where((r) => r.township != null)
            .map((r) => r.city)
            .toSet();
        targets.removeWhere(
          (_, r) =>
              r.township == null &&
              specificCities.contains(r.city) &&
              !descriptions.any((d) => _canonical(d) == r.city),
        );
        final rawWeb = Uri.tryParse(_text(info, 'web'));
        final web =
            rawWeb != null &&
                {'http', 'https'}.contains(rawWeb.scheme) &&
                rawWeb.host.isNotEmpty &&
                rawWeb.userInfo.isEmpty
            ? rawWeb
            : null;
        infos.add(
          AlertInfo(
            index: i,
            event: event,
            headline: _text(info, 'headline').isEmpty
                ? event
                : _text(info, 'headline'),
            description: _text(info, 'description'),
            instruction: _text(info, 'instruction'),
            senderName: _text(info, 'senderName').isEmpty
                ? sender
                : _text(info, 'senderName'),
            effective: effective,
            expires: expires,
            severity: _text(info, 'severity'),
            urgency: _text(info, 'urgency'),
            certainty: _text(info, 'certainty'),
            areas: descriptions,
            regions: targets.values.toList(),
            web: web,
          ),
        );
      } on FormatException {
        invalidInfos++;
      }
    }
    if (infos.isEmpty && type != 'Cancel') invalidInfos++;
    return CapMessage(
      identity: CapReference(sender, identifier, sent),
      messageType: type,
      infos: infos,
      references: references,
      sourceUrl: sourceUrl,
      invalidInfoCount: invalidInfos + invalidReferences,
    );
  }

  static String _canonical(String text) => text.trim().replaceAll('台', '臺');
  static final _cityPattern = RegExp(
    CityCodes.all.map((c) => c.normalizedName).join('|'),
  );
  static final _townPattern = RegExp(
    r'^([\u3400-\u9fff]{1,6}?[鄉鎮市區])(?=$|[\s（(、，,;；])',
  );

  /// Uses area/parameter text only, never a city mentioned in advice/headlines.
  /// Unresolvable geographic-only areas are reported explicitly by the API.
  static List<AlertRegion> _regions(String text) {
    final result = <AlertRegion>[];
    String? previousCity;
    for (final part in ShelterText.normalizeName(
      text,
    ).split(RegExp(r'[、，,;；\n]+'))) {
      final cities = _cityPattern.allMatches(part).toList();
      if (cities.isEmpty) {
        final town = _townPattern.firstMatch(part.trim())?[1];
        if (previousCity != null && town != null) {
          result.add(AlertRegion(previousCity, _canonical(town)));
        }
        continue;
      }
      for (var i = 0; i < cities.length; i++) {
        final city = CityCodes.byNormalizedName(
          cities[i].group(0)!,
        )!.displayName;
        final rest = part
            .substring(
              cities[i].end,
              i + 1 < cities.length ? cities[i + 1].start : part.length,
            )
            .trim();
        final town = _townPattern.firstMatch(rest)?[1];
        result.add(AlertRegion(city, town == null ? null : _canonical(town)));
        previousCity = city;
      }
    }
    return result;
  }
}
