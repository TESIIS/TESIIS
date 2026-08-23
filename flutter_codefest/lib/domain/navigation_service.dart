import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:geolocator/geolocator.dart';

/// Builds the Google Maps URL used to hand a shelter off to whatever map app
/// the device has.
///
/// This is a plain https URL, so it needs no API key even though the app no
/// longer embeds Google Maps.
Uri buildNavigationUri(Shelter shelter, {Position? from}) {
  if (shelter.hasCoordinate) {
    final destination = '${shelter.latitude},${shelter.longitude}';
    return from != null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1'
            '&origin=${from.latitude},${from.longitude}'
            '&destination=$destination&travelmode=walking',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$destination',
          );
  }

  // No coordinate: fall back to a text search on the address, which is the
  // whole reason these shelters stay in the list. Uses the shelter's own
  // city — hardcoding 臺北市 here was fine when that was the only county in
  // the dataset, but would send every other county's uncoordinated shelters
  // to the wrong place nationwide.
  final query = Uri.encodeComponent(
    '${shelter.city}${shelter.district}${shelter.address}',
  );
  return Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
}
