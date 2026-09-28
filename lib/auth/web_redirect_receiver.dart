import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'redirect_receiver.dart';

/// For the web: sign-in runs in a popup, which the authorization server
/// redirects to web/callback.html on this app's own origin. That page
/// relays its URL back over a BroadcastChannel. Unlike `window.opener`,
/// that still works if the sign-in pages set Cross-Origin-Opener-Policy.
class WebRedirectReceiver extends RedirectReceiver {
  WebRedirectReceiver({this.timeout = const Duration(minutes: 5)});

  /// Must match the channel name in web/callback.html.
  static const channelName = 'time_tracker_oauth';

  final Duration timeout;

  web.Window? _popup;

  @override
  Uri get redirectUri => Uri.base.resolve('callback.html');

  @override
  void prepare() {
    // Opened blank now, while the click still allows popups; authorize()
    // points it at the sign-in page once that URL is known.
    _popup = web.window.open(
      '',
      'time_tracker_sign_in',
      'popup,width=500,height=700',
    );
  }

  @override
  void cancel() {
    _popup?.close();
    _popup = null;
  }

  @override
  Future<Uri> authorize(Uri authorizationUrl) async {
    final popup = _popup;
    _popup = null;
    if (popup == null) {
      throw StateError(
        'The browser blocked the sign-in window. Allow popups for this '
        'site and try again.',
      );
    }

    final redirect = Completer<Uri>();
    final channel = web.BroadcastChannel(channelName);
    channel.onmessage = (web.MessageEvent event) {
      final data = event.data;
      if (data.isA<JSString>() && !redirect.isCompleted) {
        redirect.complete(Uri.parse((data as JSString).toDart));
      }
    }.toJS;

    try {
      popup.location.href = authorizationUrl.toString();
      return await redirect.future.timeout(timeout);
    } finally {
      channel.close();
    }
  }
}
