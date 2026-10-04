import 'dart:async';

import 'package:http/http.dart' as http;

import '../services/mcp_client.dart';

/// Why [e] kept something from being saved, in a few words.
String describeSaveError(Object e) => switch (e) {
  McpException(:final message) => message,
  SignInRequiredException() => 'Sign in again, then try again.',
  TimeoutException() => 'The server took too long to answer',
  http.ClientException() => 'No connection to the server',
  _ => e.toString().replaceFirst(RegExp(r'^\w*Exception: '), ''),
};
