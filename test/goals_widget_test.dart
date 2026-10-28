import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/platform/goals_widget.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';

/// Today, at noon.
final _now = DateTime(2026, 10, 8, 12);

Goal _goal(
  String id, {
  String status = 'active',
  String? deadline,
  String? parentId,
  int? priority,
  String? backgroundColor,
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'status': status,
  'deadline': ?deadline,
  'parent_id': ?parentId,
  'priority': ?priority,
  'background_color': ?backgroundColor,
});

/// The snapshot's goals' ids, in order.
List<String> _ids(Map<String, Object?> snapshot) => [
  for (final g in snapshot['goals'] as List) (g as Map)['id'] as String,
];

class _FakeHost implements GoalsWidgetHost {
  final saved = <String?>[];
  final scheduled = <List<DateTime>>[];
  var redraws = 0;
  var pins = 0;

  @override
  Future<void> save(String? snapshot) async => saved.add(snapshot);

  /// What was saved last -- by the widget under test, or added to [saved]
  /// by a test, as the background task would save it from its isolate.
  @override
  Future<String?> kept() async => saved.lastOrNull;

  @override
  Future<void> schedule(List<DateTime> times) async => scheduled.add(times);

  @override
  Future<void> redraw() async => redraws++;

  @override
  Future<void> pin() async => pins++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('goalsSnapshot', () {
    final goals = [
      _goal('later', deadline: '2026-10-10'),
      _goal('today-at-five', deadline: '2026-10-08T17:00'),
      _goal('undated'),
      _goal('today', deadline: '2026-10-08'),
      _goal('done', status: 'done', deadline: '2026-10-08'),
      _goal('waiting', status: 'inactive'),
      _goal('late', deadline: '2026-10-07'),
    ];

    test('the active goals, the soonest due first; undated last', () {
      final snapshot = goalsSnapshot(goals, now: _now);
      expect(_ids(snapshot), [
        'late',
        'today-at-five',
        'today',
        'later',
        'undated',
      ]);
    });

    test('each with when it is due: a date at the midnight after it', () {
      final shown = (goalsSnapshot(goals, now: _now)['goals'] as List)
          .cast<Map>();
      expect(shown[1], {
        'id': 'today-at-five',
        'title': 'today-at-five',
        'due': DateTime(2026, 10, 8, 17).millisecondsSinceEpoch,
        'has_time': true,
        'color': priorityColor(defaultGoalPriority).toARGB32(),
      });
      expect(shown[2], {
        'id': 'today',
        'title': 'today',
        'due': DateTime(2026, 10, 9).millisecondsSinceEpoch,
        'has_time': false,
        'color': priorityColor(defaultGoalPriority).toARGB32(),
      });
      expect(shown[4], {
        'id': 'undated',
        'title': 'undated',
        'has_time': false,
        'color': priorityColor(defaultGoalPriority).toARGB32(),
      });
    });

    test("each colored by its priority: its own, or its nearest parent's "
        'that has one, though the parent is not active itself', () {
      final shown =
          (goalsSnapshot([
                    _goal('project', priority: 1, status: 'done'),
                    _goal('piece', parentId: 'project'),
                    _goal('step', parentId: 'piece'),
                    _goal('urgent', parentId: 'project', priority: 0),
                  ], now: _now)['goals']
                  as List)
              .cast<Map>();
      expect(
        {for (final g in shown) g['id']: g['color']},
        {
          'piece': priorityColor(1).toARGB32(),
          'step': priorityColor(1).toARGB32(),
          'urgent': priorityColor(0).toARGB32(),
        },
      );
      expect(priorityColor(0), isNot(priorityColor(1)));
    });

    test("each colored by its own color, or its nearest parent's that "
        "has one, else its priority's", () {
      final shown =
          (goalsSnapshot([
                    _goal('project', priority: 1, backgroundColor: '#123456'),
                    _goal('piece', parentId: 'project'),
                    _goal(
                      'step',
                      parentId: 'piece',
                      backgroundColor: '#654321',
                    ),
                    _goal('plain', priority: 0),
                  ], now: _now)['goals']
                  as List)
              .cast<Map>();
      expect(
        {for (final g in shown) g['id']: g['color']},
        {
          'project': 0xFF123456,
          'piece': 0xFF123456,
          'step': 0xFF654321,
          'plain': priorityColor(0).toARGB32(),
        },
      );
    });

    test('is as of the day, so it changes with it', () {
      expect(
        goalsSnapshot(goals, now: _now)['today'],
        DateTime(2026, 10, 8).millisecondsSinceEpoch,
      );
      expect(
        goalsSnapshot(goals, now: _now.add(const Duration(hours: 13)))['today'],
        DateTime(2026, 10, 9).millisecondsSinceEpoch,
      );
    });
  });

  test('goalsRedrawTimes: as each goal not yet due falls due, and the '
      'midnights ahead', () {
    final snapshot = goalsSnapshot([
      _goal('late', deadline: '2026-10-07'),
      _goal('today-at-five', deadline: '2026-10-08T17:00'),
      _goal('today', deadline: '2026-10-08'),
      // Due at a midnight among those ahead: once.
      _goal('later', deadline: '2026-10-10'),
      _goal('far', deadline: '2026-11-20T09:30'),
      _goal('undated'),
    ], now: _now);
    expect(goalsRedrawTimes(snapshot), [
      DateTime(2026, 10, 8, 17),
      for (var i = 9; i <= 15; i++) DateTime(2026, 10, i),
      DateTime(2026, 11, 20, 9, 30),
    ]);
    expect(goalsRedrawTimes(null), isEmpty);
  });

  group('publish', () {
    test('keeps the snapshot, schedules its redraws, and draws it', () async {
      final host = _FakeHost();
      final widget = GoalsWidget(host: host, enabled: true);
      final goals = [_goal('today', deadline: '2026-10-08')];

      await widget.publish(goals, now: _now);

      expect(host.saved, hasLength(1));
      expect(jsonDecode(host.saved.single!), goalsSnapshot(goals, now: _now));
      expect(host.scheduled.single, hasLength(GoalsWidget.redrawDays));
      expect(host.redraws, 1);
    });

    test('publishes again only when what it shows changes', () async {
      final host = _FakeHost();
      final widget = GoalsWidget(host: host, enabled: true);
      final goals = [_goal('today', deadline: '2026-10-08')];

      await widget.publish(goals, now: _now);
      await widget.publish(goals, now: _now);
      expect(host.saved, hasLength(1));

      await widget.publish([
        ...goals,
        _goal('later', deadline: '2026-10-10'),
      ], now: _now);
      expect(host.saved, hasLength(2));
      expect(host.redraws, 2);

      // Another day: the same goals, published afresh.
      await widget.publish([
        ...goals,
        _goal('later', deadline: '2026-10-10'),
      ], now: _now.add(const Duration(days: 1)));
      expect(host.saved, hasLength(3));
    });

    test('publishes again when what is kept was saved elsewhere: by the '
        'background task, from its own isolate', () async {
      final host = _FakeHost();
      final widget = GoalsWidget(host: host, enabled: true);
      final goals = [_goal('today', deadline: '2026-10-08')];
      await widget.publish(goals, now: _now);
      final own = host.saved.single;

      // The task, having fetched the goals before a change to them was
      // sent, kept a snapshot of its own.
      host.saved.add('{"today":0,"goals":[]}');
      await widget.publish(goals, now: _now);
      expect(host.saved, [own, '{"today":0,"goals":[]}', own]);
      expect(host.redraws, 2);
    });

    test('with no goals known, says so: signed out, say', () async {
      final host = _FakeHost();
      final widget = GoalsWidget(host: host, enabled: true);
      await widget.publish([_goal('today', deadline: '2026-10-08')]);

      await widget.publish(null);

      expect(host.saved, [isNotNull, null]);
      expect(host.scheduled.last, isEmpty);
      expect(host.redraws, 2);
    });

    test('does nothing off Android', () async {
      final host = _FakeHost();
      final widget = GoalsWidget(host: host, enabled: false);

      await widget.publish([_goal('today', deadline: '2026-10-08')]);

      expect(host.saved, isEmpty);
      expect(host.redraws, 0);
    });
  });

  test('pin asks the host to add it to the home screen', () async {
    final host = _FakeHost();
    await GoalsWidget.pin(host: host);
    expect(host.pins, 1);
  });

  group('taps', () {
    const channel = MethodChannel(GoalsWidget.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromAndroid(String method, Object? arguments) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );

    test('reports the tap that launched the app, then later taps', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takeLaunchRequest');
        return {'goal': 'later'};
      });
      final widget = GoalsWidget(
        host: _FakeHost(),
        channel: channel,
        enabled: true,
      );
      final taps = <GoalsTap>[];
      await widget.start();
      // Buffered until something listens, as on a cold start.
      widget.taps.listen(taps.add);

      await fromAndroid('show', {'goal': null});
      await pumpEventQueue();

      expect(taps, [(goalId: 'later'), (goalId: null)]);
      widget.dispose();
    });

    test('reports nothing when launched normally', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final widget = GoalsWidget(
        host: _FakeHost(),
        channel: channel,
        enabled: true,
      );
      final taps = <GoalsTap>[];
      widget.taps.listen(taps.add);
      await widget.start();
      await pumpEventQueue();

      expect(taps, isEmpty);
      widget.dispose();
    });
  });
}
