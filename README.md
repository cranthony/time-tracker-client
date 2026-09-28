# Time Tracker Client

A Flutter app for the [Time Tracker MCP server](https://github.com/cranthony/time-tracking-google-calendar-mcp).
For now it shows today's **uncompacted notes** and has a **+** button to
record a new one. Later it will show the summaries the server generates.

It is built for Android and also runs on Windows, which is the quickest way
to try changes.

## One-time setup (both platforms)

1. **Install Flutter.** Follow <https://docs.flutter.dev/get-started/install>
   for your OS. When `flutter doctor` runs clean for the platform you want,
   you're done.
2. **Clone this repo** and fetch packages:
   ```sh
   git clone https://github.com/cranthony/time-tracker-client.git
   cd time-tracker-client
   flutter pub get
   ```
3. **Point it at your server.** Copy `config.example.json` to `config.json`
   (it's gitignored) and set `MCP_URL` to your deployed server's URL plus
   `/mcp`, the same URL you gave Claude.ai. You'll find it in the Render
   dashboard.

   If you skip `--dart-define-from-file=config.json` in the commands below,
   the app runs in an **offline demo mode** with in-memory notes. That's
   handy for UI work.

## Run on Windows

Prerequisites (once):

- **Visual Studio 2022** (the full IDE, not VS Code), with the
  **"Desktop development with C++"** workload. The free Community edition
  is fine.
- **Developer Mode** on (Settings → System → For developers). Flutter needs
  it to build plugins.
- `flutter doctor` should show a ✓ for "Visual Studio - develop Windows apps".

Then:

```powershell
flutter run -d windows --dart-define-from-file=config.json
```

The app opens in a phone-sized window. Click **Sign in**: your browser
opens the WorkOS sign-in page. After you sign in, the browser shows
"Signed in", and the app loads your notes. Press `r` in the terminal to
hot-reload after code changes.

To build a standalone `.exe` instead:

```powershell
flutter build windows --dart-define-from-file=config.json
# → build\windows\x64\runner\Release\time_tracker_client.exe
```

## Run on Android

Prerequisites (once):

- **Android Studio**, which installs the Android SDK. Open it once and let
  it finish setup, then run `flutter doctor --android-licenses` and accept.
- On the phone, **enable Developer options** (Settings → About phone → tap
  *Build number* 7 times). Then turn on **USB debugging** under
  Settings → System → Developer options.

**To run it while developing:** plug the phone in over USB and accept the
"Allow USB debugging?" prompt on the phone. Then:

```sh
flutter devices        # your phone should be listed
flutter run --dart-define-from-file=config.json
```

**To install it and keep it**, without a cable afterwards:

```sh
flutter build apk --release --dart-define-from-file=config.json
flutter install                  # with the phone plugged in
```

Alternatively, copy `build/app/outputs/flutter-apk/app-release.apk` to the
phone and open it. You'll have to allow installing from that source.

Tap **Sign in**, sign in in the browser, and Android returns you to the app.

## Signing in (WorkOS AuthKit)

The MCP server is an OAuth *resource server*, and WorkOS AuthKit issues its
tokens. The app signs in the same way Claude.ai does, so **nothing needs
configuring in WorkOS** beyond what the server's README already covers.
Specifically:

1. It reads `/.well-known/oauth-protected-resource/mcp` from the server to
   find AuthKit.
2. On first sign-in, it registers itself through **Dynamic Client
   Registration**. The "Allow MCP clients to authenticate using DCR…"
   setting in WorkOS has to be on, which it already is if Claude.ai works.
3. It runs the authorization-code flow with PKCE in your browser. It asks
   for a token for the server's URL (the `resource` parameter), which is
   the audience the server checks.
4. It stores the tokens in secure storage (Android Keystore, or Windows
   DPAPI) and refreshes them automatically. Use **⋮ → Sign out** to forget
   them.

Redirect URIs it registers:

| Platform | Redirect URI |
| -------- | ------------ |
| Windows  | `http://localhost:47291/callback` |
| Android  | `com.cranthony.timetracker://oauth/callback` |

### Troubleshooting sign-in

- **"Client registration failed"**: DCR is off in WorkOS (Connect →
  Configuration), or WorkOS refused the redirect URI above. If it's the
  Android one, try Windows first; that uses a plain localhost redirect.
- **The browser says it can't reach localhost:47291 (Windows)**: the app
  wasn't waiting for the redirect. Click Sign in again. Also check nothing
  else is using port 47291.
- **Signed in, but loading notes fails with HTTP 401**: the token's
  audience doesn't match. `MCP_URL` must be exactly the server's public URL
  plus `/mcp`, with no trailing slash.

## Development

```sh
flutter analyze
flutter test
```

Tests cover the MCP client, the whole OAuth flow (against a fake AuthKit),
and the notes screen, so none of them need a server.

### Layout

```
lib/
  main.dart                      entry point; picks MCP or demo backend
  models/note.dart               the server's NotedTime
  services/mcp_client.dart       MCP over Streamable HTTP, with bearer auth
  services/notes_repository.dart get_notes / note tools
  auth/oauth.dart                discovery, DCR, PKCE, token exchange/refresh
  auth/auth_session.dart         keeps tokens fresh, runs sign-in
  auth/redirect_receiver.dart    localhost listener (Windows) / deep link (Android)
  auth/token_store.dart          secure token storage
  screens/today_screen.dart      today's notes, sign-in, "+"
  widgets/add_note_dialog.dart   description + time picker
android/app/src/main/kotlin/.../MainActivity.kt   forwards the sign-in deep link
```
