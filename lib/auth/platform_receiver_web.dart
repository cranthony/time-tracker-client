import 'redirect_receiver.dart';
import 'web_redirect_receiver.dart';

String get platformName => 'web';

RedirectReceiver platformRedirectReceiver() => WebRedirectReceiver();

/// See OAuthClient.viaResourceServer.
const oauthViaResourceServer = true;
