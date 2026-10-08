import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/schedule_hints.dart';
import 'package:time_tracker_client/screens/background_updates_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/background_refresh.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/services/schedule_hints_repository.dart';
import 'package:time_tracker_client/widgets/app_menu.dart';

const _morning = ScheduleHint(hour: 7, minute: 30, label: 'Morning compaction');
const _evening = ScheduleHint(hour: 19, minute: 0, label: 'Evening compaction');

final _now = DateTime(2026, 10, 7, 9);

void main() {
  group('the next background fetch', () {
    test('is 10 minutes after the next routine', () {
      final next = nextRefresh(DateTime(2026, 10, 7, 7), [_morning, _evening]);

      expect(next.at, DateTime(2026, 10, 7, 7, 40));
      expect(next.hint, _morning);
    });

    test("is tomorrow's, once today's is past", () {
      const late = ScheduleHint(hour: 0, minute: 30, label: 'Night replies');

      final next = nextRefresh(DateTime(2026, 10, 7, 23), [late]);

      expect(next.at, DateTime(2026, 10, 8, 0, 40));
      expect(next.hint, late);
    });

    test('is 6 hours on when no routine runs sooner', () {
      final next = nextRefresh(_now, [_evening]);

      expect(next.at, DateTime(2026, 10, 7, 15));
      expect(next.hint, isNull);
    });

    test('is 6 hours on, with no routines', () {
      expect(nextRefresh(_now, const []).at, DateTime(2026, 10, 7, 15));
    });

    test('just past one, is the next', () {
      final next = nextRefresh(DateTime(2026, 10, 7, 7, 40), [_morning]);

      expect(next.at, DateTime(2026, 10, 7, 13, 40));
      expect(next.hint, isNull);
    });
  });

  test('hints are read earliest first, any that are not a time left out', () {
    final hints = ScheduleHints.fromJson({
      'hints': [
        {'id': 'b', 'time': '19:00', 'label': 'Evening compaction'},
        {'id': 'a', 'time': '7:30', 'label': '  '},
        {'id': 'c', 'time': 'soon'},
        {'id': 'd', 'time': '25:00'},
      ],
      'time_zone': 'America/New_York',
    });

    expect([for (final h in hints.hints) h.time], ['07:30', '19:00']);
    expect(hints.hints.first.label, isNull);
    expect(hints.timeZone, 'America/New_York');
  });

  test('the server gives them, and they are kept for next time', () async {
    final cache = InMemoryResponseCache();
    final client = _Client({
      'hints': [
        {'id': 'a', 'time': '07:30', 'label': 'Morning compaction'},
      ],
      'time_zone': 'Europe/London',
    });

    final hints = await McpScheduleHintsRepository(
      client,
      cache: cache,
    ).hints();
    final kept = await McpScheduleHintsRepository(
      _Client(null),
      cache: cache,
    ).cachedHints();

    expect(client.called, ['get_compaction_schedule_hints']);
    expect(hints.hints.single.label, 'Morning compaction');
    expect(kept!.timeZone, 'Europe/London');
  });

  group('a background fetch', () {
    test('fetches each thing kept, saying what it could not', () async {
      final record = await refreshCaches(
        hints: InMemoryScheduleHintsRepository(),
        actions: _FailingActions(McpException('down')),
        clock: () => _now,
      );

      expect(record.at, _now);
      expect(record.fetched, ['routine times']);
      expect(record.failed, ['actions']);
      expect(record.ok, isFalse);
    });

    test('stops, signed out', () async {
      final record = await refreshCaches(
        actions: _FailingActions(SignInRequiredException()),
        hints: InMemoryScheduleHintsRepository(),
      );

      expect(record.signedOut, isTrue);
      expect(record.fetched, ['routine times']);
    });
  });

  group('BackgroundRefresh', () {
    test('schedules the next fetch from the times it loads', () async {
      final delays = <Duration>[];
      final refresh = BackgroundRefresh(
        repository: InMemoryScheduleHintsRepository(
          const ScheduleHints(hints: [_evening]),
        ),
        supported: true,
        clock: () => DateTime(2026, 10, 7, 17),
        schedule: (delay) async => delays.add(delay),
        lastRecord: () async => null,
      );

      await refresh.load();

      expect(delays, [const Duration(hours: 2, minutes: 10)]);
      expect(refresh.next.hint, _evening);
    });

    test('without the times, falls back to every 6 hours', () async {
      final delays = <Duration>[];
      final refresh = BackgroundRefresh(
        repository: _NoHints(),
        supported: true,
        clock: () => _now,
        schedule: (delay) async => delays.add(delay),
        lastRecord: () async => null,
      );

      await refresh.load();

      expect(refresh.unavailable, isTrue);
      expect(delays, [const Duration(hours: 6)]);
    });

    test('schedules nothing where there are no background fetches', () async {
      final delays = <Duration>[];
      final refresh = BackgroundRefresh(
        repository: InMemoryScheduleHintsRepository(),
        supported: false,
        schedule: (delay) async => delays.add(delay),
        lastRecord: () async => null,
      );

      await refresh.load();

      expect(delays, isEmpty);
    });
  });

  group('the Background updates page', () {
    Future<void> pump(
      WidgetTester tester,
      BackgroundRefresh refresh, {
      bool viaMenu = false,
    }) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              BackgroundRefreshScope(refresh: refresh, child: child!),
          home: viaMenu
              ? Scaffold(
                  appBar: AppBar(actions: const [AppMenu(serverLabel: 'test')]),
                )
              : BackgroundUpdatesScreen(refresh: refresh),
        ),
      );
      await tester.pumpAndSettle();
    }

    BackgroundRefresh refresh({
      ScheduleHintsRepository? repository,
      bool supported = true,
      RefreshRecord? last,
    }) => BackgroundRefresh(
      repository:
          repository ??
          InMemoryScheduleHintsRepository(
            const ScheduleHints(
              hints: [_morning, _evening],
              timeZone: 'America/New_York',
            ),
          ),
      supported: supported,
      clock: () => _now,
      schedule: (_) async {},
      lastRecord: () async => last,
    );

    testWidgets("lists the routines' times, each with its update, and the "
        'fallback, plainly', (tester) async {
      await pump(tester, refresh());

      expect(find.text('7:30 AM'), findsOneWidget);
      expect(find.text('Morning compaction'), findsOneWidget);
      expect(find.text('Update ≈ 7:40 AM'), findsOneWidget);
      expect(find.text('Update ≈ 7:10 PM'), findsOneWidget);
      expect(find.text('Every 6 hours'), findsOneWidget);
      expect(find.text('Next: about 3:00 PM'), findsOneWidget);
      expect(find.textContaining("can't change them"), findsOneWidget);
      expect(find.textContaining('America/New_York'), findsOneWidget);
      // Nothing to edit.
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('says what the last fetch did', (tester) async {
      await pump(
        tester,
        refresh(
          last: RefreshRecord(
            at: DateTime(2026, 10, 7, 7, 43),
            fetched: const ['routine times', 'events'],
            failed: const ['habits'],
          ),
        ),
      );

      expect(find.textContaining('Last:'), findsOneWidget);
      expect(
        find.text("Couldn't fetch habits; fetched routine times, events."),
        findsOneWidget,
      );
    });

    testWidgets("says when the server doesn't give the times", (tester) async {
      await pump(tester, refresh(repository: _NoHints()));

      expect(
        find.textContaining("The server doesn't give its routines' times yet"),
        findsOneWidget,
      );
    });

    testWidgets('says where it does not run', (tester) async {
      await pump(tester, refresh(supported: false));

      expect(
        find.textContaining('Background updates run on Android'),
        findsOneWidget,
      );
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('opens from the app menu', (tester) async {
      await pump(tester, refresh(), viaMenu: true);

      await tester.tap(find.byType(AppMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Background updates'));
      await tester.pumpAndSettle();

      expect(find.byType(BackgroundUpdatesScreen), findsOneWidget);
    });
  });
}

class _Client extends McpClient {
  _Client(this.result) : super(endpoint: Uri.parse('http://test'));

  final Object? result;
  final called = <String>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    called.add(name);
    return result;
  }
}

class _NoHints implements ScheduleHintsRepository {
  @override
  Future<ScheduleHints> hints() async =>
      throw McpException('Unknown tool: get_compaction_schedule_hints');

  @override
  Future<ScheduleHints?> cachedHints() async => null;
}

class _FailingActions extends InMemoryActionsRepository {
  _FailingActions(this.error);

  final Object error;

  @override
  Future<ActionList> actions() async => throw error;
}
