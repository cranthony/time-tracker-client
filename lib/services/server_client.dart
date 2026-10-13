import 'package:http/http.dart' as http;

import '../auth/sign_in_mode.dart';
import 'client_health.dart';
import 'mcp_client.dart';

/// The app's client for the server at [endpoint], as the app and its
/// background task make it: signing in with [auth] -- or, in a build that
/// skips sign-in ([signInOff], or [withoutSignIn] if given), with no
/// token at all -- and telling [serverSignInOff], and so the banner, what
/// the server says of its own sign-in as it connects.
McpClient serverClient(
  Uri endpoint, {
  McpAuth? auth,
  ClientHealthRecorder? health,
  http.Client? httpClient,
  bool? withoutSignIn,
}) {
  final off = withoutSignIn ?? signInOff;
  return McpClient(
    endpoint: endpoint,
    auth: off ? null : auth,
    signInOff: off,
    serverSignInOff: serverSignInOff,
    health: health,
    httpClient: httpClient,
  );
}
