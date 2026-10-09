import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a [ProposalNotice] says came of a change to the proposal, sent
/// from the queue.
enum ProposalNoticeKind {
  /// An edit, saved, replaced changes Claude made after the user looked.
  replaced,

  /// Confirmed, or finished: it's history.
  applied,

  /// The calendar or notes changed since it was planned: a new revision,
  /// to confirm again.
  rechecked,

  /// A write that can never succeed stopped its apply: what's left is a
  /// new revision, to confirm again.
  rebuilt,

  /// It can't be planned any more: it's gone to Claude.
  needsClaude,

  /// It was given up.
  abandoned,
}

/// Something that came of a change to the open proposal sent from the
/// queue -- maybe in the background, with the app closed -- for the
/// Events page to say until the user's seen it: what it was about, the
/// server's [message], and the events it names.
class ProposalNotice {
  const ProposalNotice({
    required this.id,
    required this.kind,
    required this.proposalId,
    required this.at,
    this.revision,
    this.message,
    this.eventIds = const [],
    this.eventNames = const [],
  });

  final String id;
  final ProposalNoticeKind kind;
  final String proposalId;

  /// When it came.
  final DateTime at;

  /// The proposal's revision it came to, if it's still open.
  final int? revision;

  /// What the server said of it.
  final String? message;

  /// The events it names -- those an edit replaced Claude's changes to --
  /// and what each is called.
  final List<String> eventIds;
  final List<String> eventNames;

  /// What it says, in a line or two.
  String get text {
    final names = eventNames.isEmpty
        ? 'an event'
        : eventNames.length == 1
        ? eventNames.single
        : '${eventNames.sublist(0, eventNames.length - 1).join(', ')} and '
              '${eventNames.last}';
    return switch (kind) {
      ProposalNoticeKind.replaced =>
        "Your change replaced Claude's newer change to $names, made after "
            'you looked. Check it says what happened.',
      ProposalNoticeKind.applied =>
        'Your confirm went through: what happened is recorded.',
      ProposalNoticeKind.rechecked =>
        'Your confirm came back: the calendar or notes changed since it was '
            'planned, so it was planned again'
            '${revision == null ? '' : ' as revision $revision'}. Review '
            "what changed, and confirm that.",
      ProposalNoticeKind.rebuilt =>
        "Some of it couldn't be applied, so what's left was planned again"
            '${revision == null ? '' : ' as revision $revision'}. Review it, '
            'and confirm again.',
      ProposalNoticeKind.needsClaude =>
        "It can't be planned as it is any more, so it's gone to Claude with "
            "a note saying why. It'll come back revised, to confirm.",
      ProposalNoticeKind.abandoned => 'It was abandoned.',
    };
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'proposal_id': proposalId,
    'at': at.toUtc().toIso8601String(),
    'revision': ?revision,
    'message': ?message,
    if (eventIds.isNotEmpty) 'event_ids': eventIds,
    if (eventNames.isNotEmpty) 'event_names': eventNames,
  };

  static ProposalNotice? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ProposalNoticeKind.values.asNameMap()[json['kind']];
    final at = DateTime.tryParse('${json['at']}');
    if (kind == null || at == null) return null;
    return ProposalNotice(
      id: '${json['id']}',
      kind: kind,
      proposalId: '${json['proposal_id']}',
      at: at.toLocal(),
      revision: (json['revision'] as num?)?.toInt(),
      message: json['message'] as String?,
      eventIds: [for (final e in json['event_ids'] as List? ?? []) '$e'],
      eventNames: [for (final e in json['event_names'] as List? ?? []) '$e'],
    );
  }
}

/// The [ProposalNotice]s not yet dismissed, oldest first: kept on the
/// device, with [persist], so what the background task saved is said when
/// the app opens. Best effort.
class ProposalNotices extends ChangeNotifier {
  ProposalNotices({this.persist = true});

  final bool persist;
  var _notices = <ProposalNotice>[];
  Future<void> _lock = Future.value();

  static const _key = 'proposal_notices';

  /// At most these are kept: the oldest go first.
  static const limit = 20;

  List<ProposalNotice> get notices => List.unmodifiable(_notices);

  /// Reads what's kept -- the background task may have added some.
  Future<void> load() => _change((notices) => notices);

  /// Adds [notice], and keeps it.
  Future<void> add(ProposalNotice notice) => _change(
    (notices) =>
        [...notices, notice].reversed.take(limit).toList().reversed.toList(),
  );

  /// Dismisses [notice]: it's been seen.
  Future<void> dismiss(ProposalNotice notice) =>
      _change((notices) => [...notices.where((n) => n.id != notice.id)]);

  /// Each change read, made and written in turn, so the app's and the
  /// background task's don't clobber each other's.
  Future<void> _change(
    List<ProposalNotice> Function(List<ProposalNotice> notices) change,
  ) {
    final result = _lock.then((_) async {
      var notices = _notices;
      if (persist) notices = await _read() ?? notices;
      final changed = change(notices);
      if (persist && !identical(changed, notices)) await _write(changed);
      final was = _notices;
      _notices = changed;
      if (!listEquals(
        [for (final n in was) n.id],
        [for (final n in changed) n.id],
      )) {
        notifyListeners();
      }
    });
    _lock = result.catchError((_) {});
    return result;
  }

  Future<List<ProposalNotice>?> _read() async {
    try {
      final json = await SharedPreferencesAsync().getString(_key);
      if (json == null) return const [];
      return [
        for (final n in jsonDecode(json) as List) ?ProposalNotice.fromJson(n),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(List<ProposalNotice> notices) async {
    try {
      await SharedPreferencesAsync().setString(
        _key,
        jsonEncode([for (final n in notices) n.toJson()]),
      );
    } catch (_) {
      // Said while the app runs, then.
    }
  }
}
