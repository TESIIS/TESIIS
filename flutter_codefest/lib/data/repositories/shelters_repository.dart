import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/api_response.dart';
import 'package:flutter_codefest/data/datasources/api.dart';

Future<List<Shelter>> fetchAllShelters() async {
  final res = await ApiService.get('/shelters'); // ← 你自己的 endpoint

  final data = ApiResponse<List<Shelter>>.fromJson(
    res,
    (json) => (json as List<dynamic>).map((e) => Shelter.fromJson(e)).toList(),
  );

  return data.data;
}

Future<List<Shelter>> fetchFilteredShelters({
  String? q,
  String? city,
  String? township,
  String? village,
  String? type,
  String match = 'and',
  String? flood,
  String? quake,
  String? landslide,
  String? tsunami,
  String? relief,
  String? accessible,
  String? indoor,
  String? outdoor,
}) async {
  // 組裝 query 參數
  final Map<String, String> queryParams = {};

  if (q != null) queryParams['q'] = q;
  if (city != null) queryParams['city'] = city;
  if (township != null) queryParams['township'] = township;
  if (village != null) queryParams['village'] = village;
  if (type != null) queryParams['type'] = type;
  queryParams['match'] = match;

  // 災害條件：Y/N/備用 → true
  Map<String, String?> hazardMap = {
    'flood': flood,
    'quake': quake,
    'landslide': landslide,
    'tsunami': tsunami,
    'relief': relief,
    'accessible': accessible,
    'indoor': indoor,
    'outdoor': outdoor,
  };

  hazardMap.forEach((key, value) {
    if (value != null && (value.toUpperCase() == 'Y' || value == '備用')) {
      queryParams[key] = 'true';
    }
  });

  // 呼叫 API，帶上 query 參數
  final res = await ApiService.get('/shelters', queryParams: queryParams);
  final data = ApiResponse<List<Shelter>>.fromJson(
    res,
    (json) => (json as List<dynamic>).map((e) => Shelter.fromJson(e)).toList(),
  );

  return data.data;
}
