import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'outbox.dart';

/// Saves pending notes, action saves and changes to events while the app
/// is in the background, on Android; and, at the times [scheduleRefresh]
/// sets, fetches what the app keeps, so it's fresh when it opens.
///
/// When the app leaves the foreground with any still pending, [schedule]
/// asks Android's WorkManager to run a task once there's a network
/// connection. The task sends everything pending; if anything is left it
/// reports failure, and WorkManager tries again later with its own
/// exponential backoff. Coming back to the foreground [cancel]s it, and
/// the app's own outboxes take over.
///
/// WorkManager stops a task it cancels -- or that runs too long, or loses
/// its network -- by shutting its engine down. Told first, the task
/// finishes the item it's sending, if any ([Outbox.finishSending]), and sends no
/// more: shut down between the server saving an item and the task taking
/// it off what's kept, the item would stay, claimed, till its claim ran
/// out ([Outbox.inFlightTimeout]), and then be sent again.
///
/// Elsewhere this does nothing: a minimised Windows app keeps running, so
/// its outbox keeps sending by itself.
class BackgroundSync {
  // Named when it only saved notes; kept, so a task already waiting is
  // the same one.
  static const _task = 'save-pending-notes';

  /// The background fetch's task: one at a time, each scheduling the
  /// next.
  static const refreshTask = 'refresh-cache';

  /// The weather's background fetch: every so often, while it's on.
  static const weatherTask = 'refresh-weather';

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

  /// Schedules the background fetch [delay] from now, once there's a
  /// network connection, in place of one already waiting. From the fetch
  /// itself, [fromTask], the next is queued after it, so as not to cancel
  /// it while it runs.
  static Future<void> scheduleRefresh(
    Duration delay, {
    bool fromTask = false,
  }) => _guard(
    () => Workmanager().registerOneOffTask(
      refreshTask,
      refreshTask,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: fromTask
          ? ExistingWorkPolicy.update
          : ExistingWorkPolicy.replace,
    ),
  );

  /// Fetches the weather [every] so often, once there's a network
  /// connection -- Android's minimum is 15 minutes -- in place of any
  /// schedule before; null, not at all.
  static Future<void> scheduleWeather(Duration? every) => _guard(
    () => every == null
        ? Workmanager().cancelByUniqueName(weatherTask)
        : Workmanager().registerPeriodicTask(
            weatherTask,
            weatherTask,
            frequency: every,
            constraints: Constraints(networkType: NetworkType.connected),
            existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
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
  /// wired to the server, without any UI; [refresh] runs the background
  /// fetch, and [weather] the weather's; [done] runs as each task ends,
  /// however it went.
  static void run(
    List<Outbox> Function() build, {
    Future<void> Function()? refresh,
    Future<void> Function()? weather,
    Future<void> Function()? done,
  }) {
    // The outboxes of the task running, if one is.
    var outboxes = const <Outbox>[];
    var stopped = false;
    Workmanager().executeTask(
      onTaskStopped: (task, _) async {
        if (task != _task) return;
        stopped = true;
        // Not past the claim's timeout: by then the app may be sending
        // it anyway.
        await Future.wait([for (final o in outboxes) o.finishSending()])
            .timeout(Outbox.inFlightTimeout, onTimeout: () => const []);
      },
      (task, _) async {
        try {
          if (task == weatherTask) {
            // Every so often anyway: a failed one waits for the next.
            await weather?.call();
            return true;
          }
          if (task == refreshTask) {
            // It schedules the next itself; a failed one waits for that.
            await refresh?.call();
            return true;
          }
          stopped = false;
          outboxes = build();
          final results = [
            for (final outbox in outboxes)
              if (!stopped) await outbox.flush(ignoreBackoff: true),
          ];
          // Stopped, it's WorkManager that says whether it runs again.
          if (stopped) return true;
          // Returning false has WorkManager retry later. Nothing will change
          // without the user signing in, so stop in that case.
          // Nor will anything be sent past a write the server refused.
          return results.every((r) => r.remaining == 0 || r.blocked) ||
              results.any((r) => r.needsSignIn);
        } finally {
          outboxes = const [];
          await done?.call();
        }
      },
    );
  }
}
