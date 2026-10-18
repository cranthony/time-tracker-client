import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth/auth_session.dart';
import 'auth/oauth.dart';
import 'auth/platform_receiver.dart'
    if (dart.library.js_interop) 'auth/platform_receiver_web.dart';
import 'auth/token_store.dart';
import 'demo/google_calendar_sample.dart';
import 'demo/sample_data.dart';
import 'models/event.dart';
import 'outbox/background_sync.dart';
import 'outbox/action_writes.dart';
import 'outbox/event_outbox.dart';
import 'outbox/note_writes.dart';
import 'outbox/outbox.dart';
import 'outbox/outbox_store.dart';
import 'outbox/write_queue.dart';
import 'platform/add_note_shortcut.dart';
import 'platform/calendar_widget.dart';
import 'screens/home_screen.dart';
import 'screens/sheet_warnings_screen.dart';
import 'services/app_settings.dart';
import 'services/event_store.dart';
import 'services/actions_repository.dart';
import 'services/background_refresh.dart';
import 'services/client_health.dart';
import 'services/diagnostics_repository.dart';
import 'services/events_repository.dart';
import 'services/focus_store.dart';
import 'services/goals_repository.dart';
import 'services/habits_repository.dart';
import 'services/mcp_client.dart';
import 'services/note_drafts.dart';
import 'services/notes_repository.dart';
import 'services/people_repository.dart';
import 'services/plan_memory.dart';
import 'services/proposal_repository.dart';
import 'services/response_cache.dart';
import 'services/schedule_hints_repository.dart';
import 'services/server_url.dart';
import 'services/server_client.dart';
import 'services/traits_repository.dart';
import 'platform/google_calendar_source.dart';
import 'services/google_calendars.dart';
import 'services/open_meteo.dart';
import 'services/weather.dart';
import 'platform/device_location.dart';
import 'demo/weather_sample.dart';
import 'services/work_timing.dart';
import 'theme.dart';
import 'widgets/hotkeys.dart';
import 'widgets/sheet_warnings_banner.dart';
import 'widgets/sign_in_off_banner.dart';

/// The Time Tracker MCP server's endpoint, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://your-service.onrender.com/mcp
/// or, for the web app served from the server's own origin, a relative
/// one, such as /mcp (see [serverEndpoint]). Without it the app runs
/// against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');

/// [_mcpUrl] as a full URL: a relative one resolved against the page.
final Uri _endpoint = serverEndpoint(_mcpUrl, web: kIsWeb);

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
    // Kept in memory, with the sample's own to start with.
    final health = ClientHealthRecorder(
      origin: CallOrigin.app,
      store: InMemoryClientHealthStore(
        sample == null
            ? const ClientHealth()
            : SampleData.clientHealth(DateTime.now()),
      ),
    );
    _recordUncaughtErrors(health);
    _recordWork(health);
    // Kept in memory, and made to the notes and actions themselves.
    final writeQueue = WriteQueue(
      store: InMemoryOutboxStore(),
      call: localWrites(actions: actions, notes: repository),
    );
    final eventOutbox = EventOutbox(
      store: InMemoryOutboxStore(),
      events: events,
      proposals: proposals,
      notices: ProposalNotices(persist: false),
    );
    _watchQueues(health, writeQueue, eventOutbox);
    runApp(
      TimeTrackerApp(
        repository: repository,
        eventsRepository: events,
        proposalsRepository: proposals,
        actionsRepository: actions,
        writeQueue: writeQueue,
        eventOutbox: eventOutbox,
        clientHealth: health,
        traitsRepository:
            sample?.traitsRepository() ?? InMemoryTraitsRepository(),
        peopleRepository: people,
        habitsRepository:
            sample?.habitsRepository() ?? InMemoryHabitsRepository(),
        goalsRepository: sample?.goalsRepository() ?? InMemoryGoalsRepository(),
        focus: sample?.focusStore(),
        diagnosticsRepository: sample?.diagnosticsRepository(),
        calendarWidget: CalendarWidget(),
        googleCalendars: sample == null
            ? null
            : GoogleCalendars(
                source: SampleGoogleCalendarSource(DateTime.now()),
                persist: false,
                enabled: true,
                selected: const {'personal', 'family', 'birthdays', 'work'},
              ),
        weather: sample == null
            ? null
            : (Weather(
                forecasts: SampleForecastSource(),
                location: FixedLocationSource(),
                persist: false,
                enabled: true,
                place: const Coordinates(47.61, -122.33),
              )..load()),
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
  final health = ClientHealthRecorder(origin: CallOrigin.app);
  _recordUncaughtErrors(health);
  _recordWork(health);
  final auth = _authSession(interactive: true);
  final client = _client(auth, health);
  final cache = PrefsResponseCache();
  final writeQueue = WriteQueue(
    store: PrefsOutboxStore.writes(),
    call: WriteQueue.callOn(client),
  );
  final repository = McpNotesRepository(
    client,
    cache: cache,
    writes: writeQueue,
  );
  final events = McpEventsRepository(client);
  final proposals = McpProposalRepository(client, cache: cache);
  final settings = AppSettings();
  final actions = McpActionsRepository(
    client,
    cache: cache,
    writes: writeQueue,
  );
  final eventOutbox = EventOutbox(
    store: PrefsOutboxStore.events(),
    events: events,
    proposals: proposals,
    notices: ProposalNotices(),
    persistPause: true,
    making: () => writeQueue.making,
  );
  _watchQueues(health, writeQueue, eventOutbox);
  // From Open-Meteo, for a place the user gives, or where the device is
  // -- asked only once they pick that, in Settings.
  final weather = Weather(
    forecasts: OpenMeteoForecastSource(),
    location: DeviceLocationSource(),
  )..load();
  runApp(
    TimeTrackerApp(
      settings: settings,
      repository: repository,
      eventsRepository: events,
      proposalsRepository: proposals,
      actionsRepository: actions,
      eventOutbox: eventOutbox,
      writeQueue: writeQueue,
      clientHealth: health,
      auth: auth,
      cache: cache,
      traitsRepository: McpTraitsRepository(
        client,
        cache: cache,
        writes: writeQueue,
      ),
      peopleRepository: McpPeopleRepository(
        client,
        cache: cache,
        writes: writeQueue,
      ),
      habitsRepository: McpHabitsRepository(
        client,
        cache: cache,
        writes: writeQueue,
      ),
      goalsRepository: McpGoalsRepository(
        client,
        cache: cache,
        writes: writeQueue,
      ),
      diagnosticsRepository: McpDiagnosticsRepository(client, cache: cache),
      calendarWidget: CalendarWidget(),
      // Read on the phone, from Android's calendar provider: nowhere else
      // has the Google calendars synced to it.
      googleCalendars:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? (GoogleCalendars(source: AndroidGoogleCalendarSource())..load())
          : null,
      weather: weather,
      backgroundRefresh: BackgroundRefresh(
        repository: McpScheduleHintsRepository(client, cache: cache),
        settings: settings,
        weather: weather,
      ),
    ),
  );
}

/// Runs WorkManager's background tasks (Android): the one that saves
/// pending notes, action saves, and changes to events; the background
/// fetch ([_refreshInBackground]); and the weather's, for where it's for
/// -- where the device was last found while the app was open, never
/// asking where it is now.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  _recordUncaughtErrors(_backgroundHealth);
  BackgroundSync.run(
    refresh: _refreshInBackground,
    weather: _refreshWeatherInBackground,
    // What it recorded, kept for the Diagnostics page.
    done: _backgroundHealth.flush,
    () {
      final client = _client(
        _authSession(interactive: false),
        _backgroundHealth,
      );
      final writes = WriteQueue(
        store: PrefsOutboxStore.writes(),
        call: WriteQueue.callOn(client),
        sender: Outbox.backgroundSender,
      );
      final events = EventOutbox(
        store: PrefsOutboxStore.events(),
        sender: Outbox.backgroundSender,
        making: () => writes.making,
        events: McpEventsRepository(client),
        proposals: McpProposalRepository(client),
        // What came of a change to the proposal, for the app to say.
        notices: ProposalNotices(),
        persistPause: true,
      );
      _watchQueues(_backgroundHealth, writes, events);
      // The writes first: an event may name what one makes.
      return [writes, events];
    },
  );
}

/// Fetches the weather in the background ([refreshWeatherInBackground]),
/// and, if it's on, has the home screen calendar's headers show it.
Future<void> _refreshWeatherInBackground() async {
  final record = await refreshWeatherInBackground(
    forecasts: OpenMeteoForecastSource(),
  );
  if (record == null) return;
  final settings = AppSettings();
  await settings.load();
  await CalendarWidget().publishWeather(
    (await KeptWeather.forecast())?.forecast,
    unit: settings.temperatureUnit,
  );
}

/// The background task's health: its tool calls, errors and queues, kept
/// as each task ends.
final _backgroundHealth = ClientHealthRecorder(origin: CallOrigin.background);

/// Records [health]'s queues' lengths as they change: those waiting to be
/// sent, refused or not -- the write queue's notes as the notes', and the
/// rest as the actions', which were the first it held.
void _watchQueues(
  ClientHealthRecorder health,
  WriteQueue writes,
  EventOutbox events,
) => health.watchQueues(
  notes: writes,
  notesCount: () =>
      writes.items.where((w) => w.kind == WriteKind.note.name).length,
  actions: writes,
  actionsCount: () =>
      writes.items.where((w) => w.kind != WriteKind.note.name).length,
  events: events,
  eventsCount: () => events.items.length,
);

/// Records how long the app's own work takes, its slow frames and its
/// visits to Plan (see work_timing.dart).
void _recordWork(ClientHealthRecorder health) {
  workRecorder = health;
  watchFrames();
}

/// Records each error nothing else caught, as well as reporting it as
/// before.
void _recordUncaughtErrors(ClientHealthRecorder health) {
  final flutter = FlutterError.onError;
  FlutterError.onError = (details) {
    health.recordError(details.exception, stack: details.stack);
    flutter?.call(details);
  };
  final platform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    health.recordError(error, stack: stack);
    return platform?.call(error, stack) ?? false;
  };
}

/// Fetches what the app keeps, into what it keeps (see [refreshCaches]),
/// says how it went, and schedules the next: after the routines' next
/// time, sooner while a proposal's expected and hasn't come, or the
/// fallback -- as the settings say.
Future<void> _refreshInBackground() async {
  final client = _client(_authSession(interactive: false), _backgroundHealth);
  final cache = PrefsResponseCache();
  final hints = McpScheduleHintsRepository(client, cache: cache);
  final settings = AppSettings();
  await settings.load();
  final actions = McpActionsRepository(client, cache: cache);
  final events = EventStore(
    repository: McpEventsRepository(client),
    cache: cache,
  );
  final record = await refreshCaches(
    hints: hints,
    notes: McpNotesRepository(client, cache: cache),
    proposals: McpProposalRepository(client, cache: cache),
    expects: settings.expectsProposal,
    actions: actions,
    traits: McpTraitsRepository(client, cache: cache),
    people: McpPeopleRepository(client, cache: cache),
    habits: McpHabitsRepository(client, cache: cache),
    events: events,
  );
  await record.save();
  // The home screen calendar, from what was just fetched -- or, if that
  // failed, what was kept.
  await CalendarWidget().publish(
    events,
    actions: (await actions.cachedActions())?.actions ?? const [],
  );
  final now = DateTime.now();
  final next = nextRefresh(
    now,
    (await hints.cachedHints())?.hints ?? const [],
    delay: settings.refreshDelay,
    retry: settings.retryInterval,
    awaiting: record.awaiting,
  );
  await BackgroundSync.scheduleRefresh(next.at.difference(now), fromTask: true);
}

AuthSession _authSession({required bool interactive}) => AuthSession(
  oauth: OAuthClient(
    mcpEndpoint: _endpoint,
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

/// The server's client, signing in with [auth] when the server asks.
McpClient _client(AuthSession? auth, ClientHealthRecorder health) =>
    serverClient(_endpoint, auth: auth, health: health);

class TimeTrackerApp extends StatefulWidget {
  const TimeTrackerApp({
    super.key,
    required this.repository,
    required this.eventsRepository,
    required this.actionsRepository,
    this.eventOutbox,
    this.writeQueue,
    this.auth,
    this.cache,
    this.traitsRepository,
    this.peopleRepository,
    this.habitsRepository,
    this.goalsRepository,
    this.backgroundRefresh,
    this.diagnosticsRepository,
    this.clientHealth,
    this.proposalsRepository,
    this.focus,
    this.settings,
    this.calendarWidget,
    this.googleCalendars,
    this.weather,
  });

  /// The forecast where the device is, if the user turns it on; null for
  /// none.
  final Weather? weather;

  /// The app's settings; by default, those kept on the device.
  final AppSettings? settings;

  /// The phone's Google calendars, to show their events; null where
  /// there are none to read.
  final GoogleCalendars? googleCalendars;

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

  /// The user's goals, for every screen below (see [GoalsScope]); without
  /// it, they aren't offered.
  final GoalsRepository? goalsRepository;

  /// The background fetches' times, and their schedule (see
  /// [BackgroundRefreshScope]); without it, there are none.
  final BackgroundRefresh? backgroundRefresh;

  /// Where the Diagnostics page's metrics come from (see
  /// [DiagnosticsScope]); without it, the menu doesn't offer it.
  final DiagnosticsRepository? diagnosticsRepository;

  /// The app's own health, recorded as it goes, for the Diagnostics page's
  /// App pane; kept as the app goes to the background.
  final ClientHealthRecorder? clientHealth;

  /// The habits focused on and people prioritized; by default, those
  /// kept on the device.
  final FocusStore? focus;

  /// The Android home screen calendar, kept up to date with the events,
  /// and its taps shown on Events; without it, it isn't.
  final CalendarWidget? calendarWidget;
  final EventsRepository eventsRepository;
  final ActionsRepository actionsRepository;

  /// Changes to events, and the open proposal, waiting to be sent, or
  /// that failed; without it, each is saved as it's made.
  final EventOutbox? eventOutbox;

  /// Every write of the kinds it has ([WriteKind.all]), waiting to be
  /// saved; by default, one in memory making the actions' writes to
  /// [actionsRepository] itself.
  final WriteQueue? writeQueue;
  final AuthSession? auth;

  /// The server's last answers, which the repositories keep; emptied on
  /// signing out.
  final ResponseCache? cache;

  @override
  State<TimeTrackerApp> createState() => _TimeTrackerAppState();
}

class _TimeTrackerAppState extends State<TimeTrackerApp> {
  /// Notes being written, kept on the device as they're typed.
  final _noteDrafts = NoteDrafts.device();

  late final AppLifecycleListener _lifecycle;
  final _addNoteShortcut = AddNoteShortcut();

  /// The keys the app answers, wherever it is.
  final _hotkeys = Hotkeys();

  /// The app's navigator: for the banners above it to open pages.
  final _navigator = GlobalKey<NavigatorState>();
  String? _version;

  /// What's been loaded of the plan, and the events, for every page to
  /// share: the traits are scored from them.
  /// The app's settings, read from the device as it starts.
  late final _settings = (widget.settings ?? AppSettings())..load();

  late final _writeQueue =
      widget.writeQueue ??
      WriteQueue(
        store: InMemoryOutboxStore(),
        call: localWrites(
          actions: widget.actionsRepository,
          notes: widget.repository,
        ),
      );

  /// The notes page's writes, through [_writeQueue].
  late final _noteWrites = NoteWrites(_writeQueue);

  /// The Plan page's writes, through [_writeQueue].
  late final _actionWrites = ActionWrites(_writeQueue);

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
    // Every page shows the actions with the saves waiting, or just made.
    _planMemory.useActionWrites(_actionWrites);
    BackgroundSync.cancel();
    _writeQueue.start();
    _startEventOutbox();
    // Their times, and the next fetch scheduled from them. Best effort.
    widget.backgroundRefresh?.load().catchError((Object _) {});
    _lifecycle = AppLifecycleListener(
      onResume: _onForeground,
      onPause: _onBackground,
    );
    _addNoteShortcut.start();
    _startCalendarWidget();
    _loadVersion();
  }

  Timer? _calendarTimer;

  /// Keeps the home screen calendar up to date with the events, and
  /// listens for its taps.
  void _startCalendarWidget() {
    final calendar = widget.calendarWidget;
    if (calendar == null || !calendar.enabled) return;
    _planMemory.addListener(_calendarChanged);
    _calendarChanged();
    if (widget.weather case final weather?) {
      _calendarWeather = CalendarWeatherLink(
        widget: calendar,
        weather: weather,
        settings: _settings,
      );
    }
    calendar.start();
  }

  /// Publishes the events to the home screen calendar a moment after
  /// they change: a run of changes, once.
  /// Keeps the home screen calendar's headers' weather up to date.
  CalendarWeatherLink? _calendarWeather;

  void _calendarChanged() {
    _calendarTimer?.cancel();
    _calendarTimer = Timer(const Duration(seconds: 1), () {
      final store = _planMemory.eventStore;
      if (store == null) return;
      unawaited(
        widget.calendarWidget?.publish(
          store,
          actions: _planMemory.shownActions?.actions ?? const [],
        ),
      );
    });
  }

  StreamSubscription<(PendingEventWrite, Object?)>? _savedWrites;

  /// Starts sending the changes to events waiting, once a pause kept from
  /// before is read; each saved goes into the events at once.
  Future<void> _startEventOutbox() async {
    final outbox = widget.eventOutbox;
    if (outbox == null) return;
    _savedWrites ??= outbox.saved.listen((saved) {
      final (write, result) = saved;
      if (result case final List<Event> events) {
        final store = _planMemory.eventStore;
        store?.putEvents(events);
        // The series' later events, which the server worked out.
        if (write.repeatFrom(events) case final from? when write.setsRepeat) {
          unawaited(store?.refreshFrom(from).catchError((_) {}));
        }
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
    // What the background task's changes to the proposal came to.
    unawaited(widget.eventOutbox?.notices?.load());
    widget.eventOutbox?.start();
    _writeQueue.start();
  }

  Future<void> _onBackground() async {
    widget.eventOutbox?.stop();
    _writeQueue.stop();
    await widget.eventOutbox?.refresh();
    await _writeQueue.refresh();
    await widget.clientHealth?.flush();
    if ((widget.eventOutbox?.hasUnsent ?? false) || _writeQueue.hasUnsent) {
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
    _hotkeys.dispose();
    _calendarTimer?.cancel();
    _planMemory.removeListener(_calendarChanged);
    _calendarWeather?.dispose();
    widget.calendarWidget?.dispose();
    _savedWrites?.cancel();
    widget.eventOutbox?.dispose();
    _writeQueue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      navigatorKey: _navigator,
      navigatorObservers: [_hotkeys],
      // Above the navigator, so every route and dialog finds it.
      builder: (context, child) {
        Widget scoped = PlanMemoryScope(memory: _planMemory, child: child!);
        scoped = AppSettingsScope(settings: _settings, child: scoped);
        if (widget.googleCalendars case final calendars?) {
          scoped = GoogleCalendarsScope(calendars: calendars, child: scoped);
        }
        if (widget.weather case final weather?) {
          scoped = WeatherScope(weather: weather, child: scoped);
        }
        if (widget.diagnosticsRepository case final diagnostics?) {
          scoped = DiagnosticsScope(
            repository: diagnostics,
            client: widget.clientHealth,
            child: scoped,
          );
        }
        if (widget.backgroundRefresh case final refresh?) {
          scoped = BackgroundRefreshScope(refresh: refresh, child: scoped);
        }
        if (widget.habitsRepository case final habits?) {
          scoped = HabitsScope(repository: habits, child: scoped);
        }
        if (widget.goalsRepository case final goals?) {
          scoped = GoalsScope(repository: goals, child: scoped);
        }
        if (widget.peopleRepository case final people?) {
          scoped = PeopleScope(repository: people, child: scoped);
        }
        scoped = ActionsScope(
          repository: widget.actionsRepository,
          outbox: _actionWrites,
          child: scoped,
        );
        if (widget.traitsRepository case final traits?) {
          scoped = TraitsScope(repository: traits, child: scoped);
        }
        // Over every screen and dialog, while the server says it found
        // changes made behind its back lately.
        final diagnostics = widget.diagnosticsRepository;
        scoped = SheetWarningsBanner(
          onOpen: diagnostics == null
              ? null
              : () => _navigator.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SheetWarningsScreen(repository: diagnostics),
                  ),
                ),
          child: scoped,
        );
        // Over every screen and dialog, while the server skips sign-in.
        scoped = SignInOffBanner(child: scoped);
        return HotkeyScope(hotkeys: _hotkeys, child: scoped);
      },
      home: HomeScreen(
        notesRepository: widget.repository,
        eventsRepository: widget.eventsRepository,
        proposalsRepository: widget.proposalsRepository,
        actionsRepository: widget.actionsRepository,
        outbox: _noteWrites,
        actionWrites: _actionWrites,
        eventOutbox: widget.eventOutbox,
        writeQueue: _writeQueue,
        onSignIn: widget.auth?.signIn,
        onSignOut: widget.auth == null ? null : _signOut,
        addNoteRequests: _addNoteShortcut.taps,
        noteDrafts: _noteDrafts,
        calendarTaps: widget.calendarWidget?.taps,
        onAddNoteFieldFocused: _addNoteShortcut.fieldReady,
        version: _version,
      ),
    );
  }
}
