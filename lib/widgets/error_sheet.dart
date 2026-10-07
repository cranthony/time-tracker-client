import 'package:flutter/material.dart';

import '../services/server_errors.dart';

/// Says that [title] -- "Couldn't move it" -- and why, from [error] (or
/// [message], saying it better; or [failure], already described), in a
/// sheet over the bottom of the screen: how the app shows every failure
/// of a call to the server. With [onRetry], and a failure that trying
/// again might fix, it offers to: closing the sheet and calling it --
/// even after a refusal, with [retryRefusal] (something saved in the
/// background, which may well go through later).
/// Dismissed by swiping it down, tapping above it, Back, or Close.
Future<void> showErrorSheet(
  BuildContext context, {
  required String title,
  Object? error,
  ServerFailure? failure,
  String? message,
  VoidCallback? onRetry,
  bool retryRefusal = false,
}) async {
  final again = await _ask(
    context,
    title: title,
    failure: _failure(error, failure, message),
    canRetry: onRetry != null,
    retryRefusal: retryRefusal,
  );
  if (again) onRetry!();
}

/// Runs [action]; if it fails, says so as [showErrorSheet] does, offering
/// to run it again -- and again, while it keeps failing in a way trying
/// again might fix. Returns whether it ran, in the end.
Future<bool> runOrShowError(
  BuildContext context, {
  required String title,
  required Future<void> Function() action,
}) async {
  while (true) {
    try {
      await action();
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final again = await _ask(
        context,
        title: title,
        failure: describeServerError(e),
        canRetry: true,
      );
      if (!again || !context.mounted) return false;
    }
  }
}

ServerFailure _failure(Object? error, ServerFailure? failure, String? message) {
  assert(error != null || failure != null, 'say what failed');
  final described = failure ?? describeServerError(error!);
  return message == null ? described : ServerFailure(described.kind, message);
}

/// Shows the sheet; whether the user asked to try again.
Future<bool> _ask(
  BuildContext context, {
  required String title,
  required ServerFailure failure,
  required bool canRetry,
  bool retryRefusal = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ErrorSheet(
        title: title,
        failure: failure,
        // Neither a refusal nor being signed out passes on its own.
        canRetry:
            canRetry &&
            (retryRefusal || failure.kind != FailureKind.refused) &&
            failure.kind != FailureKind.signIn,
      ),
    ) ==
    true;

/// The sheet [showErrorSheet] shows. Pops `true` to try again.
class ErrorSheet extends StatelessWidget {
  const ErrorSheet({
    super.key,
    required this.title,
    required this.failure,
    this.canRetry = false,
  });

  final String title;
  final ServerFailure failure;
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (failure.kind) {
      FailureKind.signIn => Icons.lock_outline,
      FailureKind.connection => Icons.cloud_off,
      FailureKind.timeout || FailureKind.server => Icons.hourglass_empty,
      FailureKind.refused || FailureKind.other => Icons.error_outline,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 16),
          Text(failure.message),
          if (failure.transient) ...[
            const SizedBox(height: 8),
            Text(
              'This is usually brief.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
              if (canRetry) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
