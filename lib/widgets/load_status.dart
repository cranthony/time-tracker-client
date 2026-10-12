import 'dart:async';

import 'package:flutter/material.dart';

import '../outbox/outbox.dart';
import '../services/server_errors.dart';
import 'status_bar.dart';

/// How loading [what] -- "events" -- from the server is going, for a page
/// that loads it: after a failure, it's tried again by itself, 5s, 10s,
/// 20s, 40s, then every minute after ([Outbox.backoff]), until it
/// loads. While what was loaded before is still shown ([hasData]), the
/// [StatusBar] says so, and its sheet why, to try again now; with
/// nothing shown, the page says so itself ([LoadError]).
///
/// The page [bind]s what loads it, says how each load went ([loaded],
/// [failed]), and [unbind]s as it goes, which forgets any failure: a
/// page loads afresh when it's back. A sign-in isn't a failure to try
/// again: the page asks for it.
class LoadStatus extends ChangeNotifier implements StatusSource {
  LoadStatus(this.what, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String what;
  final DateTime Function() _clock;

  Future<void> Function()? _load;
  Timer? _timer;
  bool _disposed = false;

  /// Why the last load failed, if it did.
  Object? get error => _error;
  Object? _error;

  /// Whether what's shown is what was loaded before the failure.
  bool get hasData => _hasData;
  bool _hasData = false;

  /// Failed loads in a row.
  int get attempts => _attempts;
  int _attempts = 0;

  /// When it's tried again by itself, after a failure.
  DateTime? get nextAttemptAt => _nextAttemptAt;
  DateTime? _nextAttemptAt;

  /// Has [load] load it again, after a failure, by itself or when asked
  /// ([retry]).
  void bind(Future<void> Function() load) => _load = load;

  /// Lets go of what [bind] gave, forgetting any failure. Said once the
  /// frame's done: the page is let go of as the tree's rebuilt, when
  /// nothing else can be.
  void unbind() {
    _load = null;
    if (_forget()) scheduleMicrotask(_notify);
  }

  /// Forgets any failure, and stops trying again: what's shown changed.
  void reset() {
    if (_forget()) _notify();
  }

  /// Forgets any failure; whether there was one.
  bool _forget() {
    _timer?.cancel();
    if (_error == null && _attempts == 0) return false;
    _error = null;
    _attempts = 0;
    _nextAttemptAt = null;
    return true;
  }

  /// The last load worked.
  void loaded() => reset();

  /// The last load failed with [error], [hasData] saying whether what
  /// was loaded before is still shown: it's tried again after a while --
  /// unless it's to sign in, which only signing in helps.
  void failed(Object error, {required bool hasData}) {
    _error = error;
    _hasData = hasData;
    _attempts++;
    _timer?.cancel();
    if (describeServerError(error).kind == FailureKind.signIn) {
      _nextAttemptAt = null;
    } else {
      final at = _nextAttemptAt = _clock().add(Outbox.backoff(_attempts));
      _timer = Timer(at.difference(_clock()), () => _load?.call());
    }
    _notify();
  }

  /// Loads it again now.
  Future<void> retry() async {
    _timer?.cancel();
    await _load?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  Listenable get listenable => this;

  /// Failures to load aren't things waiting.
  @override
  int get count => 0;

  ServerFailure? get _failure => switch (_error) {
    final error? => describeServerError(error),
    null => null,
  };

  @override
  StatusLine? line(BuildContext context) => switch ((_failure, _hasData)) {
    (final failure?, true) when failure.kind != FailureKind.signIn =>
      StatusLine(
        icon: Icons.cloud_off_outlined,
        text: switch (_nextAttemptAt) {
          final at? =>
            "Couldn't load $what: trying again at ${_at(context, at)}",
          null => "Couldn't load $what",
        },
      ),
    _ => null,
  };

  @override
  List<Widget> section(BuildContext context) {
    final failure = _failure;
    if (failure == null || failure.kind == FailureKind.signIn) return const [];
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text("Couldn't load $what", style: theme.textTheme.titleLarge),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          [
            failure.message,
            if (_hasData) 'What\'s shown may be out of date.',
            if (_nextAttemptAt case final at?)
              'Trying again at ${_at(context, at)}.',
          ].join(' '),
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again now'),
          ),
        ),
      ),
    ];
  }
}

String _at(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
