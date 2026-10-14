import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';

/// Where on Earth, in degrees.
@immutable
class Coordinates {
  const Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// The place [text] holds, if that's all it holds: a latitude and a
  /// longitude as a maps app copies them -- "47.6062, -122.3321", or
  /// "47.6062° N, 122.3321° W" -- in range; otherwise null.
  static Coordinates? tryParse(String text) {
    final match = RegExp(
      r'^\s*\(?\s*(-?\d+(?:\.\d+)?)\s*°?\s*([NS])?\s*[,;\s]\s*'
      r'(-?\d+(?:\.\d+)?)\s*°?\s*([EW])?\s*\)?\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    var latitude = double.parse(match[1]!);
    var longitude = double.parse(match[3]!);
    if (match[2]?.toUpperCase() == 'S') latitude = -latitude;
    if (match[4]?.toUpperCase() == 'W') longitude = -longitude;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return Coordinates(latitude, longitude);
  }

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

/// What a background fetch of the weather did: when, and why it
/// couldn't, if it couldn't.
@immutable
class WeatherRefreshRecord {
  const WeatherRefreshRecord({required this.at, this.problem});

  final DateTime at;
  final String? problem;

  bool get ok => problem == null;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'problem': ?problem,
  };

  static WeatherRefreshRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return WeatherRefreshRecord(
      at: at.toLocal(),
      problem: json['problem'] as String?,
    );
  }
}

/// What's kept of the weather on the device, for the app and its
/// background task to share: what's picked (on or off, where for), the
/// last forecast and where it was for, where the device was last found
/// while the app was open, and what the last background fetch did. Best
/// effort, each.
abstract final class KeptWeather {
  static const enabledKey = 'weather_enabled';
  static const usesDeviceKey = 'weather_uses_device';
  static const latitudeKey = 'weather_latitude';
  static const longitudeKey = 'weather_longitude';
  static const _forecastKey = 'weather_forecast';
  static const _deviceKey = 'weather_device_place';
  static const _backgroundKey = 'weather_background_last';

  static Map<String, Object?> _place(Coordinates at) => {
    'lat': at.latitude,
    'lon': at.longitude,
  };

  static Coordinates? _placeOf(Object? json) => switch (json) {
    {'lat': final num lat, 'lon': final num lon} => Coordinates(
      lat.toDouble(),
      lon.toDouble(),
    ),
    _ => null,
  };

  static Future<Object?> _json(String key) async {
    try {
      final text = await SharedPreferencesAsync().getString(key);
      return text == null ? null : jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _keep(String key, Object? json) async {
    try {
      await SharedPreferencesAsync().setString(key, jsonEncode(json));
    } catch (_) {
      // Not kept, then.
    }
  }

  /// The last forecast, whether it was for where the device was, and the
  /// place it was for, rounded.
  static Future<({Forecast forecast, bool device, Coordinates at})?>
  forecast() async {
    final json = await _json(_forecastKey);
    if (json is! Map) return null;
    final forecast = Forecast.fromJson(json['forecast']);
    final at = _placeOf(json['at']);
    if (forecast == null || at == null) return null;
    return (forecast: forecast, device: json['device'] == true, at: at);
  }

  /// Keeps [forecast], in place of the last.
  static Future<void> keepForecast(
    Forecast forecast, {
    required bool device,
    required Coordinates at,
  }) => _keep(_forecastKey, {
    'device': device,
    'at': _place(at),
    'forecast': forecast.toJson(),
  });

  /// Where the device was last found, rounded, while the app was open.
  static Future<Coordinates?> devicePlace() async =>
      _placeOf(await _json(_deviceKey));

  static Future<void> keepDevicePlace(Coordinates at) =>
      _keep(_deviceKey, _place(at));

  /// What the last background fetch did; null if there's been none.
  static Future<WeatherRefreshRecord?> lastBackground() async =>
      WeatherRefreshRecord.fromJson(await _json(_backgroundKey));

  static Future<void> keepBackground(WeatherRefreshRecord record) =>
      _keep(_backgroundKey, record.toJson());
}

/// Fetches the weather in the background, if it's on, for where it's for
/// -- for where the device is, where it was last found while the app was
/// open: it never asks where the device is now, so needs no permission to
/// in the background. Keeps the forecast, in place of the last, for the
/// app to show as it opens, and what it did; null if the weather's off.
Future<WeatherRefreshRecord?> refreshWeatherInBackground({
  required ForecastSource forecasts,
  DateTime Function() clock = DateTime.now,
}) async {
  bool enabled;
  bool device;
  Coordinates? place;
  try {
    final prefs = SharedPreferencesAsync();
    enabled = await prefs.getBool(KeptWeather.enabledKey) ?? false;
    device = await prefs.getBool(KeptWeather.usesDeviceKey) ?? false;
    final lat = await prefs.getDouble(KeptWeather.latitudeKey);
    final lon = await prefs.getDouble(KeptWeather.longitudeKey);
    if (lat != null && lon != null) place = Coordinates(lat, lon);
  } catch (_) {
    return null;
  }
  if (!enabled) return null;
  final at = device ? await KeptWeather.devicePlace() : place?.rounded;
  WeatherRefreshRecord record;
  if (at == null) {
    record = WeatherRefreshRecord(
      at: clock(),
      problem: device
          ? "The device hasn't been found yet: open the app for that."
          : 'No place is given.',
    );
  } else {
    try {
      final forecast = await forecasts.fetch(at, now: clock());
      await KeptWeather.keepForecast(forecast, device: device, at: at);
      record = WeatherRefreshRecord(at: clock());
    } catch (e) {
      final problem = '$e';
      record = WeatherRefreshRecord(
        at: clock(),
        problem: problem.isEmpty ? "Couldn't get the forecast." : problem,
      );
    }
  }
  await KeptWeather.keepBackground(record);
  return record;
}

/// Whether the weather's shown, where for, and its latest forecast: each
/// one fetched replaces the last whole. It's for a [place] the user
/// gives -- to start -- or, if they pick it, for where the device is
/// ([usesDevice]), asked only then.
/// What's picked is kept on this device ([persist]); the forecast only
/// while the app runs.
class Weather extends ChangeNotifier {
  Weather({
    required this.forecasts,
    required this.location,
    this.persist = true,
    this._enabled = false,
    this._usesDevice = false,
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

  static const _enabledKey = KeptWeather.enabledKey;
  static const _usesDeviceKey = KeptWeather.usesDeviceKey;
  static const _latitudeKey = KeptWeather.latitudeKey;
  static const _longitudeKey = KeptWeather.longitudeKey;

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

  var _loaded = false;

  /// Whether what's kept on the device has been read ([load]), so what's
  /// picked is known.
  bool get loaded => _loaded;

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
    await _adoptKept();
    _loaded = true;
    notifyListeners();
    await refresh();
  }

  /// The forecast kept on the device -- the last fetched, here or in the
  /// background -- if it's newer than this one, and for where it's for
  /// now: shown at once, till a newer one comes.
  Future<void> _adoptKept() async {
    if (!persist || !_enabled) return;
    final generation = _generation;
    final kept = await KeptWeather.forecast();
    if (kept == null || generation != _generation) return;
    final matches = kept.device
        ? _usesDevice
        : !_usesDevice && kept.at == _place?.rounded;
    final last = _forecast;
    if (!matches ||
        (last != null && !kept.forecast.fetchedAt.isAfter(last.fetchedAt))) {
      return;
    }
    _forecast = kept.forecast;
    notifyListeners();
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
  Future<void> refresh({bool force = false}) async {
    if (!_enabled) return;
    // Fetched in the background, maybe, since.
    if (!force && _fetching == null) await _adoptKept();
    if (!_enabled) return;
    if (!located && !(_usesDevice && _access == null)) return;
    if (_fetching case final fetching?) return fetching;
    final last = _forecast;
    if (!force &&
        _error == null &&
        last != null &&
        _clock().difference(last.fetchedAt) < maxAge) {
      return;
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
      final at = (_usesDevice ? await location.current() : _place!).rounded;
      final fetched = await forecasts.fetch(at, now: _clock());
      forecast = fetched;
      if (persist && generation == _generation) {
        // For the background fetch: where to, and what it had.
        if (_usesDevice) await KeptWeather.keepDevicePlace(at);
        await KeptWeather.keepForecast(fetched, device: _usesDevice, at: at);
      }
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
