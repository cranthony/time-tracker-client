import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'auth/auth_session.dart';
import 'auth/oauth.dart';
import 'auth/platform_receiver.dart'
    if (dart.library.js_interop) 'auth/platform_receiver_web.dart';
import 'auth/token_store.dart';
import 'outbox/background_sync.dart';
import 'outbox/note_outbox.dart';
import 'outbox/outbox_store.dart';
import 'platform/add_note_shortcut.dart';
import 'screens/home_screen.dart';
import 'services/events_repository.dart';
import 'services/mcp_client.dart';
import 'services/notes_repository.dart';

/// The Time Tracker MCP server's endpoint, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://your-service.onrender.com/mcp
/// Without it the app runs against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');

Future<void> main() async {
  // Before anything below that might use a platform channel.
  WidgetsFlutterBinding.ensureInitialized();
  if (_mcpUrl.isEmpty) {
    final repository = InMemoryNotesRepository();
    runApp(
      TimeTrackerApp(
        repository: repository,
        eventsRepository: InMemoryEventsRepository(),
        outbox: NoteOutbox(
          store: InMemoryOutboxStore(),
          repository: repository,
        ),
      ),
    );
    return;
  }

  await BackgroundSync.initialize(backgroundDispatcher);
  final auth = _authSession(interactive: true);
  final client = _client(auth);
  final repository = McpNotesRepository(client);
  runApp(
    TimeTrackerApp(
      repository: repository,
      eventsRepository: McpEventsRepository(client),
      outbox: NoteOutbox(store: PrefsOutboxStore(), repository: repository),
      auth: auth,
    ),
  );
}

/// Runs WorkManager's background task (Android) that saves pending notes.
@pragma('vm:entry-point')
void backgroundDispatcher() => BackgroundSync.run(() {
  final repository = McpNotesRepository(
    _client(_authSession(interactive: false)),
  );
  return NoteOutbox(store: PrefsOutboxStore(), repository: repository);
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
    required this.outbox,
    this.auth,
  });

  final NotesRepository repository;
  final EventsRepository eventsRepository;
  final NoteOutbox outbox;
  final AuthSession? auth;

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
  }

  Future<void> _onBackground() async {
    widget.outbox.stop();
    await widget.outbox.refresh();
    if (widget.outbox.pending.isNotEmpty) await BackgroundSync.schedule();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _addNoteShortcut.dispose();
    widget.outbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(
        notesRepository: widget.repository,
        eventsRepository: widget.eventsRepository,
        outbox: widget.outbox,
        onSignIn: widget.auth?.signIn,
        onSignOut: widget.auth?.signOut,
        addNoteRequests: _addNoteShortcut.taps,
        version: _version,
      ),
    );
  }
}
