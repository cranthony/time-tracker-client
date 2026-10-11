import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../models/event.dart';
import '../models/plan_action.dart';
import '../services/event_store.dart';
import '../widgets/day_timeline.dart' show eventColor;

/// A tap on the Android home screen calendar: on an event, its time and
/// id; on a day's header, that day's start; on the widget's own header,
/// neither, for now.
typedef CalendarTap = ({DateTime? at, String? eventId});

/// The Android home screen calendar (CalendarWidget.kt): the events from
/// now to a few days ahead, under a header for each day.
///
/// The widget can't ask the app for them as it's drawn, so [publish]
/// keeps them where it reads them -- a snapshot of the days kept in an
/// [EventStore] -- and has it drawn again. The widget leaves out what's
/// over as it's drawn, and [publish] has it drawn again as each event
/// starts or ends, and as each day does, so it always starts at now.
///
/// Taps on it open the app on Events ([taps]): at the event tapped, or
/// the day, or now. Its "+" opens the New note dialog, as the add-note
/// widget does (see AddNoteShortcut).
///
/// Best effort: anything that goes wrong just leaves the widget as it
/// was. Elsewhere than Android it does nothing.
class CalendarWidget {
  CalendarWidget({
    CalendarWidgetHost? host,
    MethodChannel? channel,
    bool? enabled,
  }) : _host = host ?? const HomeWidgetHost(),
       _channel = channel ?? const MethodChannel(channelName),
       enabled =
           enabled ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const channelName = 'time_tracker/calendar_widget';

  /// How many days it shows, today first.
  static const days = 4;

  final CalendarWidgetHost _host;
  final MethodChannel _channel;
  final bool enabled;
  final _taps = StreamController<CalendarTap>();

  /// What was last published, to publish again only when it changes;
  /// [_unpublished] until the first.
  Object? _published = _unpublished;
  static const _unpublished = Object();

  /// Taps on the widget, a tap that launched the app among them, buffered
  /// until the first listener.
  Stream<CalendarTap> get taps => _taps.stream;

  /// Keeps [store]'s events from [now] to [days] days ahead -- the
  /// colors from [actions] -- for the widget, and has it drawn again,
  /// unless they're as they were.
  Future<void> publish(
    EventStore store, {
    Iterable<PlanAction> actions = const [],
    DateTime? now,
  }) async {
    if (!enabled) return;
    await store.restored();
    final snapshot = calendarSnapshot(
      store,
      actions: actions,
      now: now ?? DateTime.now(),
    );
    final json = snapshot == null ? null : jsonEncode(snapshot);
    if (json == _published) return;
    try {
      await _host.save(json);
      await _host.schedule(redrawTimes(snapshot));
      await _host.redraw();
      _published = json;
    } on Exception catch (e) {
      debugPrint('Home screen calendar unavailable: $e');
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
      debugPrint('Home screen calendar unavailable: $e');
    }
  }

  void dispose() {
    if (enabled) _channel.setMethodCallHandler(null);
    _taps.close();
  }

  static CalendarTap _tap(Object? arguments) {
    final map = arguments is Map ? arguments : const {};
    return (
      at: switch (map['at']) {
        final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
        _ => null,
      },
      eventId: map['event'] as String?,
    );
  }
}

/// [store]'s events for the widget, from [now], for each day from today
/// that it has, up to [CalendarWidget.days]: each day's start and end
/// (milliseconds since the epoch), and the events in it, by start --
/// one across midnight in each day it's in -- each with its [eventColor]
/// from [actions]. Null if it hasn't today's: there's nothing to show.
Map<String, Object?>? calendarSnapshot(
  EventStore store, {
  Iterable<PlanAction> actions = const [],
  required DateTime now,
}) {
  final byId = {for (final a in actions) ?a.id: a};
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < CalendarWidget.days; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    final next = DateTime(now.year, now.month, now.day + i + 1);
    if (!store.has(day)) break;
    final from = i == 0 ? now : day;
    days.add({
      'start': day.millisecondsSinceEpoch,
      'end': next.millisecondsSinceEpoch,
      'events': [
        for (final e in store.between(from, next))
          if (!e.isCancelled) _event(e, byId),
      ],
    });
  }
  if (days.isEmpty) return null;
  return {'days': days};
}

Map<String, Object?> _event(Event e, Map<String, PlanAction> actions) => {
  'id': e.id,
  'summary': e.summary,
  'start': e.start.millisecondsSinceEpoch,
  'end': e.end.millisecondsSinceEpoch,
  'color': eventColor(e, actions).toARGB32(),
};

/// When the widget showing [snapshot] needs drawing again: as each of its
/// events starts and ends, and as each day ends -- in order, each once.
List<DateTime> redrawTimes(Map<String, Object?>? snapshot) {
  final times = <int>{};
  for (final day in (snapshot?['days'] as List?) ?? const []) {
    final d = day as Map;
    times.add(d['end'] as int);
    for (final e in d['events'] as List) {
      times
        ..add((e as Map)['start'] as int)
        ..add(e['end'] as int);
    }
  }
  return [
    for (final t in times.toList()..sort())
      DateTime.fromMillisecondsSinceEpoch(t),
  ];
}

/// Where [CalendarWidget] keeps the widget's snapshot, and has it drawn.
abstract class CalendarWidgetHost {
  /// Keeps [snapshot] (JSON) for the widget; null for none.
  Future<void> save(String? snapshot);

  /// Has the widget drawn again at [times], in place of those before.
  Future<void> schedule(List<DateTime> times);

  /// Has the widget drawn again now.
  Future<void> redraw();
}

/// [CalendarWidgetHost] by the home_widget plugin, which works from the
/// background task too.
class HomeWidgetHost implements CalendarWidgetHost {
  const HomeWidgetHost();

  /// Where CalendarWidget.kt reads it.
  static const snapshotKey = 'calendar_snapshot';
  static const _receiver = 'com.cranthony.timetracker.CalendarWidgetReceiver';

  @override
  Future<void> save(String? snapshot) =>
      HomeWidget.saveWidgetData<String>(snapshotKey, snapshot);

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
}
