import 'package:http/http.dart' as http;

import '../auth/sign_in_mode.dart';
import 'client_health.dart';
import 'mcp_client.dart';
import 'sheet_warnings.dart';

/// The app's client for the server at [endpoint], as the app and its
/// background task make it: signed in with [auth] when the server asks for
/// it, and telling [serverSignInOff], and so the banner, what the server
/// says of its own sign-in as it connects -- and [serverSheetWarnings],
/// and so its banner, what it says with each result of changes made
/// behind its back.
McpClient serverClient(
  Uri endpoint, {
  McpAuth? auth,
  ClientHealthRecorder? health,
  http.Client? httpClient,
}) => McpClient(
  endpoint: endpoint,
  auth: auth,
  serverSignInOff: serverSignInOff,
  serverSheetWarnings: serverSheetWarnings,
  health: health,
  httpClient: httpClient,
);
