import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/plan_action.dart';
import '../models/weather.dart';
import '../services/app_settings.dart';
import '../services/weather.dart';
import '../services/event_store.dart';
import '../widgets/day_timeline.dart' show eventColor;
import '../widgets/goals_due_strip.dart' show goalsDueOn;

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
/// Above each day's events are the active goals due that day: the two
/// due soonest, and how many more there are.
///
/// The background refresh task publishes too, from its own isolate, so
/// what's kept for the widget may not be what this instance last kept:
/// [publish] compares with what's kept ([CalendarWidgetHost.kept]), not
/// with what it kept last, so the app's view wins once it's looked at
/// again -- a goal closed in the app that the task, fetching the goals
/// before the change was sent, still had open, say.
///
/// Each day's header also gives its weather, if it's on: its sky's icon,
/// its chance of rain -- today's from now -- and its high and low, the
/// rest of today's for today. [publishWeather] keeps those apart from the
/// events, so a forecast fetched in the background redraws it without
/// them.
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

  /// Whether the app menu offers to add the widget to the home screen:
  /// only in builds for the emulator test, which can't add it otherwise
  /// (tool/emulator/calendar_widget_test.sh):
  ///   flutter build apk --dart-define=CALENDAR_PIN=true
  static const pinOffered = bool.fromEnvironment('CALENDAR_PIN');

  /// Asks Android to add the widget to the home screen; it asks first.
  static Future<void> pin({
    CalendarWidgetHost host = const HomeWidgetHost(),
  }) async {
    try {
      await host.pin();
    } on Exception catch (e) {
      debugPrint('Home screen calendar unavailable: $e');
    }
  }

  final CalendarWidgetHost _host;
  final MethodChannel _channel;
  final bool enabled;
  final _taps = StreamController<CalendarTap>();

  /// The weather last published, to publish again only when it changes;
  /// [_unpublished] until the first.
  Object? _weatherPublished = _unpublished;
  static const _unpublished = Object();

  /// Taps on the widget, a tap that launched the app among them, buffered
  /// until the first listener.
  Stream<CalendarTap> get taps => _taps.stream;

  /// Keeps [store]'s events from [now] to [days] days ahead -- the
  /// colors from [actions] -- and the [goals] due those days for the
  /// widget, and has it drawn again, unless they're as what's kept for
  /// it -- by this instance, or by the background task's.
  Future<void> publish(
    EventStore store, {
    Iterable<PlanAction> actions = const [],
    Iterable<Goal> goals = const [],
    DateTime? now,
  }) async {
    if (!enabled) return;
    await store.restored();
    final snapshot = calendarSnapshot(
      store,
      actions: actions,
      goals: goals,
      now: now ?? DateTime.now(),
    );
    final json = snapshot == null ? null : jsonEncode(snapshot);
    try {
      if (json == await _host.kept()) return;
      await _host.save(json);
      await _host.schedule(redrawTimes(snapshot));
      await _host.redraw();
    } on Exception catch (e) {
      debugPrint('Home screen calendar unavailable: $e');
    }
  }

  /// Keeps [forecast]'s days' weather for the widget's headers, its
  /// temperatures in [unit], and has it drawn again, unless it's as it
  /// was; null, the weather's off: none.
  Future<void> publishWeather(
    Forecast? forecast, {
    TemperatureUnit unit = TemperatureUnit.fahrenheit,
  }) async {
    if (!enabled) return;
    final weather = forecast == null
        ? null
        : jsonEncode(calendarWeather(forecast, unit: unit));
    if (weather == _weatherPublished) return;
    try {
      await _host.saveWeather(weather);
      await _host.redraw();
      _weatherPublished = weather;
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
/// from [actions] -- and the active [goals] due in it, as [goalsDueOn] has them. Null
/// if it hasn't today's: there's nothing to show.
Map<String, Object?>? calendarSnapshot(
  EventStore store, {
  Iterable<PlanAction> actions = const [],
  Iterable<Goal> goals = const [],
  required DateTime now,
}) {
  final byId = {for (final a in actions) ?a.id: a};
  // Every goal, for the priorities the active ones inherit.
  final tree = GoalTree(goals);
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < CalendarWidget.days; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    final next = DateTime(now.year, now.month, now.day + i + 1);
    if (!store.has(day)) break;
    final from = i == 0 ? now : day;
    final due = goalsDueOn(goals.where((g) => g.active), day, tree);
    days.add({
      'start': day.millisecondsSinceEpoch,
      'end': next.millisecondsSinceEpoch,
      if (due.isNotEmpty)
        'goals': [
          for (final g in due.take(2)) {'id': g.id, 'title': g.title},
        ],
      if (due.length > 2) 'more_goals': due.length - 2,
      'events': [
        for (final e in store.between(from, next))
          if (!e.isCancelled) _event(e, byId),
      ],
    });
  }
  if (days.isEmpty) return null;
  return {'days': days};
}

/// Keeps [widget]'s headers' weather as [weather] has it: each forecast
/// as it comes, in the [settings]' temperature unit, and none while it's
/// off -- not till it's known whether it's on, so as not to clear it as
/// the app opens.
class CalendarWeatherLink {
  CalendarWeatherLink({
    required this.widget,
    required this.weather,
    required this.settings,
  }) {
    weather.addListener(_changed);
    settings.addListener(_changed);
    _changed();
  }

  final CalendarWidget widget;
  final Weather weather;
  final AppSettings settings;

  void _changed() {
    if (!weather.loaded) return;
    unawaited(
      widget.publishWeather(
        weather.enabled ? weather.forecast : null,
        unit: settings.temperatureUnit,
      ),
    );
  }

  void dispose() {
    weather.removeListener(_changed);
    settings.removeListener(_changed);
  }
}

/// [forecast]'s days for the widget's headers, by their midnights
/// (milliseconds since the epoch): each's sky as an [skyEmoji], its chance
/// of rain if it's more than none, and its high and low in [unit] -- in
/// full, and [compact] for a narrow widget -- or one temperature where
/// they round the same. Today's are from when it was fetched: what's left
/// of it.
Map<String, Object?> calendarWeather(
  Forecast forecast, {
  TemperatureUnit unit = TemperatureUnit.fahrenheit,
}) => {
  'days': [
    for (final day in forecast.days)
      {
        'start': DateTime(
          day.start.year,
          day.start.month,
          day.start.day,
        ).millisecondsSinceEpoch,
        'icon': skyEmoji(day.sky, daytime: day.daytime),
        if (day.rainChance case final chance? when chance > 0)
          'rain': '$chance%',
        ...?_temperatures(day, unit),
      },
  ],
};

/// [day]'s high and low, as "72° / 55°" and, compact, "72/55°"; one
/// temperature where they round the same.
Map<String, String>? _temperatures(WeatherSpan day, TemperatureUnit unit) {
  final (high, low) = (day.high, day.low);
  if (high == null || low == null) return null;
  final (h, l) = (unit.format(high), unit.format(low));
  if (h == l) return {'temps': h, 'temps_compact': h};
  return {'temps': '$h / $l', 'temps_compact': '${h.replaceAll('°', '')}/$l'};
}

/// [sky] as an emoji, for the widget, which draws text more easily than
/// icons: a clear night's a moon.
String skyEmoji(Sky sky, {bool daytime = true}) => switch (sky) {
  Sky.clear => daytime ? '☀️' : '🌙',
  Sky.partlyCloudy => daytime ? '⛅' : '☁️',
  Sky.cloudy => '☁️',
  Sky.fog => '🌫️',
  Sky.drizzle => '🌦️',
  Sky.rain => '🌧️',
  Sky.snow => '🌨️',
  Sky.thunderstorm => '⛈️',
};

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

  /// The snapshot kept for the widget, by whichever isolate [save]d it
  /// last; null for none.
  Future<String?> kept();

  /// Keeps [weather] (JSON, see [calendarWeather]) for the widget's
  /// headers; null for none.
  Future<void> saveWeather(String? weather);

  /// Has the widget drawn again at [times], in place of those before.
  Future<void> schedule(List<DateTime> times);

  /// Has the widget drawn again now.
  Future<void> redraw();

  /// Asks to add the widget to the home screen.
  Future<void> pin();
}

/// [CalendarWidgetHost] by the home_widget plugin, which works from the
/// background task too.
class HomeWidgetHost implements CalendarWidgetHost {
  const HomeWidgetHost();

  /// Where CalendarWidget.kt reads it.
  static const snapshotKey = 'calendar_snapshot';

  /// Where CalendarWidget.kt reads the weather.
  static const weatherKey = 'calendar_weather';
  static const _receiver = 'com.cranthony.timetracker.CalendarWidgetReceiver';

  @override
  Future<void> save(String? snapshot) =>
      HomeWidget.saveWidgetData<String>(snapshotKey, snapshot);

  @override
  Future<String?> kept() => HomeWidget.getWidgetData<String>(snapshotKey);

  @override
  Future<void> saveWeather(String? weather) =>
      HomeWidget.saveWidgetData<String>(weatherKey, weather);

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
