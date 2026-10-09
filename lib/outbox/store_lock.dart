import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

/// Lets one change at a time be made to what an [OutboxStore] keeps:
/// read, changed and written back whole, with no other in between. The
/// app and its Android background task each have their own outboxes --
/// in other isolates, of the one process -- sharing what's kept; without
/// this, one's change could write over the other's, losing a write, and
/// both could claim the same one to send.
abstract interface class StoreLock {
  /// Runs [action] holding the lock, once whoever holds it lets go -- or
  /// throws a [TimeoutException], running nothing, if that's not within
  /// [wait]. [action] can [keepUntil] what it started is done -- a write
  /// that outlives its timeout, say -- for the lock to be held till then.
  Future<T> hold<T>(
    Future<T> Function(void Function(Future<void> done) keepUntil) action, {
    Duration wait,
  });
}

/// No lock: for a store only one outbox uses, as in tests.
class NoStoreLock implements StoreLock {
  const NoStoreLock();

  @override
  Future<T> hold<T>(
    Future<T> Function(void Function(Future<void> done) keepUntil) action, {
    Duration wait = Duration.zero,
  }) => action((_) {});
}

/// A lock within one isolate: each [hold] waits for the one before it.
class SerialStoreLock implements StoreLock {
  Future<void> _last = Future.value();

  @override
  Future<T> hold<T>(
    Future<T> Function(void Function(Future<void> done) keepUntil) action, {
    Duration wait = Duration.zero,
  }) {
    final pending = <Future<void>>[];
    final result = _last.then((_) => action(pending.add));
    _last = result
        .then<void>((_) {}, onError: (Object _) {})
        .then(
          (_) => Future.wait([
            for (final p in pending) p.catchError((Object _) {}),
          ]),
        );
    return result;
  }
}

/// A lock every isolate of the process shares, by [name], with
/// [IsolateNameServer]: whoever registers a port under it holds it, as
/// only one can. While it's held, the holder answers pings on that port,
/// so a holder that died holding it -- the background task's isolate,
/// shut down mid-change -- is found out, and the lock taken from it.
///
/// On Android, WorkManager runs the background task in the app's
/// process, so this keeps the app and its task apart. The web has one
/// isolate, and nothing to keep apart.
class IsolateStoreLock implements StoreLock {
  const IsolateStoreLock(this.name);

  final String name;

  /// How long a holder has to answer a ping before it's taken for dead.
  /// Generous: a live one answers between any two of its awaits.
  static const pingTimeout = Duration(seconds: 3);

  /// How long to wait between tries while it's held.
  static const _poll = Duration(milliseconds: 10);

  /// One for [key]'s store, or none on the web.
  static StoreLock forKey(String key) =>
      kIsWeb ? const NoStoreLock() : IsolateStoreLock('outbox_store:$key');

  @override
  Future<T> hold<T>(
    Future<T> Function(void Function(Future<void> done) keepUntil) action, {
    Duration wait = const Duration(seconds: 30),
  }) async {
    final port = ReceivePort();
    // Answers each ping -- a port to say so on -- while held.
    port.listen((message) {
      if (message is SendPort) message.send(true);
    });
    final me = port.sendPort;
    try {
      await _acquire(me, DateTime.now().add(wait));
    } catch (_) {
      port.close();
      rethrow;
    }
    final pending = <Future<void>>[];
    void release() {
      if (IsolateNameServer.lookupPortByName(name) == me) {
        IsolateNameServer.removePortNameMapping(name);
      }
      port.close();
    }

    try {
      return await action(pending.add);
    } finally {
      // Not before what it started is done.
      if (pending.isEmpty) {
        release();
      } else {
        unawaited(
          Future.wait([for (final p in pending) p.catchError((Object _) {})])
              .whenComplete(release),
        );
      }
    }
  }

  Future<void> _acquire(SendPort me, DateTime deadline) async {
    while (!IsolateNameServer.registerPortWithName(me, name)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('The outbox store is busy elsewhere.');
      }
      final holder = IsolateNameServer.lookupPortByName(name);
      if (holder == null) continue; // Let go of just now.
      if (await _answers(holder)) {
        await Future<void>.delayed(_poll);
        continue;
      }
      // Dead: take it -- unless someone else just did.
      if (IsolateNameServer.lookupPortByName(name) == holder) {
        IsolateNameServer.removePortNameMapping(name);
      }
    }
  }

  /// Whether [holder] is alive: it answers a ping -- or lets go meanwhile,
  /// having been alive to (a ping it gets after it lets go, it doesn't
  /// answer). False if neither, within [pingTimeout].
  Future<bool> _answers(SendPort holder) async {
    final reply = ReceivePort();
    final answered = reply.first;
    try {
      holder.send(reply.sendPort);
      final deadline = DateTime.now().add(pingTimeout);
      while (DateTime.now().isBefore(deadline)) {
        try {
          await answered.timeout(_poll);
          return true;
        } on TimeoutException {
          if (IsolateNameServer.lookupPortByName(name) != holder) return true;
        }
      }
      return false;
    } finally {
      reply.close();
    }
  }
}
