# Time Tracker Client

A Flutter app for the [Time Tracker MCP server](https://github.com/cranthony/time-tracking-google-calendar-mcp).
For now it shows today's **uncompacted notes** and has a **+** button to
record a new one. Later it will show the summaries the server generates.

It is built for Android and also runs on Windows and in Chrome. Chrome
needs no extra tooling, so it's the quickest way to try changes.

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

## Run in Chrome

No prerequisites beyond Flutter and Chrome.

```powershell
flutter run -d chrome --web-port 8765 --dart-define-from-file=config.json
```

Or build it once and serve the static files:

```powershell
flutter build web --dart-define-from-file=config.json
python -m http.server 8765 --directory build/web
```

Then open <http://localhost:8765>. Click **Sign in**: a popup window shows
the WorkOS sign-in page, then closes itself, and the app loads your notes.
If Chrome blocks the popup, allow popups for the site and click again.

Serve it from `localhost` (any port). The server allows cross-origin calls
from `localhost`; for anywhere else, add that origin to the server's
`MCP_CORS_ALLOWED_ORIGINS`.

In the browser, registering the app and fetching tokens go through the
MCP server's `/oauth/register` and `/oauth/token`, which forward them to
AuthKit: AuthKit's own endpoints don't allow browser calls (no CORS
headers). Nothing needs configuring in WorkOS for this.

### Hosted on GitHub Pages

Every push to `main` builds the web app and publishes it to
<https://cranthony.github.io/time-tracker-client/>
([.github/workflows/pages.yml](.github/workflows/pages.yml)). It needs:

- **Pages** set to deploy from GitHub Actions (Settings → Pages → Source).
- The repository variable **`MCP_URL`** (Settings → Secrets and variables
  → Actions → Variables), the same value as in `config.json`.
- The server's **`MCP_CORS_ALLOWED_ORIGINS`** set to
  `https://cranthony.github.io` (on Render: the service's Environment tab).

## Run on Android

### Install the published build (no tools needed)

Every push to `main` builds a signed APK
([.github/workflows/android.yml](.github/workflows/android.yml)) and
publishes it as a GitHub Release. On the phone, open
<https://github.com/cranthony/time-tracker-client/releases/latest/download/time-tracker.apk>
in the browser, then open the downloaded file. The first time, Android
asks you to allow installs from your browser. To update, do the same
again: it installs over the old version and keeps you signed in.

Every build is signed with the same key, which is what lets updates
install over each other. It's kept in the `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD` repository secrets (a PKCS#12 keystore, key
alias `upload`), with a backup outside the repo. Losing it means
uninstalling the app to install a build signed with a new key. APKs you
build yourself are signed with your debug key instead, so Android won't
install one over a published build, or the other way round, without
uninstalling first.

### Build it yourself

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
4. It stores the tokens in secure storage (Android Keystore or Windows
   DPAPI) and refreshes them automatically. Use **⋮ → Sign out** to
   forget them.

   Browsers have no such storage, so on the web the tokens go in the
   tab's `sessionStorage`. They're gone when you close the tab, so you
   sign in again each session. They aren't really protected while the
   tab is open: flutter_secure_storage does encrypt them, but keeps the
   key right beside them, so any script running on the page could read
   them. The client registration (not a secret) stays in `localStorage`,
   so a new session reuses it instead of registering another client.

Redirect URIs it registers:

| Platform | Redirect URI |
| -------- | ------------ |
| Windows  | `http://localhost:47291/callback` |
| Android  | `com.cranthony.timetracker://oauth/callback` |
| Web      | `callback.html` next to the app, e.g. `http://localhost:8765/callback.html` |

### Troubleshooting sign-in

- **"Client registration failed"**: DCR is off in WorkOS (Connect →
  Configuration), or WorkOS refused the redirect URI above. If it's the
  Android one, try Windows first; that uses a plain localhost redirect.
- **The browser says it can't reach localhost:47291 (Windows)**: the app
  wasn't waiting for the redirect. Click Sign in again. Also check nothing
  else is using port 47291.
- **Chrome: "Failed to fetch" / `ClientException` loading notes**: the
  server refused the cross-origin call. Serve the app from `localhost`, or
  add its origin to the server's `MCP_CORS_ALLOWED_ORIGINS`.
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
  auth/web_redirect_receiver.dart  popup + web/callback.html (web)
  auth/platform_receiver*.dart   picks the receiver for the platform
  auth/token_store.dart          secure token storage
  screens/today_screen.dart      today's notes, sign-in, "+"
  widgets/add_note_dialog.dart   description + time picker
android/app/src/main/kotlin/.../MainActivity.kt   forwards the sign-in deep link
```
