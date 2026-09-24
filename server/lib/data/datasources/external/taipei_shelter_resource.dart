import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../core/csv/csv_codec.dart';

const _tableNamespace = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _textNamespace = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _odsMimeType = 'application/vnd.oasis.opendocument.spreadsheet';

/// The Taipei API occasionally exposes rows parsed from the ZIP header of an
/// uploaded ODS file instead of the shelter register. Reject that response
/// before an empty coordinate table can be written.
List<Map<String, dynamic>> validateTaipeiShelterRows(
  List<Map<String, dynamic>> rows,
) {
  if (rows.isEmpty) {
    throw const FormatException('Taipei shelter source contains no rows');
  }

  final normalized = <Map<String, dynamic>>[];
  final codes = <String>{};
  for (var i = 0; i < rows.length; i++) {
    final row = normalizeTaipeiShelterRow(rows[i]);
    for (final field in ['收容所編號', '名稱', '門牌地址', '鄉鎮']) {
      if ('${row[field] ?? ''}'.trim().isEmpty) {
        throw FormatException(
          'Taipei shelter row ${i + 1} is missing $field; '
          'available fields: ${rows[i].keys.join(', ')}',
        );
      }
    }
    final code = '${row['收容所編號']}'.trim();
    if (!codes.add(code)) {
      throw FormatException('Duplicate Taipei shelter code: $code');
    }
    normalized.add(row);
  }
  return normalized;
}

/// Fold the two published header versions into the names the rest of the
/// Taipei pipeline already understands.
Map<String, dynamic> normalizeTaipeiShelterRow(Map<String, dynamic> row) {
  final normalized = Map<String, dynamic>.of(row);
  void alias(String canonical, String alternate) {
    if ('${normalized[canonical] ?? ''}'.trim().isEmpty &&
        normalized.containsKey(alternate)) {
      normalized[canonical] = normalized[alternate];
    }
  }

  alias('名稱', '名稱(學校機關全銜)');
  alias('救濟支站', '救濟站');
  alias('收容所面積（平方公尺）', '收容所面積(平方公尺)');
  return normalized;
}

/// The resource download may be a UTF-8 CSV or an ODS spreadsheet. The
/// published metadata still says CSV even when the actual file is ODS, so
/// detect the file format from its bytes rather than its advertised type.
List<Map<String, dynamic>> decodeTaipeiShelterResource(List<int> bytes) {
  final rows =
      bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4b &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04
      ? _decodeOds(bytes)
      : parseCsvAsMaps(utf8.decode(bytes)).cast<Map<String, dynamic>>();
  return validateTaipeiShelterRows(rows);
}

List<Map<String, dynamic>> _decodeOds(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final mime = archive.findFile('mimetype');
  final content = archive.findFile('content.xml');
  if (mime == null ||
      utf8.decode(mime.content) != _odsMimeType ||
      content == null) {
    throw const FormatException('Taipei resource is not an ODS spreadsheet');
  }

  final document = XmlDocument.parse(utf8.decode(content.content));
  final sheets = document.findAllElements(
    'table',
    namespaceUri: _tableNamespace,
  );
  final register = sheets.where(
    (sheet) =>
        sheet.getAttribute('name', namespaceUri: _tableNamespace) == '清冊',
  );
  if (register.isEmpty) {
    throw const FormatException('Taipei ODS has no 清冊 worksheet');
  }

  List<String>? header;
  final rows = <Map<String, dynamic>>[];
  for (final xmlRow in register.first.findElements(
    'table-row',
    namespaceUri: _tableNamespace,
  )) {
    // ODS represents the unused tail of a sheet as millions of repeated
    // empty rows. Iterate physical XML rows only.
    final values = _cellValues(xmlRow);
    if (values.every((value) => value.isEmpty)) continue;
    final rowRepeat =
        int.tryParse(
          xmlRow.getAttribute(
                'number-rows-repeated',
                namespaceUri: _tableNamespace,
              ) ??
              '1',
        ) ??
        1;
    if (rowRepeat != 1) {
      throw const FormatException('Taipei ODS repeats a nonempty row');
    }
    if (header == null) {
      header = values.map((value) => value.trim()).toList();
      continue;
    }
    final code = values.isEmpty ? '' : values.first.trim();
    if (code.isEmpty) {
      // The current register ends with two totals rows with no code or name.
      if (values.take(6).every((value) => value.isEmpty)) continue;
      throw const FormatException('Taipei ODS contains a row without a code');
    }
    final row = <String, dynamic>{};
    for (var i = 0; i < header.length; i++) {
      if (header[i].isNotEmpty) {
        row[header[i]] = i < values.length ? values[i] : '';
      }
    }
    rows.add(row);
  }
  return rows;
}

List<String> _cellValues(XmlElement row) {
  final values = <String>[];
  for (final cell in row.children.whereType<XmlElement>()) {
    if (cell.name.local != 'table-cell' &&
        cell.name.local != 'covered-table-cell') {
      continue;
    }
    final repeat =
        int.tryParse(
          cell.getAttribute(
                'number-columns-repeated',
                namespaceUri: _tableNamespace,
              ) ??
              '1',
        ) ??
        1;
    if (repeat < 1) {
      throw const FormatException('Invalid repeated ODS cell count');
    }
    // Only the first 64 columns can contain shelter fields. A blank tail may
    // be repeated thousands of times in a valid ODS file.
    final paragraphs = cell.findElements('p', namespaceUri: _textNamespace);
    final value = paragraphs.map((p) => p.innerText).join('\n').trim();
    for (var i = 0; i < repeat && values.length < 64; i++) {
      values.add(value);
    }
  }
  return values;
}
