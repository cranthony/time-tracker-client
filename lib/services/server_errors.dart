import 'dart:async';

import 'package:http/http.dart' as http;

import 'mcp_client.dart';

/// What kind of failure talking to the server was -- which says what the
/// user can do about it.
enum FailureKind {
  /// Signed out: only signing in again helps.
  signIn,

  /// The server couldn't be reached, or the connection dropped.
  connection,

  /// The server took too long to answer.
  timeout,

  /// The server's having trouble (a 5xx, or too many requests).
  server,

  /// The server answered, and said no: trying again won't change that.
  refused,

  /// Anything else.
  other,
}

/// A failure, in words for the user.
class ServerFailure {
  const ServerFailure(this.kind, this.message);

  final FailureKind kind;

  /// What went wrong, in a sentence: the server's own words, for a
  /// refusal.
  final String message;

  /// Whether it's likely to work if tried again in a moment.
  bool get transient => switch (kind) {
    FailureKind.connection || FailureKind.timeout || FailureKind.server => true,
    _ => false,
  };
}

/// Statuses that mean the server, or something in front of it, is having
/// a moment.
const _transientStatuses = {408, 429, 500, 502, 503, 504};

/// [error] from talking to the server, in words for the user.
ServerFailure describeServerError(Object error) => switch (error) {
  SignInRequiredException() => const ServerFailure(
    FailureKind.signIn,
    'You were signed out. Sign in again, then try again.',
  ),
  McpException(:final statusCode?)
      when _transientStatuses.contains(statusCode) =>
    const ServerFailure(
      FailureKind.server,
      'The server is having trouble right now.',
    ),
  McpException(:final serverMessage?) => ServerFailure(
    FailureKind.refused,
    serverMessage,
  ),
  // A tool's own words, without the wrapping.
  McpException(:final message) => ServerFailure(
    FailureKind.refused,
    message.replaceFirst(RegExp(r'^Tool \w+ failed: '), ''),
  ),
  TimeoutException() => const ServerFailure(
    FailureKind.timeout,
    'The server took too long to answer.',
  ),
  http.ClientException() => const ServerFailure(
    FailureKind.connection,
    "Couldn't reach the server, or the connection dropped.",
  ),
  _ => ServerFailure(
    FailureKind.other,
    error.toString().replaceFirst(RegExp(r'^\w*(Exception|Error): '), ''),
  ),
};

/// Whether [error] is likely to go away if the call is tried again.
bool isTransient(Object error) => describeServerError(error).transient;

/// Whether [error] means the request never reached the server -- so
/// trying again can't do anything twice, whatever the call.
bool neverSent(Object error) =>
    error is http.ClientException &&
    RegExp(
      'connection refused|failed host lookup|network is unreachable|'
      'no address associated',
      caseSensitive: false,
    ).hasMatch(error.message);
