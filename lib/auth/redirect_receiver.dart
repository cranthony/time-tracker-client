import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the authorization URL in a browser and waits for the authorization
/// server to redirect back to [redirectUri].
abstract class RedirectReceiver {
  Uri get redirectUri;

  /// Called synchronously at the very start of sign-in, while the browser
  /// still counts the user's click as the reason for what happens next.
  /// On the web, that's the only time a popup window can be opened.
  void prepare() {}

  /// Undoes [prepare] when sign-in fails before [authorize] gets to run.
  void cancel() {}

  /// Returns the full redirect URI, including the `code` and `state`.
  Future<Uri> authorize(Uri authorizationUrl);
}

Future<void> _openBrowser(Uri url) async {
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open a browser for $url');
  }
}

/// For desktop (Windows): a one-shot HTTP server on localhost catches the
/// redirect, per RFC 8252's loopback redirect. The port is fixed because
/// the redirect URI is registered with the authorization server exactly.
class LoopbackRedirectReceiver extends RedirectReceiver {
  LoopbackRedirectReceiver({
    this.port = 47291,
    this.timeout = const Duration(minutes: 5),
    Future<void> Function(Uri)? openBrowser,
  }) : _openBrowserFn = openBrowser ?? _openBrowser;

  final int port;
  final Duration timeout;
  final Future<void> Function(Uri) _openBrowserFn;

  @override
  Uri get redirectUri => Uri.parse('http://localhost:$port/callback');

  @override
  Future<Uri> authorize(Uri authorizationUrl) async {
    // "localhost" can resolve to either loopback address in the browser.
    final servers = <HttpServer>[];
    for (final address in [
      InternetAddress.loopbackIPv4,
      InternetAddress.loopbackIPv6,
    ]) {
      try {
        servers.add(await HttpServer.bind(address, port));
      } on SocketException {
        // e.g. no IPv6 on this machine; the other one will do.
      }
    }
    if (servers.isEmpty) {
      throw StateError(
        'Could not listen on localhost:$port for the sign-in redirect',
      );
    }

    final redirect = Completer<Uri>();
    for (final server in servers) {
      server.listen((request) async {
        if (request.uri.path != redirectUri.path) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><title>Time Tracker</title>'
          '<body style="font-family:sans-serif;text-align:center;padding-top:4em">'
          '<h2>Signed in</h2><p>You can close this tab and return to Time Tracker.</p>',
        );
        await request.response.close();
        if (!redirect.isCompleted) {
          redirect.complete(redirectUri.replace(query: request.uri.query));
        }
      });
    }

    try {
      await _openBrowserFn(authorizationUrl);
      return await redirect.future.timeout(timeout);
    } finally {
      for (final server in servers) {
        await server.close(force: true);
      }
    }
  }
}

/// For Android: the browser redirects to a custom-scheme URI, which Android
/// routes to MainActivity (see the intent filter in AndroidManifest.xml);
/// MainActivity forwards it here over a method channel.
class AndroidRedirectReceiver extends RedirectReceiver {
  AndroidRedirectReceiver() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'redirect' &&
          _pending != null &&
          !_pending!.isCompleted) {
        _pending!.complete(Uri.parse(call.arguments as String));
      }
    });
  }

  static const scheme = 'com.cranthony.timetracker';
  static const _channel = MethodChannel('time_tracker/oauth');

  Completer<Uri>? _pending;

  @override
  Uri get redirectUri => Uri.parse('$scheme://oauth/callback');

  @override
  Future<Uri> authorize(Uri authorizationUrl) async {
    final pending = _pending = Completer<Uri>();
    await _openBrowser(authorizationUrl);
    return pending.future.timeout(const Duration(minutes: 10));
  }
}
