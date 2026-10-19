import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Taps on the Android home screen "+" widget (AddNoteWidget.kt), as the
/// time of each tap -- each should open the New note dialog -- and on the
/// goal widget (AddGoalWidget.kt), as [goalTaps]: each should open the New
/// goal sheet.
///
/// A tap that launched the app from scratch comes before anything is
/// listening, so [taps] and [goalTaps] buffer until their first listener.
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
  final _goalTaps = StreamController<DateTime>();

  Stream<DateTime> get taps => _taps.stream;
  Stream<DateTime> get goalTaps => _goalTaps.stream;

  /// Call once the app is running, after runApp.
  Future<void> start() async {
    if (!_enabled) return;
    // Taps while the app is already running.
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'addNote':
          _taps.add(_time(call.arguments));
        case 'addGoal':
          _goalTaps.add(_time(call.arguments));
      }
    });
    // The tap that launched it, if one did.
    try {
      final launchedAt = await _channel.invokeMethod<int>('takeLaunchRequest');
      if (launchedAt != null) _taps.add(_time(launchedAt));
      final goalAt = await _channel.invokeMethod<int>('takeGoalLaunchRequest');
      if (goalAt != null) _goalTaps.add(_time(goalAt));
    } on PlatformException catch (e) {
      debugPrint('Home screen widget unavailable: $e');
    }
  }

  /// Tells Android the New note dialog, or New goal sheet, opened for a
  /// tap has its field focused, so it can show the keyboard once its window has focus too.
  Future<void> fieldReady() async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>('fieldReady');
    } on PlatformException catch (e) {
      debugPrint('Home screen widget unavailable: $e');
    }
  }

  void dispose() {
    if (_enabled) _channel.setMethodCallHandler(null);
    _taps.close();
    _goalTaps.close();
  }

  static DateTime _time(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis as int);
}
