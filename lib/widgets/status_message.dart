import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/server_errors.dart';
import 'hotkeys.dart';

/// The button a page signs in with ([onPressed]), saying so while
/// [signingIn]: S presses it while it's shown, and holding Ctrl shows S
/// on it.
class SignInButton extends StatelessWidget {
  const SignInButton({
    super.key,
    required this.signingIn,
    required this.onPressed,
  });

  final bool signingIn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HotkeyBindings(
    bindings: [
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyS),
        onPressed,
        when: () => !signingIn && isPainted(context),
      ),
    ],
    child: HotkeyHint(
      Hotkey.signIn,
      child: FilledButton(
        onPressed: signingIn ? null : onPressed,
        child: Text(signingIn ? 'Waiting for browser…' : 'Sign in'),
      ),
    ),
  );
}

/// Lets a lone message fill the screen and still support pull-to-refresh.
class FillViewport extends StatelessWidget {
  const FillViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// An icon, a message, and optionally a button.
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// Why [what] -- "events" -- couldn't be loaded, from [error], with a
/// button to try again ([onRetry]) when that might help: how every page
/// says so. [stale]: what's shown is what was loaded before. [retryingAt]:
/// when it's tried again by itself.
class LoadError extends StatelessWidget {
  const LoadError({
    super.key,
    required this.what,
    required this.error,
    this.stale = false,
    this.retryingAt,
    this.onRetry,
  });

  final String what;
  final Object error;
  final bool stale;
  final DateTime? retryingAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = describeServerError(error);
    return StatusMessage(
      icon: switch (failure.kind) {
        FailureKind.signIn => Icons.lock_outline,
        FailureKind.refused || FailureKind.other => Icons.error_outline,
        _ => Icons.cloud_off,
      },
      text: [
        stale
            ? "Couldn't load $what. These may be out of date."
            : "Couldn't load $what.",
        failure.message,
        if (retryingAt case final at?)
          'Trying again at '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()))}.',
      ].join('\n'),
      action: onRetry == null || failure.kind == FailureKind.signIn
          ? null
          : OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}
