# Time Tracker Client

An Android app (Flutter) for the Time Tracker MCP server. For now it shows
today's **uncompacted notes**, with a **+** button to record a new one.
Later it will show the summaries the server generates.

## Running

```sh
flutter run \
  --dart-define=MCP_URL=https://<your-server>/mcp \
  --dart-define=MCP_TOKEN=<bearer token, if the server needs one>
```

Without `MCP_URL`, the app uses an in-memory demo store, which is handy for
working on the UI.

To install on a phone: `flutter build apk --release --dart-define=...`, then
`flutter install` (or copy `build/app/outputs/flutter-apk/app-release.apk`
to the phone).

## How it talks to the server

`lib/services/mcp_client.dart` is a small MCP client for the Streamable HTTP
transport (initialize handshake, `Mcp-Session-Id`, JSON or SSE responses).
`lib/services/notes_repository.dart` uses it to call two tools:

- `get_notes` (with `include_compacted: false`); the screen then keeps only
  notes from today in the phone's local time zone.
- `note`, with `noted_time: {timestamp, description}`. Timestamps are sent
  in UTC.

## Layout

```
lib/
  main.dart                    app entry, picks MCP or in-memory backend
  models/note.dart             NotedTime model
  services/mcp_client.dart     MCP over Streamable HTTP
  services/notes_repository.dart
  screens/today_screen.dart    today's notes + "+" button
  widgets/add_note_dialog.dart description + time picker
test/                          widget and MCP client tests
```

`flutter analyze` and `flutter test` should both be clean.
