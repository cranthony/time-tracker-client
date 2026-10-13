import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/sign_in_mode.dart';

/// A strip across the top of every screen, above the app bar, while the
/// server says it skips sign-in ([serverSignInOff]): amber, and never
/// dismissed, so no screen, or screenshot of one, hides it. Otherwise,
/// just [child].
class SignInOffBanner extends StatelessWidget {
  const SignInOffBanner({super.key, required this.child, this.server});

  final Widget child;

  /// Whether the server skips sign-in; by default [serverSignInOff].
  final ValueListenable<bool>? server;

  static const color = Color(0xFFFFC107);

  static const text = 'Sign-in off: the server trusts every request';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: server ?? serverSignInOff,
    builder: (context, off, _) {
      if (!off) return child;
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
                    children: const [
                      Icon(Icons.lock_open, size: 16, color: Colors.black87),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
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
