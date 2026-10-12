import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Maps' search for [place]: an address, or a place's name.
Uri mapsSearch(String place) => Uri.https('www.google.com', '/maps/search/', {
  'api': '1',
  'query': place.trim(),
});

/// A search for [place] that any maps app on Android takes: the default
/// one, or the user's pick of them.
Uri geoSearch(String place) =>
    Uri.parse('geo:0,0?q=${Uri.encodeComponent(place.trim())}');

/// Opens [place] in a maps app: on Android, the default one, by a `geo:`
/// link; elsewhere, or with no maps app to take it, Google Maps in the
/// browser. Whether it opened.
Future<bool> openInMaps(String place) async {
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      await open(geoSearch(place))) {
    return true;
  }
  return open(mapsSearch(place));
}
