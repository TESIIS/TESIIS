// lib/core/csv/csv_codec.dart
//
// Minimal RFC 4180 CSV reader/writer.
//
// Written by hand rather than pulled from pub because the only CSV this repo
// touches is its own coordinate table plus one government export, and both are
// plain UTF-8 with quoted fields. Adding a dependency for ~60 lines would cost
// more than it saves.

/// Parses [input] into rows of raw string fields.
///
/// Handles quoted fields, embedded commas/newlines, and doubled quotes (""),
/// which the 消防署 export uses for its 適用災害類別 column ("水災,震災,土石流").
/// Strips a UTF-8 BOM if present — the 消防署 export has one.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // A trailing newline must not produce a phantom empty row.
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.write(ch);
      }
      i++;
      continue;
    }
    switch (ch) {
      case '"':
        inQuotes = true;
        break;
      case ',':
        endField();
        break;
      case '\r':
        // Swallow CR; the following LF ends the row.
        break;
      case '\n':
        endRow();
        break;
      default:
        field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Parses [input] into maps keyed by the header row.
List<Map<String, String>> parseCsvAsMaps(String input) {
  final rows = parseCsv(input);
  if (rows.isEmpty) return const [];
  final header = rows.first.map((h) => h.trim()).toList(growable: false);
  return rows
      .skip(1)
      .map((row) {
        final map = <String, String>{};
        for (var i = 0; i < header.length; i++) {
          map[header[i]] = i < row.length ? row[i] : '';
        }
        return map;
      })
      .toList(growable: false);
}

/// Quotes [value] only when it would otherwise break the format, so the
/// committed coordinate table stays readable in a diff.
String encodeCsvField(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String encodeCsvRow(Iterable<String> fields) =>
    fields.map(encodeCsvField).join(',');
