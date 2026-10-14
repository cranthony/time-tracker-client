import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';

/// Where on Earth, in degrees.
@immutable
class Coordinates {
  const Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Rounded to the hundredth of a degree, about a kilometer: as near as
  /// a forecast needs, and no nearer than the weather service needs to
  /// know.
  Coordinates get rounded => Coordinates(
    (latitude * 100).roundToDouble() / 100,
    (longitude * 100).roundToDouble() / 100,
  );

  @override
  bool operator ==(Object other) =>
      other is Coordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'Coordinates($latitude, $longitude)';
}

/// Whether the app may know where the device is: [blocked] is denied for
/// good, so only the device's settings can allow it now; [serviceOff],
/// the device's location is off altogether.
enum LocationAccess { granted, denied, blocked, serviceOff }

/// Where the device is.
abstract class LocationSource {
  Future<LocationAccess> access();

  /// Asks the user to let the app know; what they said.
  Future<LocationAccess> requestAccess();

  /// Where it is now, roughly: a forecast needs no more.
  Future<Coordinates> current();

  /// Opens the device's settings for the app, or for location, to allow
  /// it there.
  Future<void> openSettings();
}

/// Where forecasts come from.
abstract class ForecastSource {
  /// The forecast for [at], from [now] on.
  Future<Forecast> fetch(Coordinates at, {required DateTime now});
}

/// A forecast that couldn't be had, and why.
class WeatherException implements Exception {
  WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether the weather's shown, and the forecast for wherever the device
/// is: each one fetched replaces the last whole. Whether it's on is kept
/// on this device ([persist]); the forecast only while the app runs.
class Weather extends ChangeNotifier {
  Weather({
    required this.forecasts,
    required this.location,
    this.persist = true,
    this._enabled = false,
    DateTime Function()? clock,
    this.maxAge = const Duration(minutes: 30),
  }) : _clock = clock ?? DateTime.now;

  final ForecastSource forecasts;
  final LocationSource location;
  final bool persist;
  final DateTime Function() _clock;

  /// How old a forecast gets before a [refresh] fetches another.
  final Duration maxAge;

  static const _enabledKey = 'weather_enabled';

  bool _enabled;

  /// Whether it's shown: only while the app may know where it is.
  bool get enabled => _enabled;

  LocationAccess? _access;

  /// What the user last said to letting the app know where it is, once
  /// asked.
  LocationAccess? get access => _access;

  Forecast? _forecast;

  /// The latest forecast, once there's one.
  Forecast? get forecast => _forecast;

  Object? _error;

  /// Why the last fetch failed, if it did: the forecast before it, if any,
  /// is kept till one comes.
  Object? get error => _error;

  Future<void>? _fetching;

  /// Whether a forecast is being fetched.
  bool get loading => _fetching != null;

  /// Bumped as it's turned off, so a fetch begun before is dropped as it
  /// comes.
  var _generation = 0;

  /// Reads whether it's on, kept on the device, and whether the app may
  /// still know where it is: if not, it's off. Then fetches. Best effort.
  Future<void> load() async {
    if (persist) {
      try {
        _enabled =
            await SharedPreferencesAsync().getBool(_enabledKey) ?? _enabled;
      } catch (_) {
        // Nothing kept: as it was.
      }
    }
    if (_enabled) {
      try {
        _access = await location.access();
      } catch (_) {
        _access = LocationAccess.denied;
      }
      if (_access != LocationAccess.granted) _enabled = false;
    }
    notifyListeners();
    await refresh();
  }

  /// Turns it on, asking to know where the device is if need be; whether
  /// it's on. Refused, [access] says how.
  Future<bool> enable() async {
    var access = await location.access();
    if (access == LocationAccess.denied) {
      access = await location.requestAccess();
    }
    _access = access;
    if (access != LocationAccess.granted) {
      notifyListeners();
      return false;
    }
    _enabled = true;
    _keep();
    notifyListeners();
    unawaited(refresh(force: true));
    return true;
  }

  void disable() {
    _enabled = false;
    _generation++;
    _forecast = null;
    _error = null;
    _fetching = null;
    _keep();
    notifyListeners();
  }

  void _keep() {
    if (!persist) return;
    try {
      SharedPreferencesAsync()
          .setBool(_enabledKey, _enabled)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Fetches a forecast for where the device is now, if it's on and the
  /// last is older than [maxAge] -- or whatever its age, with [force] --
  /// unless one's being fetched already.
  Future<void> refresh({bool force = false}) {
    if (!_enabled) return Future.value();
    if (_fetching case final fetching?) return fetching;
    final last = _forecast;
    if (!force &&
        _error == null &&
        last != null &&
        _clock().difference(last.fetchedAt) < maxAge) {
      return Future.value();
    }
    final generation = _generation;
    final fetching = _fetch(generation);
    _fetching = fetching;
    notifyListeners();
    return fetching;
  }

  Future<void> _fetch(int generation) async {
    Forecast? forecast;
    Object? error;
    try {
      final at = await location.current();
      forecast = await forecasts.fetch(at.rounded, now: _clock());
    } catch (e) {
      error = e;
    }
    if (generation != _generation) return;
    _fetching = null;
    if (forecast != null) _forecast = forecast;
    _error = error;
    notifyListeners();
  }

  /// The nearest [WeatherScope]'s, or null if there's none.
  static Weather? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WeatherScope>()?.notifier;

  /// The nearest [WeatherScope]'s, without rebuilding as it changes: for
  /// outside a build.
  static Weather? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WeatherScope>()?.notifier;
}

/// Gives the [Weather] to everything below it, rebuilding what reads it
/// ([Weather.of]) as it changes.
class WeatherScope extends InheritedNotifier<Weather> {
  const WeatherScope({
    super.key,
    required Weather weather,
    required super.child,
  }) : super(notifier: weather);
}
