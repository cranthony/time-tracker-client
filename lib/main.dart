import 'package:flutter/material.dart';

import 'screens/today_screen.dart';
import 'services/mcp_client.dart';
import 'services/notes_repository.dart';

/// Server settings, passed at build time, e.g.
///   flutter run --dart-define=MCP_URL=https://example.com/mcp --dart-define=MCP_TOKEN=...
/// Without MCP_URL the app runs against an in-memory demo store.
const _mcpUrl = String.fromEnvironment('MCP_URL');
const _mcpToken = String.fromEnvironment('MCP_TOKEN');

void main() {
  final NotesRepository repository = _mcpUrl.isEmpty
      ? InMemoryNotesRepository()
      : McpNotesRepository(
          McpClient(endpoint: Uri.parse(_mcpUrl), bearerToken: _mcpToken),
        );
  runApp(TimeTrackerApp(repository: repository));
}

class TimeTrackerApp extends StatelessWidget {
  const TimeTrackerApp({super.key, required this.repository});

  final NotesRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Tracker',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: TodayScreen(repository: repository),
    );
  }
}
