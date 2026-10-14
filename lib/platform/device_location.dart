import 'package:geolocator/geolocator.dart';

import '../services/weather.dart';

/// Where the device is, from its own location service (the geolocator
/// plugin): on Android, the coarse location; in a browser, its
/// geolocation; on Windows, its location service.
class DeviceLocationSource implements LocationSource {
  static LocationAccess _access(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.blocked,
        _ => LocationAccess.denied,
      };

  @override
  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _access(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> requestAccess() async =>
      _access(await Geolocator.requestPermission());

  @override
  Future<Coordinates> current() async {
    // Where it was in the last hour will do, if it's known: a forecast's
    // for miles. Browsers don't know.
    Position? known;
    try {
      known = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    if (known != null &&
        DateTime.now().difference(known.timestamp) > const Duration(hours: 1)) {
      known = null;
    }
    final position =
        known ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 30),
          ),
        );
    return Coordinates(position.latitude, position.longitude);
  }

  @override
  Future<void> openSettings() async {
    if (await access() == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
