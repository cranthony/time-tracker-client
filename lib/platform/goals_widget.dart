import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../models/goal.dart';
import '../widgets/color_picker.dart' show priorityColor;

/// A tap on the Android home screen goals: on a goal, its id; on the
/// widget's own header, none.
typedef GoalsTap = ({String? goalId});

/// The Android home screen goals (GoalsWidget.kt): every active goal,
/// the soonest due first, each with when it's due.
///
/// The widget can't ask the app for them as it's drawn, so [publish]
/// keeps them where it reads them -- a snapshot of the goals -- and has
/// it drawn again. The widget tells the overdue from the rest as it's
/// drawn, and names each's day from today, so [publish] has it drawn
/// again as each falls due, and as each day ends.
///
/// The background refresh task publishes too, from its own isolate, so
/// what's kept for the widget may not be what this instance last kept:
/// [publish] compares with what's kept ([GoalsWidgetHost.kept]), not
/// with what it kept last, so the app's view wins once it's looked at
/// again, as the calendar's does (see CalendarWidget).
///
/// Taps on it open the app ([taps]): a goal's page, or the Plan page's
/// Goals. Its button opens the New goal sheet, as the add-goal widget
/// does (see AddNoteShortcut).
///
/// Best effort: anything that goes wrong just leaves the widget as it
/// was. Elsewhere than Android it does nothing.
class GoalsWidget {
  GoalsWidget({GoalsWidgetHost? host, MethodChannel? channel, bool? enabled})
    : _host = host ?? const HomeWidgetGoalsHost(),
      _channel = channel ?? const MethodChannel(channelName),
      enabled =
          enabled ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const channelName = 'time_tracker/goals_widget';

  /// How many days ahead it's had drawn again at midnight, for the days'
  /// names to move on, should the app not run meanwhile.
  static const redrawDays = 7;

  /// Whether the app menu offers to add the widget to the home screen:
  /// only in builds for the emulator test, which can't add it otherwise
  /// (tool/emulator/goals_widget_test.sh):
  ///   flutter build apk --dart-define=GOALS_PIN=true
  static const pinOffered = bool.fromEnvironment('GOALS_PIN');

  /// Asks Android to add the widget to the home screen; it asks first.
  static Future<void> pin({
    GoalsWidgetHost host = const HomeWidgetGoalsHost(),
  }) async {
    try {
      await host.pin();
    } on Exception catch (e) {
      debugPrint('Home screen goals unavailable: $e');
    }
  }

  final GoalsWidgetHost _host;
  final MethodChannel _channel;
  final bool enabled;
  final _taps = StreamController<GoalsTap>();

  /// Taps on the widget, a tap that launched the app among them, buffered
  /// until the first listener.
  Stream<GoalsTap> get taps => _taps.stream;

  /// Keeps the active ones of [goals] for the widget, as of [now], and
  /// has it drawn again, unless they're as what's kept for it -- by this
  /// instance, or by the background task's. Null, they aren't known --
  /// signed out, say: it says to open the app.
  Future<void> publish(Iterable<Goal>? goals, {DateTime? now}) async {
    if (!enabled) return;
    final snapshot = goals == null
        ? null
        : goalsSnapshot(goals, now: now ?? DateTime.now());
    final json = snapshot == null ? null : jsonEncode(snapshot);
    try {
      if (json == await _host.kept()) return;
      await _host.save(json);
      await _host.schedule(goalsRedrawTimes(snapshot));
      await _host.redraw();
    } on Exception catch (e) {
      debugPrint('Home screen goals unavailable: $e');
    }
  }

  /// Call once the app is running, after runApp.
  Future<void> start() async {
    if (!enabled) return;
    // Taps while the app is already running.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'show') _taps.add(_tap(call.arguments));
    });
    // The tap that launched it, if one did.
    try {
      final launched = await _channel.invokeMethod<Object?>(
        'takeLaunchRequest',
      );
      if (launched != null) _taps.add(_tap(launched));
    } on PlatformException catch (e) {
      debugPrint('Home screen goals unavailable: $e');
    }
  }

  void dispose() {
    if (enabled) _channel.setMethodCallHandler(null);
    _taps.close();
  }

  static GoalsTap _tap(Object? arguments) {
    final map = arguments is Map ? arguments : const {};
    return (goalId: map['goal'] as String?);
  }
}

/// The active ones of [goals] for the widget, the soonest due first
/// ([compareByDeadline]; those with no deadline last, by title): each's
/// id and title, when it's due (milliseconds since the epoch; a date's
/// at the midnight after it), whether that's a time of day, not just a
/// date, and its color (ARGB), for the bar beside it: the color of the
/// priority that applies to it -- its own, or its nearest parent's among
/// [goals] ([GoalTree.priorityOf]) -- as the app's lists color it
/// ([priorityColor]). With the day it's as of ([now]'s), so it's
/// published anew each day, which sets the redraws at the midnights
/// ahead again.
Map<String, Object?> goalsSnapshot(
  Iterable<Goal> goals, {
  required DateTime now,
}) {
  final tree = GoalTree(goals);
  final active = [
    for (final g in goals)
      if (g.active) g,
  ]..sort(compareByDeadline);
  return {
    'today': DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
    'goals': [
      for (final g in active)
        {
          'id': g.id,
          'title': g.title,
          if (g.due case final due?) 'due': due.millisecondsSinceEpoch,
          'has_time': deadlineHasTime(g.deadline),
          'color': priorityColor(tree.priorityOf(g.id)).toARGB32(),
        },
    ],
  };
}

/// When the widget showing [snapshot] needs drawing again: as each of its
/// goals falls due -- those not due yet as of its day -- and at each
/// midnight for [GoalsWidget.redrawDays] days from it, for the days'
/// names; in order, each once. None for no snapshot.
List<DateTime> goalsRedrawTimes(Map<String, Object?>? snapshot) {
  if (snapshot == null) return const [];
  final today = DateTime.fromMillisecondsSinceEpoch(snapshot['today'] as int);
  final times = <int>{
    for (var i = 1; i <= GoalsWidget.redrawDays; i++)
      DateTime(today.year, today.month, today.day + i).millisecondsSinceEpoch,
    for (final g in snapshot['goals'] as List)
      if ((g as Map)['due'] case final int due
          when due > today.millisecondsSinceEpoch)
        due,
  };
  return [
    for (final t in times.toList()..sort())
      DateTime.fromMillisecondsSinceEpoch(t),
  ];
}

/// Where [GoalsWidget] keeps the widget's snapshot, and has it drawn.
abstract class GoalsWidgetHost {
  /// Keeps [snapshot] (JSON) for the widget; null for none.
  Future<void> save(String? snapshot);

  /// The snapshot kept for the widget, by whichever isolate [save]d it
  /// last; null for none.
  Future<String?> kept();

  /// Has the widget drawn again at [times], in place of those before.
  Future<void> schedule(List<DateTime> times);

  /// Has the widget drawn again now.
  Future<void> redraw();

  /// Asks to add the widget to the home screen.
  Future<void> pin();
}

/// [GoalsWidgetHost] by the home_widget plugin, which works from the
/// background task too.
class HomeWidgetGoalsHost implements GoalsWidgetHost {
  const HomeWidgetGoalsHost();

  /// Where GoalsWidget.kt reads it.
  static const snapshotKey = 'goals_snapshot';
  static const _receiver = 'com.cranthony.timetracker.GoalsWidgetReceiver';

  @override
  Future<void> save(String? snapshot) =>
      HomeWidget.saveWidgetData<String>(snapshotKey, snapshot);

  @override
  Future<String?> kept() => HomeWidget.getWidgetData<String>(snapshotKey);

  @override
  Future<void> schedule(List<DateTime> times) => times.isEmpty
      ? HomeWidget.cancelScheduledWidgetUpdates(qualifiedAndroidName: _receiver)
      : HomeWidget.scheduleWidgetUpdates(
          times,
          qualifiedAndroidName: _receiver,
        );

  @override
  Future<void> redraw() =>
      HomeWidget.updateWidget(qualifiedAndroidName: _receiver);

  @override
  Future<void> pin() =>
      HomeWidget.requestPinWidget(qualifiedAndroidName: _receiver);
}
