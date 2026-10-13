import 'dart:async';

import 'package:flutter/material.dart';

import 'status_bar.dart';

/// Why the open compaction proposal no longer plans -- the server's
/// `problem` -- said at the foot of the page ([StatusBar]), as the app's
/// other errors are, and in full in its sheet: not over the calendar,
/// where a long one left no room to see it.
///
/// The Events page says what it is as the proposal changes ([show]), and
/// nothing as it goes ([clear]).
class ProposalProblemStatus extends ChangeNotifier implements StatusSource {
  /// What's said when the proposal has no problem of its own to give.
  static const fallback = 'It no longer fits the calendar.';

  /// The problem said; null for none.
  String? get problem => _problem;
  String? _problem;
  bool _disposed = false;

  /// Says [problem], or nothing for null.
  void show(String? problem) {
    if (problem == _problem) return;
    _problem = problem;
    _notify();
  }

  /// Says nothing. Said once the frame's done: the page is let go of as
  /// the tree's rebuilt, when nothing else can be.
  void clear() {
    if (_problem == null) return;
    _problem = null;
    scheduleMicrotask(_notify);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Listenable get listenable => this;

  /// A problem isn't a thing waiting.
  @override
  int get count => 0;

  @override
  StatusLine? line(BuildContext context) => _problem == null
      ? null
      : const StatusLine(
          icon: Icons.report_outlined,
          text: "The proposal can't be confirmed",
          needsYou: true,
        );

  @override
  List<Widget> section(BuildContext context) {
    final problem = _problem;
    if (problem == null) return const [];
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          "The proposal can't be confirmed",
          style: theme.textTheme.titleLarge,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SelectableText(problem),
      ),
    ];
  }
}
