import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/note.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import 'outbox_store.dart';
import 'pending_note.dart';

/// Notes waiting to be saved to the server. New notes land here first (and
/// in [OutboxStore], so they survive the app closing), then get sent one at
/// a time, oldest first, retrying with backoff until they're saved or
/// cancelled.
///
/// Call [start] to have it send by itself while the app is in use, and
/// [stop] when the app goes to the background. The Android background task
/// uses its own instance and calls [flush] instead.
class NoteOutbox extends ChangeNotifier {
  NoteOutbox({
    required this._store,
    required this._repository,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random();

  final OutboxStore _store;
  final NotesRepository _repository;
  final DateTime Function() _clock;
  final Random _random;

  /// How long another sender's in-flight request is trusted to finish
  /// before its note is treated as unsent again (e.g. the app was killed
  /// mid-request).
  static const inFlightTimeout = Duration(minutes: 2);

  /// Gives up on a single request after this long. It may still reach the
  /// server, which the next attempt checks for.
  static const requestTimeout = Duration(seconds: 30);

  List<PendingNote> _pending = [];
  String? _sendingId;
  bool _needsSignIn = false;
  bool _running = false;
  Timer? _timer;
  Future<FlushResult>? _flushing;
  Future<void> _lock = Future.value();

  /// Oldest first.
  List<PendingNote> get pending => List.unmodifiable(_pending);

  /// True once the server has said to sign in; nothing is sent until
  /// [retryNow] is called (e.g. after signing in).
  bool get needsSignIn => _needsSignIn;

  /// Whether [note] is being sent right now, here or by the background
  /// task. It can't be cancelled then: the server may already have it.
  bool isSending(PendingNote note) =>
      note.id == _sendingId || _inFlightElsewhere(note, _clock());

  /// Called after each note is saved.
  VoidCallback? onSaved;

  /// Picks up changes made elsewhere (the background task).
  Future<void> refresh() => _update((notes) => notes);

  Future<PendingNote> add(Note note) async {
    final pending = PendingNote(
      id: '${_clock().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}',
      // Whole seconds, so the note can be recognised if the server stores
      // it with less precision (see _alreadySaved).
      note: Note(
        timestamp: _truncateToSeconds(note.timestamp),
        description: note.description,
      ),
    );
    await _update((notes) => [...notes, pending]);
    _schedule(immediately: true);
    return pending;
  }

  /// Drops [note] without sending it. Returns false if it's being sent.
  Future<bool> cancel(PendingNote note) async {
    if (isSending(note)) return false;
    await _update((notes) => notes.where((n) => n.id != note.id).toList());
    _schedule();
    return true;
  }

  /// Puts back a note removed by [cancel].
  Future<void> restore(PendingNote note) async {
    await _update((notes) => [...notes, note]);
    _schedule(immediately: true);
  }

  /// Sends everything that's due now, ignoring backoff.
  Future<FlushResult> retryNow() {
    _needsSignIn = false;
    return flush(ignoreBackoff: true);
  }

  void start() {
    _running = true;
    unawaited(refresh().then((_) => _schedule(immediately: true)));
  }

  /// Stops sending new notes. A request already in flight still finishes.
  void stop() {
    _running = false;
    _timer?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Sends due notes one at a time, oldest first, until one fails or none
  /// are left.
  Future<FlushResult> flush({bool ignoreBackoff = false}) =>
      _flushing ??= _flush(ignoreBackoff).whenComplete(() {
        _flushing = null;
        _schedule();
      });

  Future<FlushResult> _flush(bool ignoreBackoff) async {
    List<Note>? onServer;
    while (true) {
      await refresh();
      final now = _clock();
      final next = _pending
          .where((n) => _isDue(n, now, ignoreBackoff))
          .firstOrNull;
      if (next == null) break;

      // Claimed before the first await, so cancel() refuses it from here
      // on; and if it was cancelled just before, it's gone: skip it.
      _sendingId = next.id;
      var stillPending = false;
      await _update((notes) {
        stillPending = notes.any((n) => n.id == next.id);
        return [
          for (final n in notes)
            n.id == next.id ? n.copyWith(sendingSince: () => now) : n,
        ];
      });
      if (!stillPending) {
        _sendingId = null;
        continue;
      }
      try {
        if (next.attempts > 0) {
          onServer ??= await _repository.uncompactedNotes().timeout(
            requestTimeout,
          );
        }
        if (onServer == null || !_alreadySaved(next.note, onServer)) {
          await _repository.addNote(next.note).timeout(requestTimeout);
        }
        _sendingId = null;
        await _update((notes) => notes.where((n) => n.id != next.id).toList());
        onSaved?.call();
      } on SignInRequiredException {
        _sendingId = null;
        _needsSignIn = true;
        await _replace(
          next.copyWith(
            sendingSince: () => null,
            lastError: () => 'Sign in to save',
          ),
        );
        break;
      } catch (e) {
        _sendingId = null;
        final attempts = next.attempts + 1;
        await _replace(
          next.copyWith(
            attempts: attempts,
            sendingSince: () => null,
            lastError: () => _describe(e),
            nextAttemptAt: () => _clock().add(backoff(attempts)),
          ),
        );
        // Most failures are the connection or the server; the rest would
        // likely fail the same way, so leave them for the next round.
        break;
      }
      if (!_running && !ignoreBackoff) break;
    }
    return FlushResult(remaining: _pending.length, needsSignIn: _needsSignIn);
  }

  /// 5s, 10s, 20s, 40s, then every minute.
  static Duration backoff(int attempts) =>
      Duration(seconds: min(60, 5 * pow(2, attempts - 1).toInt()));

  bool _isDue(PendingNote note, DateTime now, bool ignoreBackoff) {
    if (note.id == _sendingId || _inFlightElsewhere(note, now)) return false;
    final at = note.nextAttemptAt;
    return ignoreBackoff || at == null || !at.isAfter(now);
  }

  bool _inFlightElsewhere(PendingNote note, DateTime now) {
    final since = note.sendingSince;
    return note.id != _sendingId &&
        since != null &&
        now.difference(since) < inFlightTimeout;
  }

  /// Whether an earlier attempt already saved [note], but we never heard.
  static bool _alreadySaved(Note note, List<Note> onServer) => onServer.any(
    (n) =>
        (n.description ?? '') == (note.description ?? '') &&
        n.timestamp.difference(note.timestamp).abs() <
            const Duration(seconds: 1),
  );

  void _schedule({bool immediately = false}) {
    _timer?.cancel();
    if (!_running || _needsSignIn || _pending.isEmpty) return;
    final now = _clock();
    var next = immediately ? now : null;
    for (final note in _pending) {
      final at = _inFlightElsewhere(note, now)
          // Look again soon: the background task may finish it any moment.
          ? now.add(const Duration(seconds: 5))
          : note.nextAttemptAt ?? now;
      if (next == null || at.isBefore(next)) next = at;
    }
    final delay = next!.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (_running) flush();
    });
  }

  Future<void> _replace(PendingNote note) =>
      _update((notes) => [for (final n in notes) n.id == note.id ? note : n]);

  /// Reads the store, applies [change], writes it back and notifies.
  /// Serialised, so concurrent changes from this isolate don't clobber
  /// each other.
  Future<void> _update(List<PendingNote> Function(List<PendingNote>) change) {
    final result = _lock.then((_) async {
      final before = await _store.load();
      final after = change(before)
        ..sort((a, b) => a.note.timestamp.compareTo(b.note.timestamp));
      if (!identical(after, before)) await _store.save(after);
      _pending = after;
      notifyListeners();
    });
    _lock = result.catchError((_) {});
    return result;
  }

  static DateTime _truncateToSeconds(DateTime t) => t.subtract(
    Duration(microseconds: t.microsecond, milliseconds: t.millisecond),
  );

  static String _describe(Object e) => switch (e) {
    McpException(:final message) => message,
    TimeoutException() => 'The server took too long to answer',
    http.ClientException() => 'No connection to the server',
    _ => e.toString().replaceFirst(RegExp(r'^\w*Exception: '), ''),
  };
}

class FlushResult {
  const FlushResult({required this.remaining, required this.needsSignIn});
  final int remaining;
  final bool needsSignIn;
}
