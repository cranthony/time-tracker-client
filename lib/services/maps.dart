import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

/// [place] as a web link, if that's all it is -- a link to it on a map,
/// say, or to a video call -- rather than an address or a place's name.
Uri? placeLink(String place) {
  final text = place.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
  return uri.host.isEmpty ? null : uri;
}

/// The button that opens [place] ([openInMaps]): an arrow if it's a link,
/// a map if not.
({IconData icon, String tooltip}) placeButton(String place) =>
    placeLink(place) == null
    ? (icon: Icons.map_outlined, tooltip: 'Open in Maps')
    : (icon: Icons.arrow_forward, tooltip: 'Open link');

/// Opens [place]: a link ([placeLink]) as it is, in the app it belongs
/// to; anything else in a maps app -- on Android, the default one, by a
/// `geo:` link; elsewhere, or with no maps app to take it, Google Maps in
/// the browser. Whether it opened.
Future<bool> openInMaps(String place) async {
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  if (placeLink(place) case final link?) return open(link);
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      await open(geoSearch(place))) {
    return true;
  }
  return open(mapsSearch(place));
}
