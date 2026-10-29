import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/models/schedule_hints.dart';
import 'package:time_tracker_client/screens/background_updates_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/background_refresh.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/services/schedule_hints_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
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

    test('is as long after the routine as set', () {
      final next = nextRefresh(DateTime(2026, 10, 7, 7), [
        _morning,
      ], delay: const Duration(minutes: 30));

      expect(next.at, DateTime(2026, 10, 7, 8));
    });

    test("comes sooner while a compaction's proposal hasn't come", () {
      final next = nextRefresh(
        DateTime(2026, 10, 7, 7, 40),
        [_morning, _evening],
        retry: const Duration(minutes: 20),
        awaiting: (hint: _morning, at: DateTime(2026, 10, 7, 7, 30)),
      );

      expect(next.at, DateTime(2026, 10, 7, 8));
      expect(next.hint, _morning);
      expect(next.retry, isTrue);
    });

    test('gives up on the proposal 3 hours after its routine', () {
      final next = nextRefresh(
        DateTime(2026, 10, 7, 10, 20),
        [_morning, _evening],
        awaiting: (hint: _morning, at: DateTime(2026, 10, 7, 7, 30)),
      );

      expect(next.at, DateTime(2026, 10, 7, 16, 20));
      expect(next.retry, isFalse);
    });

    test('does not come sooner, set not to', () {
      final next = nextRefresh(
        DateTime(2026, 10, 7, 7, 40),
        [_morning],
        retry: null,
        awaiting: (hint: _morning, at: DateTime(2026, 10, 7, 7, 30)),
      );

      expect(next.retry, isFalse);
    });
  });

  group('after a routine a proposal is expected from, a background fetch', () {
    final at = DateTime(2026, 10, 7, 7, 45);
    final hints = InMemoryScheduleHintsRepository(
      const ScheduleHints(hints: [_morning, _evening]),
    );
    bool morning(ScheduleHint hint) => hint == _morning;

    test("awaits its proposal when there's none", () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(null),
        expects: morning,
        clock: () => at,
      );

      expect(record.fetched, contains('proposal'));
      expect(record.awaiting?.hint, _morning);
      expect(record.awaiting?.at, DateTime(2026, 10, 7, 7, 30));
    });

    test('has it, through a time after the routine', () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(
          _proposal(through: DateTime(2026, 10, 7, 7, 35)),
        ),
        expects: morning,
        clock: () => at,
      );

      expect(record.awaiting, isNull);
    });

    test('awaits it while the proposal runs through before then', () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(
          _proposal(through: DateTime(2026, 10, 7, 1)),
        ),
        expects: morning,
        clock: () => at,
      );

      expect(record.awaiting?.hint, _morning);
    });

    test('awaits it while only the user extended it past then', () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(
          _proposal(
            through: DateTime(2026, 10, 7, 7, 40),
            claudeThrough: DateTime(2026, 10, 7, 1),
          ),
        ),
        expects: morning,
        clock: () => at,
      );

      expect(record.awaiting?.hint, _morning);
    });

    test('has it, confirmed since', () async {
      final record = await refreshCaches(
        hints: hints,
        notes: InMemoryNotesRepository(
          null,
          CompactionStatus(lastCompaction: DateTime(2026, 10, 7, 7, 40)),
        ),
        proposals: InMemoryProposalRepository(null),
        expects: morning,
        clock: () => at,
      );

      expect(record.awaiting, isNull);
    });

    test('awaits nothing after a routine none is expected from', () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(null),
        expects: (_) => false,
        clock: () => at,
      );

      expect(record.awaiting, isNull);
    });

    test('awaits nothing long after it', () async {
      final record = await refreshCaches(
        hints: hints,
        proposals: InMemoryProposalRepository(null),
        expects: morning,
        clock: () => DateTime(2026, 10, 7, 11),
      );

      expect(record.awaiting, isNull);
    });
  });

  group('the open proposal', () {
    test('is kept, with nothing changed since', () async {
      final cache = InMemoryResponseCache();

      final proposal = await McpProposalRepository(
        _ProposalClient(open: true),
        cache: cache,
      ).current(sinceRevision: 1);
      final kept = await McpProposalRepository(
        _ProposalClient(open: false),
        cache: cache,
      ).cachedCurrent();

      expect(proposal?.changedSince, {'e1'});
      expect(kept?.revision, 2);
      expect(kept?.changedSince, isEmpty);
    });

    test('is forgotten once none is open', () async {
      final cache = InMemoryResponseCache();
      await McpProposalRepository(
        _ProposalClient(open: true),
        cache: cache,
      ).current();

      await McpProposalRepository(
        _ProposalClient(open: false),
        cache: cache,
      ).current();

      expect(
        await McpProposalRepository(
          _ProposalClient(open: false),
          cache: cache,
        ).cachedCurrent(),
        isNull,
      );
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

    test(
      'fetches the goals, keeping them for the app and its widget',
      () async {
        final cache = InMemoryResponseCache();
        final client = _Client([
          {'id': 'g1', 'title': 'Run 5k', 'status': 'active'},
        ]);
        final record = await refreshCaches(
          goals: McpGoalsRepository(client, cache: cache),
          clock: () => _now,
        );
        final kept = await McpGoalsRepository(
          _Client(null),
          cache: cache,
        ).cachedGoals();

        expect(record.fetched, ['goals']);
        expect(client.called, ['get_goals']);
        expect(kept!.single.title, 'Run 5k');
      },
    );

    test('fetches the traits and their scoring defaults', () async {
      final cache = InMemoryResponseCache();
      final client = _ToolsClient({
        'get_traits': const <Object?>[],
        'get_scoring_defaults': const <String, Object?>{},
      });
      final record = await refreshCaches(
        traits: McpTraitsRepository(client, cache: cache),
        clock: () => _now,
      );
      final kept = McpTraitsRepository(_Client(null), cache: cache);

      expect(record.fetched, ['traits']);
      expect(client.called, ['get_traits', 'get_scoring_defaults']);
      expect(await kept.cachedScoringDefaults(), isNotNull);
    });

    test('says when it could not fetch the goals', () async {
      final record = await refreshCaches(
        goals: _FailingGoals(McpException('down')),
        clock: () => _now,
      );

      expect(record.failed, ['goals']);
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

    test("reschedules as the settings change, and awaits the last fetch's "
        'proposal', () async {
      final delays = <Duration>[];
      final settings = AppSettings(persist: false);
      await settings.setExpectsProposal(_morning, true);
      final refresh = BackgroundRefresh(
        repository: InMemoryScheduleHintsRepository(
          const ScheduleHints(hints: [_morning, _evening]),
        ),
        settings: settings,
        supported: true,
        clock: () => DateTime(2026, 10, 7, 7, 40),
        schedule: (delay) async => delays.add(delay),
        lastRecord: () async => RefreshRecord(
          at: DateTime(2026, 10, 7, 7, 40),
          awaiting: (hint: _morning, at: DateTime(2026, 10, 7, 7, 30)),
        ),
      );
      await refresh.load();

      await settings.setRetryInterval(const Duration(minutes: 30));
      await settings.setExpectsProposal(_morning, false);
      await settings.setExpectsProposal(_morning, true);
      await settings.setRetryInterval(null);
      await settings.setRefreshDelay(const Duration(minutes: 20));

      expect(delays, [
        const Duration(minutes: 15),
        const Duration(minutes: 30),
        // Not expected: the fallback's, sooner than the evening's.
        const Duration(hours: 6),
        const Duration(minutes: 30),
        // Not checking again.
        const Duration(hours: 6),
        // The morning's again, 20 minutes after it.
        const Duration(minutes: 10),
      ]);
    });

    testWidgets('where there are none, checks every so often while the app '
        "is open, and after each routine's time", (tester) async {
      var now = DateTime(2026, 10, 7, 18, 50);
      final settings = AppSettings(persist: false);
      final checks = <DateTime>[];
      final refresh = BackgroundRefresh(
        repository: InMemoryScheduleHintsRepository(
          const ScheduleHints(hints: [_evening]),
        ),
        settings: settings,
        supported: false,
        clock: () => now,
        lastRecord: () async => null,
      );
      Future<void> wait(Duration d) async {
        now = now.add(d);
        await tester.pump(d);
      }

      await refresh.load();
      refresh.startLive(() async {
        checks.add(now);
        return true;
      });
      expect(refresh.liveNext, DateTime(2026, 10, 7, 18, 55));

      await wait(const Duration(minutes: 5));
      expect(checks, [DateTime(2026, 10, 7, 18, 55)]);
      expect(refresh.liveLast, DateTime(2026, 10, 7, 18, 55));

      // Only after the routines, then: ten minutes after the evening's.
      await settings.setOpenRefresh(null);
      expect(refresh.liveNext, DateTime(2026, 10, 7, 19, 10));
      await wait(const Duration(minutes: 15));
      expect(checks.last, DateTime(2026, 10, 7, 19, 10));

      refresh.stopLive();
      await wait(const Duration(days: 1));
      expect(checks, hasLength(2));
    });

    testWidgets("checks again a moment later if it couldn't", (tester) async {
      var now = _now;
      var couldnt = true;
      var checks = 0;
      final refresh = BackgroundRefresh(
        supported: false,
        clock: () => now,
        lastRecord: () async => null,
      );
      refresh.startLive(() async {
        checks++;
        return !couldnt;
      });

      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      expect(checks, 1);
      expect(refresh.liveLast, isNull);

      couldnt = false;
      now = now.add(BackgroundRefresh.liveRetry);
      await tester.pump(BackgroundRefresh.liveRetry);
      expect(checks, 2);
      expect(refresh.liveLast, now);
      refresh.stopLive();
    });

    test('checks nothing while open where there are background fetches', () {
      final refresh = BackgroundRefresh(supported: true);
      refresh.startLive(() async => true);

      expect(refresh.live, isFalse);
      expect(refresh.liveNext, isNull);
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
      DateTime? now,
      AppSettings? settings,
    }) => BackgroundRefresh(
      settings: settings,
      repository:
          repository ??
          InMemoryScheduleHintsRepository(
            const ScheduleHints(
              hints: [_morning, _evening],
              timeZone: 'America/New_York',
            ),
          ),
      supported: supported,
      clock: () => now ?? _now,
      schedule: (_) async {},
      lastRecord: () async => last,
    );

    testWidgets("lists the routines' times, each with its update, and the "
        'fallback, plainly', (tester) async {
      await pump(tester, refresh());

      expect(find.text('7:30 AM'), findsOneWidget);
      expect(find.textContaining('Morning compaction'), findsOneWidget);
      expect(find.textContaining('Update ≈ 7:40 AM'), findsOneWidget);
      expect(find.textContaining('Update ≈ 7:10 PM'), findsOneWidget);
      expect(
        find.widgetWithText(FilterChip, 'Expect proposal'),
        findsNWidgets(2),
      );
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

    testWidgets("says it's checking again for a routine's proposal", (
      tester,
    ) async {
      final settings = AppSettings(persist: false);
      await settings.setExpectsProposal(_morning, true);
      await pump(
        tester,
        refresh(
          settings: settings,
          now: DateTime(2026, 10, 7, 7, 40),
          last: RefreshRecord(
            at: DateTime(2026, 10, 7, 7, 40),
            awaiting: (hint: _morning, at: DateTime(2026, 10, 7, 7, 30)),
          ),
        ),
      );

      expect(find.text('Next: about 7:55 AM'), findsOneWidget);
      expect(
        find.textContaining("checking again for Morning compaction's proposal"),
        findsOneWidget,
      );
    });

    testWidgets('sets how long after each routine it fetches', (tester) async {
      final r = refresh();
      await pump(tester, r);

      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();

      expect(r.settings.refreshDelay, const Duration(minutes: 30));
      expect(find.textContaining('Update ≈ 8:00 AM'), findsOneWidget);
    });

    testWidgets('sets which routines a proposal is expected from', (
      tester,
    ) async {
      final r = refresh();
      await pump(tester, r);

      await tester.tap(
        find.widgetWithText(FilterChip, 'Expect proposal').first,
      );
      await tester.pumpAndSettle();

      expect(r.settings.expectsProposal(_morning), isTrue);
      expect(r.settings.expectsProposal(_evening), isFalse);
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, 'Expect proposal').first,
            )
            .selected,
        isTrue,
      );
    });

    testWidgets("says when the server doesn't give the times", (tester) async {
      await pump(tester, refresh(repository: _NoHints()));

      expect(
        find.textContaining("The server doesn't give its routines' times yet"),
        findsOneWidget,
      );
    });

    testWidgets('where it does not run, says the app must stay open, and '
        'has how often it checks while it is', (tester) async {
      final r = refresh(supported: false);
      await pump(tester, r);

      expect(find.textContaining('Keep the app open'), findsOneWidget);
      expect(find.textContaining('On Android, it updates'), findsOneWidget);
      expect(find.textContaining('every 5 minutes'), findsOneWidget);
      expect(find.textContaining('Check ≈ 7:40 AM'), findsOneWidget);
      // The background's own: not here.
      expect(find.text('Every 6 hours'), findsNothing);
      expect(find.text('Until a proposal comes'), findsNothing);
      expect(find.widgetWithText(FilterChip, 'Expect proposal'), findsNothing);

      await tester.tap(find.text('5 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min').last);
      await tester.pumpAndSettle();

      expect(r.settings.openRefresh, const Duration(minutes: 15));
      expect(find.textContaining('every 15 minutes'), findsOneWidget);
    });

    testWidgets('says when it checks next, while the app is open', (
      tester,
    ) async {
      final r = refresh(supported: false);
      r.startLive(() async => true);
      await pump(tester, r);

      expect(find.text('Next: about 9:05 AM'), findsOneWidget);
      expect(find.text('Last: none yet'), findsOneWidget);
      r.stopLive();
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
    String? writeId,
  ]) async {
    called.add(name);
    return result;
  }
}

/// Answers each tool with its own result.
class _ToolsClient extends McpClient {
  _ToolsClient(this.results) : super(endpoint: Uri.parse('http://test'));

  final Map<String, Object?> results;
  final called = <String>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async {
    called.add(name);
    return results[name];
  }
}

Proposal _proposal({required DateTime through, DateTime? claudeThrough}) =>
    Proposal(
      id: 'abc123def456',
      revision: 2,
      state: ProposalState.awaitingReview,
      windowStart: DateTime(2026, 10, 6, 20),
      through: through,
      claudeThrough: claudeThrough,
    );

/// A server with a proposal [open], or none.
class _ProposalClient extends McpClient {
  _ProposalClient({required this.open})
    : super(endpoint: Uri.parse('http://test'));

  final bool open;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async => switch (name) {
    'get_compaction_status' => {
      'proposal': open ? {'id': 'abc123def456', 'revision': 2} : null,
    },
    _ => {
      'id': 'abc123def456',
      'revision': 2,
      'state': 'awaiting_review',
      'window_start': '2026-10-06T20:00:00-04:00',
      'through': '2026-10-07T07:00:00-04:00',
      'events': <Object?>[],
      'changed_since': ['e1'],
    },
  };
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

class _FailingGoals extends InMemoryGoalsRepository {
  _FailingGoals(this.error);

  final Object error;

  @override
  Future<List<Goal>> goals() async => throw error;
}
