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

/// Whether the weather's shown, where for, and its latest forecast: each
/// one fetched replaces the last whole. It's for where the device is
/// ([usesDevice]) -- asked only then -- or for a [place] the user gives.
/// What's picked is kept on this device ([persist]); the forecast only
/// while the app runs.
class Weather extends ChangeNotifier {
  Weather({
    required this.forecasts,
    required this.location,
    this.persist = true,
    this._enabled = false,
    this._usesDevice = true,
    this._place,
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
  static const _usesDeviceKey = 'weather_uses_device';
  static const _latitudeKey = 'weather_latitude';
  static const _longitudeKey = 'weather_longitude';

  bool _enabled;

  /// Whether it's shown.
  bool get enabled => _enabled;

  bool _usesDevice;

  /// Whether it's for where the device is, rather than the [place] given.
  bool get usesDevice => _usesDevice;

  Coordinates? _place;

  /// The place it's for, as the user gave it, unless it's for where the
  /// device is; kept, either way, to go back to.
  Coordinates? get place => _place;

  LocationAccess? _access;

  /// What the user last said to letting the app know where it is, once
  /// asked, or checked; null while it's never needed to know.
  LocationAccess? get access => _access;

  /// Whether it knows where to fetch the forecast for: where the device
  /// is, allowed, or the [place] given.
  bool get located =>
      _usesDevice ? _access == LocationAccess.granted : _place != null;

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

  /// Bumped as it's turned off, or moved, so a fetch begun before is
  /// dropped as it comes.
  var _generation = 0;

  /// Reads what's kept on the device, and, if it's on for where the
  /// device is, whether the app may still know -- without asking. Then
  /// fetches. Best effort.
  Future<void> load() async {
    if (persist) {
      try {
        final prefs = SharedPreferencesAsync();
        _enabled = await prefs.getBool(_enabledKey) ?? _enabled;
        _usesDevice = await prefs.getBool(_usesDeviceKey) ?? _usesDevice;
        final latitude = await prefs.getDouble(_latitudeKey);
        final longitude = await prefs.getDouble(_longitudeKey);
        if (latitude != null && longitude != null) {
          _place = Coordinates(latitude, longitude);
        }
      } catch (_) {
        // Nothing kept: as it was.
      }
    }
    if (_enabled && _usesDevice) await _checkAccess();
    notifyListeners();
    await refresh();
  }

  Future<void> _checkAccess() async {
    try {
      _access = await location.access();
    } catch (_) {
      _access = LocationAccess.denied;
    }
  }

  /// Asks to know where the device is, if it may be asked; what it said.
  Future<LocationAccess> _askAccess() async {
    await _checkAccess();
    if (_access == LocationAccess.denied) {
      try {
        _access = await location.requestAccess();
      } catch (_) {}
    }
    return _access!;
  }

  /// Turns it on: for where the device is, asking to know if need be,
  /// unless it's for a [place] given. Whether it knows where it's for:
  /// refused, it's on all the same, and [access] says how.
  Future<bool> enable() async {
    _enabled = true;
    _keep();
    if (_usesDevice) await _askAccess();
    notifyListeners();
    unawaited(refresh(force: true));
    return located;
  }

  void disable() {
    _enabled = false;
    _forget();
    _keep();
    notifyListeners();
  }

  /// Makes it for where the device is, asking to know if need be; whether
  /// it may.
  Future<bool> useDevice() async {
    if (!_usesDevice) {
      _usesDevice = true;
      _forget();
      _keep();
    }
    await _askAccess();
    notifyListeners();
    unawaited(refresh(force: true));
    return located;
  }

  /// Makes it for [place], never asking where the device is.
  void usePlace(Coordinates place) {
    if (!_usesDevice && place == _place) return;
    _usesDevice = false;
    _place = place;
    _forget();
    _keep();
    notifyListeners();
    unawaited(refresh(force: true));
  }

  /// Drops the forecast, and any being fetched: it's not for what's
  /// picked now.
  void _forget() {
    _generation++;
    _forecast = null;
    _error = null;
    _fetching = null;
  }

  void _keep() {
    if (!persist) return;
    try {
      final prefs = SharedPreferencesAsync();
      prefs.setBool(_enabledKey, _enabled).catchError((_) {});
      prefs.setBool(_usesDeviceKey, _usesDevice).catchError((_) {});
      if (_place case final place?) {
        prefs.setDouble(_latitudeKey, place.latitude).catchError((_) {});
        prefs.setDouble(_longitudeKey, place.longitude).catchError((_) {});
      }
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Fetches a forecast for where it's for, if it's on, knows where -- for
  /// where the device is, checking, without asking, if it hasn't -- and
  /// the last is older than [maxAge] -- or whatever its age, with [force]
  /// -- unless one's being fetched already.
  Future<void> refresh({bool force = false}) {
    if (!_enabled) return Future.value();
    if (!located && !(_usesDevice && _access == null)) return Future.value();
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
    if (_usesDevice && _access == null) {
      await _checkAccess();
      if (!located) {
        if (generation == _generation) {
          _fetching = null;
          notifyListeners();
        }
        return;
      }
    }
    try {
      final at = _usesDevice ? await location.current() : _place!;
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
