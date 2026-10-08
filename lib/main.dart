import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth/auth_session.dart';
import 'auth/oauth.dart';
import 'auth/platform_receiver.dart'
    if (dart.library.js_interop) 'auth/platform_receiver_web.dart';
import 'auth/token_store.dart';
import 'demo/sample_data.dart';
import 'models/event.dart';
import 'outbox/background_sync.dart';
import 'outbox/action_outbox.dart';
import 'outbox/event_outbox.dart';
import 'outbox/note_outbox.dart';
import 'outbox/outbox_store.dart';
import 'platform/add_note_shortcut.dart';
import 'screens/home_screen.dart';
import 'services/event_store.dart';
import 'services/actions_repository.dart';
import 'services/background_refresh.dart';
import 'services/events_repository.dart';
import 'services/focus_store.dart';
import 'services/habits_repository.dart';
import 'services/mcp_client.dart';
import 'services/notes_repository.dart';
import 'services/people_repository.dart';
import 'services/plan_memory.dart';
import 'services/proposal_repository.dart';
import 'services/response_cache.dart';
import 'services/schedule_hints_repository.dart';
import 'services/traits_repository.dart';
import 'theme.dart';

/// The Time Tracker MCP server's endpoint, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://your-service.onrender.com/mcp
/// Without it the app runs against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');

/// With no server, start from a realistic sample of notes, events and actions
/// (lib/demo/sample_data.dart) instead of an empty store:
///   flutter run --dart-define=SAMPLE_DATA=true
const _sampleData = bool.fromEnvironment('SAMPLE_DATA');

Future<void> main() async {
  // Before anything below that might use a platform channel.
  WidgetsFlutterBinding.ensureInitialized();
  if (_mcpUrl.isEmpty) {
    final sample = _sampleData ? SampleData(DateTime.now()) : null;
    final repository = sample?.notesRepository() ?? InMemoryNotesRepository();
    final actions = sample?.actionsRepository() ?? InMemoryActionsRepository();
    final events = sample?.eventsRepository() ?? InMemoryEventsRepository();
    final people = sample?.peopleRepository() ?? InMemoryPeopleRepository();
    final proposals = sample?.proposalRepository(
      events: events,
      notes: repository,
      people: people,
      actions: actions,
    );
    runApp(
      TimeTrackerApp(
        repository: repository,
        eventsRepository: events,
        proposalsRepository: proposals,
        actionsRepository: actions,
        outbox: NoteOutbox(
          store: InMemoryOutboxStore(),
          repository: repository,
        ),
        actionOutbox: ActionOutbox(
          store: InMemoryOutboxStore(),
          repository: actions,
        ),
        eventOutbox: EventOutbox(
          store: InMemoryOutboxStore(),
          events: events,
          proposals: proposals,
        ),
        traitsRepository:
            sample?.traitsRepository() ?? InMemoryTraitsRepository(),
        peopleRepository: people,
        habitsRepository:
            sample?.habitsRepository() ?? InMemoryHabitsRepository(),
        focus: sample?.focusStore(),
        backgroundRefresh: BackgroundRefresh(
          repository: sample?.scheduleHintsRepository(),
          // The offline demo has nothing to fetch.
          supported: false,
        ),
      ),
    );
    return;
  }

  await BackgroundSync.initialize(backgroundDispatcher);
  final auth = _authSession(interactive: true);
  final client = _client(auth);
  final cache = PrefsResponseCache();
  final repository = McpNotesRepository(client, cache: cache);
  final actions = McpActionsRepository(client, cache: cache);
  final events = McpEventsRepository(client);
  final proposals = McpProposalRepository(client);
  runApp(
    TimeTrackerApp(
      repository: repository,
      eventsRepository: events,
      proposalsRepository: proposals,
      actionsRepository: actions,
      outbox: NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: repository,
      ),
      actionOutbox: ActionOutbox(
        store: PrefsOutboxStore.actions(),
        repository: actions,
      ),
      eventOutbox: EventOutbox(
        store: PrefsOutboxStore.events(),
        events: events,
        proposals: proposals,
        persistPause: true,
      ),
      auth: auth,
      cache: cache,
      traitsRepository: McpTraitsRepository(client, cache: cache),
      peopleRepository: McpPeopleRepository(client, cache: cache),
      habitsRepository: McpHabitsRepository(client, cache: cache),
      backgroundRefresh: BackgroundRefresh(
        repository: McpScheduleHintsRepository(client, cache: cache),
      ),
    ),
  );
}

/// Runs WorkManager's background tasks (Android): the one that saves
/// pending notes, action saves, and changes to events; and the background
/// fetch ([_refreshInBackground]).
@pragma('vm:entry-point')
void backgroundDispatcher() =>
    BackgroundSync.run(refresh: _refreshInBackground, () {
      final client = _client(_authSession(interactive: false));
      return [
        NoteOutbox(
          store: PrefsOutboxStore.notes(),
          repository: McpNotesRepository(client),
        ),
        ActionOutbox(
          store: PrefsOutboxStore.actions(),
          repository: McpActionsRepository(client),
        ),
        EventOutbox(
          store: PrefsOutboxStore.events(),
          events: McpEventsRepository(client),
          proposals: McpProposalRepository(client),
          persistPause: true,
        ),
      ];
    });

/// Fetches what the app keeps, into what it keeps (see [refreshCaches]),
/// says how it went, and schedules the next: after the routines' next
/// time, or the fallback.
Future<void> _refreshInBackground() async {
  final client = _client(_authSession(interactive: false));
  final cache = PrefsResponseCache();
  final hints = McpScheduleHintsRepository(client, cache: cache);
  final record = await refreshCaches(
    hints: hints,
    notes: McpNotesRepository(client, cache: cache),
    actions: McpActionsRepository(client, cache: cache),
    traits: McpTraitsRepository(client, cache: cache),
    people: McpPeopleRepository(client, cache: cache),
    habits: McpHabitsRepository(client, cache: cache),
    events: EventStore(repository: McpEventsRepository(client), cache: cache),
  );
  await record.save();
  final now = DateTime.now();
  final next = nextRefresh(now, (await hints.cachedHints())?.hints ?? const []);
  await BackgroundSync.scheduleRefresh(next.at.difference(now), fromTask: true);
}

AuthSession _authSession({required bool interactive}) => AuthSession(
  oauth: OAuthClient(
    mcpEndpoint: Uri.parse(_mcpUrl),
    clientName: 'Time Tracker ($platformName)',
    viaResourceServer: oauthViaResourceServer,
  ),
  // The web has no secure storage (see SecureTokenStore), so there the
  // tokens are only ever in memory: reloading the page means signing in
  // again.
  store: kIsWeb ? InMemoryTokenStore() : const SecureTokenStore(),
  registrationStore: const SecureTokenStore(),
  // The background task can't sign in, and mustn't take over the app's
  // sign-in redirect handling if WorkManager runs it in the app's process.
  receiver: interactive ? platformRedirectReceiver() : null,
);

McpClient _client(AuthSession auth) =>
    McpClient(endpoint: Uri.parse(_mcpUrl), auth: auth);

class TimeTrackerApp extends StatefulWidget {
  const TimeTrackerApp({
    super.key,
    required this.repository,
    required this.eventsRepository,
    required this.actionsRepository,
    required this.outbox,
    required this.actionOutbox,
    this.eventOutbox,
    this.auth,
    this.cache,
    this.traitsRepository,
    this.peopleRepository,
    this.habitsRepository,
    this.backgroundRefresh,
    this.proposalsRepository,
    this.focus,
  });

  final NotesRepository repository;

  /// Where the open compaction proposal comes from, to review on the
  /// Events page; without it, there's none.
  final ProposalRepository? proposalsRepository;

  /// Traits, and how each person is rated by them, for every screen
  /// below (see [TraitsScope]); without it, they aren't offered.
  final TraitsRepository? traitsRepository;

  /// People and their circles, for every screen below (see
  /// [PeopleScope]); without it, they aren't offered.
  final PeopleRepository? peopleRepository;

  /// Self's habits, for every screen below (see [HabitsScope]); without
  /// it, they aren't offered.
  final HabitsRepository? habitsRepository;

  /// The background fetches' times, and their schedule (see
  /// [BackgroundRefreshScope]); without it, there are none.
  final BackgroundRefresh? backgroundRefresh;

  /// The habits focused on and people prioritized; by default, those
  /// kept on the device.
  final FocusStore? focus;
  final EventsRepository eventsRepository;
  final ActionsRepository actionsRepository;
  final NoteOutbox outbox;

  /// PlanAction saves waiting to be sent, or that failed.
  final ActionOutbox actionOutbox;

  /// Changes to events, and the open proposal, waiting to be sent, or
  /// that failed; without it, each is saved as it's made.
  final EventOutbox? eventOutbox;
  final AuthSession? auth;

  /// The server's last answers, which the repositories keep; emptied on
  /// signing out.
  final ResponseCache? cache;

  @override
  State<TimeTrackerApp> createState() => _TimeTrackerAppState();
}

class _TimeTrackerAppState extends State<TimeTrackerApp> {
  late final AppLifecycleListener _lifecycle;
  final _addNoteShortcut = AddNoteShortcut();
  String? _version;

  /// What's been loaded of the plan, and the events, for every page to
  /// share: the traits are scored from them.
  late final _planMemory = PlanMemory(
    eventStore: EventStore(
      repository: widget.eventsRepository,
      cache: widget.cache,
    ),
    focus: (widget.focus ?? FocusStore())..load(),
  );

  @override
  void initState() {
    super.initState();
    BackgroundSync.cancel();
    widget.outbox.start();
    widget.actionOutbox.start();
    _startEventOutbox();
    // Their times, and the next fetch scheduled from them. Best effort.
    widget.backgroundRefresh?.load().catchError((Object _) {});
    _lifecycle = AppLifecycleListener(
      onResume: _onForeground,
      onPause: _onBackground,
    );
    _addNoteShortcut.start();
    _loadVersion();
  }

  StreamSubscription<(PendingEventWrite, Object?)>? _savedWrites;

  /// Starts sending the changes to events waiting, once a pause kept from
  /// before is read; each saved goes into the events at once.
  Future<void> _startEventOutbox() async {
    final outbox = widget.eventOutbox;
    if (outbox == null) return;
    _savedWrites ??= outbox.saved.listen((saved) {
      if (saved.$2 case final List<Event> events) {
        _planMemory.eventStore?.putEvents(events);
      }
    });
    await outbox.loadPause();
    outbox.start();
  }

  /// The version from pubspec.yaml, and CI's build number, e.g. "1.1.0 (25)".
  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})';
    });
  }

  Future<void> _onForeground() async {
    await BackgroundSync.cancel();
    // The background task may have refreshed tokens and saved notes.
    widget.auth?.reload();
    widget.outbox.start();
    widget.actionOutbox.start();
    widget.eventOutbox?.start();
  }

  Future<void> _onBackground() async {
    widget.actionOutbox.stop();
    widget.outbox.stop();
    widget.eventOutbox?.stop();
    await widget.outbox.refresh();
    await widget.actionOutbox.refresh();
    await widget.eventOutbox?.refresh();
    if (widget.outbox.hasUnsent ||
        widget.actionOutbox.hasUnsent ||
        (widget.eventOutbox?.hasUnsent ?? false)) {
      await BackgroundSync.schedule();
    }
  }

  /// Signs out, and forgets what the server said while signed in.
  Future<void> _signOut() async {
    await widget.auth!.signOut();
    await _planMemory.eventStore?.clear();
    await widget.cache?.clear();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _addNoteShortcut.dispose();
    widget.outbox.dispose();
    widget.actionOutbox.dispose();
    _savedWrites?.cancel();
    widget.eventOutbox?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      // Above the navigator, so every route and dialog finds it.
      builder: (context, child) {
        Widget scoped = PlanMemoryScope(memory: _planMemory, child: child!);
        if (widget.backgroundRefresh case final refresh?) {
          scoped = BackgroundRefreshScope(refresh: refresh, child: scoped);
        }
        if (widget.habitsRepository case final habits?) {
          scoped = HabitsScope(repository: habits, child: scoped);
        }
        if (widget.peopleRepository case final people?) {
          scoped = PeopleScope(repository: people, child: scoped);
        }
        if (widget.traitsRepository case final traits?) {
          scoped = TraitsScope(repository: traits, child: scoped);
        }
        return scoped;
      },
      home: HomeScreen(
        notesRepository: widget.repository,
        eventsRepository: widget.eventsRepository,
        proposalsRepository: widget.proposalsRepository,
        actionsRepository: widget.actionsRepository,
        outbox: widget.outbox,
        actionOutbox: widget.actionOutbox,
        eventOutbox: widget.eventOutbox,
        onSignIn: widget.auth?.signIn,
        onSignOut: widget.auth == null ? null : _signOut,
        addNoteRequests: _addNoteShortcut.taps,
        onAddNoteFieldFocused: _addNoteShortcut.fieldReady,
        version: _version,
      ),
    );
  }
}
