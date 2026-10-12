import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/sign_in_mode.dart';

/// A strip across the top of every screen, above the app bar, while
/// sign-in is off -- in this build ([signInOff]), or on the server
/// ([serverSignInOff]): amber, and never dismissed, so no screen, or
/// screenshot of one, hides it. Without either, just [child].
class SignInOffBanner extends StatelessWidget {
  const SignInOffBanner({
    super.key,
    required this.child,
    this.thisBuild,
    this.server,
  });

  final Widget child;

  /// Whether this build skips sign-in; by default [signInOff].
  final bool? thisBuild;

  /// Whether the server does; by default [serverSignInOff].
  final ValueListenable<bool>? server;

  static const color = Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: server ?? serverSignInOff,
    builder: (context, serverOff, _) {
      final off = thisBuild ?? signInOff;
      if (!off && !serverOff) return child;
      final text = off
          ? 'Sign-in off: this build trusts its network'
          : 'Sign-in off: the server trusts every request';
      return Column(
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            label: text,
            child: Material(
              color: color,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_open,
                        size: 16,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The status bar's room taken already, by the strip.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
