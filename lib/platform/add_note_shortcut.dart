import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Taps on the Android home screen "+" widget (AddNoteWidget.kt), as the
/// time of each tap. Each one should open the New note dialog.
///
/// A tap that launched the app from scratch comes before anything is
/// listening, so [taps] buffers until the first listener.
class AddNoteShortcut {
  AddNoteShortcut({MethodChannel? channel, bool? enabled})
    : _channel =
          channel ?? const MethodChannel('time_tracker/add_note_shortcut'),
      _enabled =
          enabled ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _enabled;
  final _taps = StreamController<DateTime>();

  Stream<DateTime> get taps => _taps.stream;

  /// Call once the app is running, after runApp.
  Future<void> start() async {
    if (!_enabled) return;
    // Taps while the app is already running.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'addNote') _taps.add(_time(call.arguments));
    });
    // The tap that launched it, if one did.
    try {
      final launchedAt = await _channel.invokeMethod<int>('takeLaunchRequest');
      if (launchedAt != null) _taps.add(_time(launchedAt));
    } on PlatformException catch (e) {
      debugPrint('Home screen widget unavailable: $e');
    }
  }

  void dispose() {
    if (_enabled) _channel.setMethodCallHandler(null);
    _taps.close();
  }

  static DateTime _time(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis as int);
}
