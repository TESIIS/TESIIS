import 'package:flutter/foundation.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

Uri shelterLink(Shelter shelter, {Uri? base}) {
  final source =
      base ??
      (kIsWeb ? Uri.base : Uri.parse('https://tesiis.itousouta.me/app/'));
  return source.replace(
    queryParameters: {'shelter': shelter.shelterId},
    fragment: '',
  );
}

String shelterShareText(Shelter shelter) =>
    '${shelter.name}\n${shelter.city} ${shelter.district}\n${shelter.address}\n${shelterLink(shelter)}';
