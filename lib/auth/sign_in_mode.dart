import 'package:flutter/foundation.dart';

/// Whether the server said, as the app last connected, that it skips
/// sign-in -- a server built with AUTH_DISABLED, for a corporate network
/// whose proxy signs people in. The app connects before it signs in, and
/// signs in only when a server asks (see [McpClient]), so with such a
/// server it never does; this is what has it say so, on every screen
/// ([SignInOffBanner]), in About and in Settings.
final serverSignInOff = ValueNotifier<bool>(false);

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
