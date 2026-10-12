import 'package:flutter/foundation.dart';

/// Whether this build skips sign-in, passed at build time -- for a
/// corporate network, where a proxy in front of the server signs people
/// in:
///   flutter build web --dart-define=DISABLE_AUTH=true
/// true, 1 or yes, in any case. Such a build never signs in, sends no
/// bearer token, and says so on every screen ([SignInOffBanner]).
const _disableAuth = String.fromEnvironment('DISABLE_AUTH');

/// Whether [value] turns sign-in off: true, 1 or yes, in any case.
bool turnsSignInOff(String value) =>
    const {'true', '1', 'yes'}.contains(value.trim().toLowerCase());

/// Whether this build skips sign-in.
final bool signInOff = turnsSignInOff(_disableAuth);

/// Whether the server said, as the app connected, that it skips sign-in
/// (a server built with AUTH_DISABLED): the app says so too, whether or
/// not it does.
final serverSignInOff = ValueNotifier<bool>(false);

/// The app's name, as its title and About give it.
String get appName => signInOff ? 'Time Tracker (no sign-in)' : 'Time Tracker';

/// What the server's handshake says, in a build of it that skips sign-in.
bool handshakeSaysSignInOff(Map<String, dynamic> result) {
  final title = switch (result['serverInfo']) {
    {'title': final String title} => title,
    _ => '',
  };
  final instructions = result['instructions'] as String? ?? '';
  return title.endsWith('(sign-in off)') ||
      instructions.startsWith('Authentication is disabled');
}
