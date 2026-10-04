import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth/auth_session.dart';
import 'auth/oauth.dart';
import 'auth/platform_receiver.dart'
    if (dart.library.js_interop) 'auth/platform_receiver_web.dart';
import 'auth/token_store.dart';
import 'demo/sample_data.dart';
import 'outbox/background_sync.dart';
import 'outbox/goal_outbox.dart';
import 'outbox/note_outbox.dart';
import 'outbox/outbox_store.dart';
import 'platform/add_note_shortcut.dart';
import 'screens/home_screen.dart';
import 'services/goals_repository.dart';
import 'services/events_repository.dart';
import 'services/mcp_client.dart';
import 'services/notes_repository.dart';
import 'services/response_cache.dart';
import 'theme.dart';

/// The Time Tracker MCP server's endpoint, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://your-service.onrender.com/mcp
/// Without it the app runs against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');

/// With no server, start from a realistic sample of notes, events and goals
/// (lib/demo/sample_data.dart) instead of an empty store:
///   flutter run --dart-define=SAMPLE_DATA=true
const _sampleData = bool.fromEnvironment('SAMPLE_DATA');

Future<void> main() async {
  // Before anything below that might use a platform channel.
  WidgetsFlutterBinding.ensureInitialized();
  if (_mcpUrl.isEmpty) {
    final sample = _sampleData ? SampleData(DateTime.now()) : null;
    final repository = sample?.notesRepository() ?? InMemoryNotesRepository();
    final goals = sample?.goalsRepository() ?? InMemoryGoalsRepository();
    runApp(
      TimeTrackerApp(
        repository: repository,
        eventsRepository:
            sample?.eventsRepository() ?? InMemoryEventsRepository(),
        goalsRepository: goals,
        outbox: NoteOutbox(
          store: InMemoryOutboxStore(),
          repository: repository,
        ),
        goalOutbox: GoalOutbox(store: InMemoryOutboxStore(), repository: goals),
      ),
    );
    return;
  }

  await BackgroundSync.initialize(backgroundDispatcher);
  final auth = _authSession(interactive: true);
  final client = _client(auth);
  final cache = PrefsResponseCache();
  final repository = McpNotesRepository(client, cache: cache);
  final goals = McpGoalsRepository(client, cache: cache);
  runApp(
    TimeTrackerApp(
      repository: repository,
      eventsRepository: McpEventsRepository(client, cache: cache),
      goalsRepository: goals,
      outbox: NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: repository,
      ),
      goalOutbox: GoalOutbox(
        store: PrefsOutboxStore.goals(),
        repository: goals,
      ),
      auth: auth,
      cache: cache,
    ),
  );
}

/// Runs WorkManager's background task (Android) that saves pending notes
/// and goal saves.
@pragma('vm:entry-point')
void backgroundDispatcher() => BackgroundSync.run(() {
  final client = _client(_authSession(interactive: false));
  return [
    NoteOutbox(
      store: PrefsOutboxStore.notes(),
      repository: McpNotesRepository(client),
    ),
    GoalOutbox(
      store: PrefsOutboxStore.goals(),
      repository: McpGoalsRepository(client),
    ),
  ];
});

AuthSession _authSession({required bool interactive}) => AuthSession(
  oauth: OAuthClient(
    mcpEndpoint: Uri.parse(_mcpUrl),
    clientName: 'Time Tracker ($platformName)',
    viaResourceServer: oauthViaResourceServer,
  ),
  // On the web, tokens last only as long as the tab; see SecureTokenStore.
  store: const SecureTokenStore.forSession(),
  registrationStore: const SecureTokenStore.persistent(),
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
    required this.goalsRepository,
    required this.outbox,
    required this.goalOutbox,
    this.auth,
    this.cache,
  });

  final NotesRepository repository;
  final EventsRepository eventsRepository;
  final GoalsRepository goalsRepository;
  final NoteOutbox outbox;

  /// Goal saves waiting to be sent, or that failed.
  final GoalOutbox goalOutbox;
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

  @override
  void initState() {
    super.initState();
    BackgroundSync.cancel();
    widget.outbox.start();
    widget.goalOutbox.start();
    _lifecycle = AppLifecycleListener(
      onResume: _onForeground,
      onPause: _onBackground,
    );
    _addNoteShortcut.start();
    _loadVersion();
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
    widget.goalOutbox.start();
  }

  Future<void> _onBackground() async {
    widget.goalOutbox.stop();
    widget.outbox.stop();
    await widget.outbox.refresh();
    await widget.goalOutbox.refresh();
    if (widget.outbox.hasUnsent || widget.goalOutbox.hasUnsent) {
      await BackgroundSync.schedule();
    }
  }

  /// Signs out, and forgets what the server said while signed in.
  Future<void> _signOut() async {
    await widget.auth!.signOut();
    await widget.cache?.clear();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _addNoteShortcut.dispose();
    widget.outbox.dispose();
    widget.goalOutbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: HomeScreen(
        notesRepository: widget.repository,
        eventsRepository: widget.eventsRepository,
        goalsRepository: widget.goalsRepository,
        outbox: widget.outbox,
        goalOutbox: widget.goalOutbox,
        onSignIn: widget.auth?.signIn,
        onSignOut: widget.auth == null ? null : _signOut,
        addNoteRequests: _addNoteShortcut.taps,
        version: _version,
      ),
    );
  }
}
