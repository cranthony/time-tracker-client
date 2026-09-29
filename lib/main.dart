import 'package:flutter/material.dart';

import 'auth/auth_session.dart';
import 'auth/oauth.dart';
import 'auth/platform_receiver.dart'
    if (dart.library.js_interop) 'auth/platform_receiver_web.dart';
import 'auth/token_store.dart';
import 'screens/today_screen.dart';
import 'services/mcp_client.dart';
import 'services/notes_repository.dart';

/// The Time Tracker MCP server's endpoint, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://your-service.onrender.com/mcp
/// Without it the app runs against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');

void main() {
  // Before anything below that might use a platform channel.
  WidgetsFlutterBinding.ensureInitialized();
  if (_mcpUrl.isEmpty) {
    runApp(TimeTrackerApp(repository: InMemoryNotesRepository()));
    return;
  }

  final endpoint = Uri.parse(_mcpUrl);
  final auth = AuthSession(
    oauth: OAuthClient(
      mcpEndpoint: endpoint,
      clientName: 'Time Tracker ($platformName)',
      viaResourceServer: oauthViaResourceServer,
    ),
    // On the web, tokens last only as long as the tab; see SecureTokenStore.
    store: const SecureTokenStore.forSession(),
    registrationStore: const SecureTokenStore.persistent(),
    receiver: platformRedirectReceiver(),
  );
  runApp(
    TimeTrackerApp(
      repository: McpNotesRepository(McpClient(endpoint: endpoint, auth: auth)),
      auth: auth,
    ),
  );
}

class TimeTrackerApp extends StatelessWidget {
  const TimeTrackerApp({super.key, required this.repository, this.auth});

  final NotesRepository repository;
  final AuthSession? auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: TodayScreen(
        repository: repository,
        onSignIn: auth?.signIn,
        onSignOut: auth?.signOut,
      ),
    );
  }
}
