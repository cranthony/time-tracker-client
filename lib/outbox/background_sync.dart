import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'outbox.dart';

/// Saves pending notes and action saves while the app is in the background,
/// on Android.
///
/// When the app leaves the foreground with any still pending, [schedule]
/// asks Android's WorkManager to run a task once there's a network
/// connection. The task sends everything pending; if anything is left it
/// reports failure, and WorkManager tries again later with its own
/// exponential backoff. Coming back to the foreground [cancel]s it, and
/// the app's own outboxes take over.
///
/// Elsewhere this does nothing: a minimised Windows app keeps running, so
/// its outbox keeps sending by itself.
class BackgroundSync {
  // Named when it only saved notes; kept, so a task already waiting is
  // the same one.
  static const _task = 'save-pending-notes';

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize(void Function() dispatcher) =>
      _guard(() => Workmanager().initialize(dispatcher));

  static Future<void> schedule() => _guard(
    () => Workmanager().registerOneOffTask(
      _task,
      _task,
      constraints: Constraints(networkType: NetworkType.connected),
      // Don't restart the backoff of a task that's already waiting.
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    ),
  );

  static Future<void> cancel() =>
      _guard(() => Workmanager().cancelByUniqueName(_task));

  /// Background saving is a bonus: if WorkManager misbehaves, the app
  /// still works, and still saves notes while it's open.
  static Future<void> _guard(Future<void> Function() action) async {
    if (!supported) return;
    try {
      await action();
    } catch (e, stack) {
      debugPrint('Background saving unavailable: $e\n$stack');
    }
  }

  /// Call from the background dispatcher. [build] creates the outboxes,
  /// wired to the server, without any UI.
  static void run(List<Outbox> Function() build) {
    Workmanager().executeTask((task, _) async {
      final results = [
        for (final outbox in build()) await outbox.flush(ignoreBackoff: true),
      ];
      // Returning false has WorkManager retry later. Nothing will change
      // without the user signing in, so stop in that case.
      return results.every((r) => r.remaining == 0) ||
          results.any((r) => r.needsSignIn);
    });
  }
}
