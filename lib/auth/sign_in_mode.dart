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

/// The flag a server built with AUTH_DISABLED sets in its handshake's
/// `_meta` (its auth_mode::META_KEY).
const authDisabledMetaKey = 'time-tracking/authDisabled';

/// Whether the server's handshake says it skips sign-in: its `_meta`
/// flag, not the words it also says it in, which may change.
bool handshakeSaysSignInOff(Map<String, dynamic> result) =>
    switch (result['_meta']) {
      {authDisabledMetaKey: true} => true,
      _ => false,
    };
