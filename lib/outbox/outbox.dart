import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/mcp_client.dart';
import 'outbox_store.dart';
import 'save_error.dart';

/// Something an [Outbox] keeps until the server has it, and how sending
/// it has gone so far.
abstract interface class OutboxItem<T extends OutboxItem<T>> {
  /// Local only; the server knows nothing about it.
  String get id;

  /// Failed attempts so far. Once non-zero, an earlier attempt may have
  /// reached the server even though we never heard back, so the next
  /// attempt checks for that before sending again.
  int get attempts;

  /// Why the last attempt failed, if it did.
  String? get lastError;

  /// When to try again; null means as soon as possible.
  DateTime? get nextAttemptAt;

  /// Set while some sender (this app, or its background task) has a
  /// request for it in flight.
  DateTime? get sendingSince;

  /// Whether the server refused it: it isn't sent again until it's retried
  /// (see [Outbox.retryNow]), as it would only be refused again.
  bool get refused;

  T copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    bool? refused,
  });
}

/// Items waiting to be saved to the server. New items land here first
/// (and in [OutboxStore], so they survive the app closing), then get sent
/// one at a time, oldest first, retrying with backoff until they're saved
/// or dropped. Failures the server gives ([retries] says which) wait for a
/// [retryNow] instead.
///
/// Call [start] to have it send by itself while the app is in use, and
/// [stop] when the app goes to the background. The Android background task
/// uses its own instance and calls [flush] instead; a claim on each item
/// in flight keeps the two from sending it at once.
///
/// [send] sends an item, giving an [R] (e.g. the id the server gave it);
/// [saved], [failed] and [sentAll] say how sending went.
abstract class Outbox<T extends OutboxItem<T>, R> extends ChangeNotifier {
  Outbox({required this._store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final OutboxStore<T> _store;
  final DateTime Function() _clock;

  /// How long another sender's in-flight request is trusted to finish
  /// before its item is treated as unsent again (e.g. the app was killed
  /// mid-request). Every step of a send has a timeout, so a live sender
  /// is done well within this.
  static const inFlightTimeout = Duration(minutes: 2);

  /// Gives up on a single request after this long. It may still reach the
  /// server, which the next attempt checks for.
  static const requestTimeout = Duration(seconds: 30);

  /// Gives up on reading or writing the [OutboxStore] after this long, so
  /// a store that never answers can't hold up every later change.
  static const storeTimeout = Duration(seconds: 10);

  /// 5s, 10s, 20s, 40s, then every minute.
  static Duration backoff(int attempts) =>
      Duration(seconds: min(60, 5 * pow(2, attempts - 1).toInt()));

  List<T> _items = [];
  String? _sendingId;
  bool _needsSignIn = false;
  bool _running = false;
  Timer? _timer;
  Future<FlushResult>? _flushing;
  Future<void> _lock = Future.value();

  /// Oldest first.
  List<T> get items => List.unmodifiable(_items);

  /// Whether anything is left to send: the server hasn't refused it.
  bool get hasUnsent => _items.any((item) => !item.refused);

  /// True once the server has said to sign in; nothing is sent until
  /// [retryNow] is called (e.g. after signing in).
  bool get needsSignIn => _needsSignIn;

  /// Whether [item] is being sent right now, here or by the background
  /// task. It can't be dropped then: the server may already have it.
  bool isSending(T item) =>
      item.id == _sendingId || _inFlightElsewhere(item, _clock());

  /// The time now, as this outbox tells it.
  @protected
  DateTime now() => _clock();

  /// Sends [item] to the server. [maybeSaved] says an earlier attempt may
  /// have saved it already, unheard, which this should check first.
  @protected
  Future<R> send(T item, {required bool maybeSaved});

  /// Whether a failure to send, [error], is tried again by itself, after a
  /// while. Otherwise the item waits for [retryNow], marked
  /// [OutboxItem.refused]. Everything is tried again, by default.
  @protected
  bool retries(Object error) => true;

  /// [items] in the order they're sent and listed: as added, by default.
  @protected
  List<T> order(List<T> items) => items;

  /// Called when a round of sending starts, e.g. to forget what was
  /// fetched for the last one.
  @protected
  void flushStarting() {}

  /// Called after [item] is saved, with what [send] gave, just before
  /// it's dropped.
  @protected
  void saved(T item, R result) {}

  /// Called after sending [item] failed: it's [item] as it's kept now.
  @protected
  void failed(T item) {}

  /// Called at the end of a round that saved something.
  @protected
  void sentAll() {}

  /// Picks up changes made elsewhere (the background task).
  Future<void> refresh() => change((items) => items);

  /// Sends everything that can be sent now, ignoring backoff, including
  /// what the server refused before.
  Future<FlushResult> retryNow() async {
    _needsSignIn = false;
    await change(
      (items) => [
        for (final item in items)
          item.refused ? item.copyWith(refused: false) : item,
      ],
    );
    return flush(ignoreBackoff: true);
  }

  void start() {
    _running = true;
    unawaited(refresh().then((_) => schedule(immediately: true)));
  }

  /// Stops sending new items. A request already in flight still finishes.
  void stop() {
    _running = false;
    _timer?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Sends due items one at a time, oldest first, until one fails in a way
  /// that's tried again, or none are left.
  ///
  /// A failure to read or write the store ends the round; whatever is
  /// left is tried again on the next.
  Future<FlushResult> flush({bool ignoreBackoff = false}) =>
      _flushing ??= _flush(ignoreBackoff)
          .catchError((Object e, StackTrace stack) {
            debugPrint('Saving stopped: $e\n$stack');
            return _result();
          })
          .whenComplete(() {
            _flushing = null;
            schedule();
          });

  Future<FlushResult> _flush(bool ignoreBackoff) async {
    flushStarting();
    var savedAny = false;
    try {
      while (true) {
        await refresh();
        final now = _clock();
        final next = _items
            .where((item) => _isDue(item, now, ignoreBackoff))
            .firstOrNull;
        if (next == null) break;

        // Claimed before the first await, so dropping it is refused from
        // here on. Whatever happens next, even the store failing, the
        // claim is let go of below, or it would look in flight until the
        // app restarts.
        _sendingId = next.id;
        try {
          // If it was dropped just before, it's gone: skip it.
          var stillPending = false;
          await change((items) {
            stillPending = items.any((item) => item.id == next.id);
            return [
              for (final item in items)
                item.id == next.id
                    ? item.copyWith(sendingSince: () => now)
                    : item,
            ];
          });
          if (!stillPending) continue;
          // An earlier attempt, or a sender that gave up on it (see
          // inFlightTimeout), may have saved it even though nobody heard.
          final result = await send(
            next,
            maybeSaved: next.attempts > 0 || next.sendingSince != null,
          );
          _sendingId = null;
          savedAny = true;
          // Said before it's dropped, so whatever shows it can show it as
          // saved without it going missing in between.
          saved(next, result);
          await change(
            (items) => [
              for (final item in items)
                if (item.id != next.id) item,
            ],
          );
        } on SignInRequiredException {
          _sendingId = null;
          _needsSignIn = true;
          final kept = next.copyWith(
            sendingSince: () => null,
            lastError: () => 'Sign in to save',
          );
          await _replace(kept);
          failed(kept);
          break;
        } catch (e) {
          _sendingId = null;
          if (!retries(e)) {
            // The server answered, saying no: it wasn't saved, and other
            // items may well be.
            final kept = next.copyWith(
              attempts: 0,
              sendingSince: () => null,
              lastError: () => describeSaveError(e),
              nextAttemptAt: () => null,
              refused: true,
            );
            await _replace(kept);
            failed(kept);
            continue;
          }
          final attempts = next.attempts + 1;
          final kept = next.copyWith(
            attempts: attempts,
            sendingSince: () => null,
            lastError: () => describeSaveError(e),
            nextAttemptAt: () => _clock().add(backoff(attempts)),
          );
          await _replace(kept);
          failed(kept);
          // Most failures are the connection or the server; the rest would
          // likely fail the same way, so leave them for the next round.
          break;
        } finally {
          _sendingId = null;
        }
        if (!_running && !ignoreBackoff) break;
      }
    } finally {
      if (savedAny) sentAll();
    }
    return _result();
  }

  FlushResult _result() => FlushResult(
    remaining: _items.where((item) => !item.refused).length,
    needsSignIn: _needsSignIn,
  );

  bool _isDue(T item, DateTime now, bool ignoreBackoff) {
    if (item.refused) return false;
    if (item.id == _sendingId || _inFlightElsewhere(item, now)) return false;
    final at = item.nextAttemptAt;
    return ignoreBackoff || at == null || !at.isAfter(now);
  }

  bool _inFlightElsewhere(T item, DateTime now) {
    final since = item.sendingSince;
    return item.id != _sendingId &&
        since != null &&
        now.difference(since) < inFlightTimeout;
  }

  /// Sends what's due when it's due, while running.
  @protected
  void schedule({bool immediately = false}) {
    _timer?.cancel();
    if (!_running || _needsSignIn) return;
    final now = _clock();
    DateTime? next = immediately && hasUnsent ? now : null;
    for (final item in _items) {
      if (item.refused) continue;
      final at = _inFlightElsewhere(item, now)
          // Look again soon: the background task may finish it any moment.
          ? now.add(const Duration(seconds: 5))
          : item.nextAttemptAt ?? now;
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next == null) return;
    final delay = next.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_running) flush();
    });
  }

  Future<void> _replace(T item) =>
      change((items) => [for (final i in items) i.id == item.id ? item : i]);

  /// Applies [change] to the items: at once, to those listed, then to
  /// those kept, which it reads, changes and writes back, then lists.
  /// Serialised, so concurrent changes from this isolate don't clobber
  /// each other.
  @protected
  Future<void> change(List<T> Function(List<T> items) change) {
    final shown = order(change(_items));
    if (!identical(shown, _items)) {
      _items = shown;
      notifyListeners();
    }
    final result = _lock.then((_) async {
      final before = await _store.load().timeout(storeTimeout);
      final after = order(change(before));
      if (!identical(after, before)) {
        await _store.save(after).timeout(storeTimeout);
      }
      _items = after;
      notifyListeners();
    });
    _lock = result.catchError((_) {});
    return result;
  }
}

class FlushResult {
  const FlushResult({required this.remaining, required this.needsSignIn});

  /// How many items are left to send, not counting those the server
  /// refused, which wait to be retried.
  final int remaining;
  final bool needsSignIn;
}
