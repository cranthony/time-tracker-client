import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'note_outbox.dart';

/// Saves pending notes while the app is in the background, on Android.
///
/// When the app leaves the foreground with notes still pending, [schedule]
/// asks Android's WorkManager to run a task once there's a network
/// connection. The task sends everything pending; if anything is left it
/// reports failure, and WorkManager tries again later with its own
/// exponential backoff. Coming back to the foreground [cancel]s it, and
/// the app's own [NoteOutbox] takes over.
///
/// Elsewhere this does nothing: a minimised Windows app keeps running, so
/// its outbox keeps sending by itself.
class BackgroundSync {
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

  /// Call from the background dispatcher. [build] creates an outbox wired
  /// to the server, without any UI.
  static void run(NoteOutbox Function() build) {
    Workmanager().executeTask((task, _) async {
      final result = await build().flush(ignoreBackoff: true);
      // Returning false has WorkManager retry later. Nothing will change
      // without the user signing in, so stop in that case.
      return result.remaining == 0 || result.needsSignIn;
    });
  }
}
