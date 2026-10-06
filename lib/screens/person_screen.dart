import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/person.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/health.dart';
import 'trait_breakdown.dart';

/// A person -- Self included -- on one page: who they are (their context
/// and circles), which traits apply to them and their own parts for any,
/// and what matters to them. Once [memory] has scored everyone from the
/// events (see [PlanMemory.scores]), also their relationship health,
/// their traits' scores of the last day that's over (tapping one shows
/// the parts, events and Claude's judgments behind it), their history
/// (the actions done and locations of their events, with how often and
/// when), and a timeline of those events with what happened at each.
/// Always, the events the user cancelled that count against their
/// follow-through ([Person.cancelledEvents]).
/// [onEdit] edits them, returning them as saved.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.person,
    this.traits,
    this.memory,
    this.circles = const [],
    this.personNames = const {},
    this.actionNames = const {},
    this.locationNames = const {},
    this.onEdit,
  });

  final Person person;
  final TraitsRepository? traits;

  /// Where everyone's scores are worked out, from the events.
  final PlanMemory? memory;
  final List<Circle> circles;

  /// Names people by id, for who events were with and for.
  final Map<String?, String> personNames;

  /// Names actions by id, for what was done at their events.
  final Map<String?, String> actionNames;

  /// Names locations by id, for where their events were.
  final Map<String?, String> locationNames;
  final Future<Person?> Function()? onEdit;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Person _person = widget.person;

  /// Every trait, by id, to name those that apply to them.
  Map<String, Trait> _traitList = const {};

  /// Everyone's scores, if they're worked out yet.
  TraitScores? get _scores => widget.memory?.scores;
  bool get _scored => widget.memory != null;

  @override
  void initState() {
    super.initState();
    widget.memory?.addListener(_rescored);
    _loadTraitList();
  }

  @override
  void dispose() {
    widget.memory?.removeListener(_rescored);
    super.dispose();
  }

  /// Shows the scores again, as they're worked out again.
  void _rescored() {
    if (mounted) setState(() {});
  }

  /// The traits again, and the week either side of today's events.
  Future<void> _load() async {
    await Future.wait([
      _loadTraitList(),
      if (widget.memory?.eventStore case final store?)
        store.warm().catchError((Object _) {}),
    ]);
  }

  Future<void> _loadTraitList() async {
    try {
      final traits = await widget.traits?.traits(
        statuses: [...traitStatuses.keys],
      );
      if (!mounted || traits == null) return;
      setState(
        () => _traitList = {
          for (final t in traits)
            if (t.id != null) t.id!: t,
        },
      );
    } catch (_) {
      // Named by id, then.
    }
  }

  Future<void> _edit() async {
    final saved = await widget.onEdit!();
    if (saved == null || !mounted) return;
    setState(() => _person = saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circles = [
      for (final c in widget.circles)
        if (_person.circleIds.contains(c.id)) c,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(personName(_person)),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              tooltip: 'Edit ${personName(_person)}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (_scored)
              ListTile(
                title: const Text('Relationship health'),
                subtitle: Text(switch (_scores?.health(_person.id)) {
                  final h? => relationshipBand(h),
                  null => 'Not rated yet',
                }),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_scores?.healthTrend(_person.id) case final trend?
                        when trend.nonNulls.isNotEmpty) ...[
                      TrendSparkline(
                        trend: trend,
                        scale: HealthScale.relationship,
                      ),
                      const SizedBox(width: 8),
                    ],
                    HealthDot(
                      rating: _scores?.health(_person.id),
                      scale: HealthScale.relationship,
                    ),
                  ],
                ),
              ),
            if (_person.context case final context?)
              ListTile(
                dense: true,
                title: const Text('Context'),
                subtitle: Text(context),
              ),
            if (circles.isNotEmpty)
              ListTile(
                dense: true,
                title: const Text('Circles'),
                subtitle: Text(circles.map((c) => c.name).join(', ')),
              ),
            _heading(theme, 'Traits'),
            ..._applies(theme),
            if (_scored) ..._traits(context),
            _heading(
              theme,
              _person.isSelf ? 'What matters to you' : 'What matters to them',
            ),
            _padded(switch (_person.whatMatters) {
              final text? when text.trim().isNotEmpty => Text(text),
              _ => Text(
                'Nothing yet. Compaction adds to it as notes reveal things.',
                style: TextStyle(color: theme.hintColor),
              ),
            }),
            if (_scored) ...[
              _heading(theme, 'History'),
              ..._history(theme),
              _heading(theme, 'Events'),
              ..._timeline(theme),
            ],
            _heading(theme, 'Cancelled'),
            ..._cancelled(theme),
          ],
        ),
      ),
    );
  }

  /// Which traits apply to them, and their own parts for any.
  List<Widget> _applies(ThemeData theme) {
    final traits = _person.traits;
    String name(String id) => _traitList[id]?.name ?? id;
    return [
      _padded(
        Text(switch (traits.select) {
          null => 'Every active trait',
          final ids when ids.isEmpty => 'None',
          final ids => ids.map(name).join(', '),
        }, style: theme.textTheme.bodyMedium),
      ),
      for (final MapEntry(:key, :value) in traits.parts.entries)
        ListTile(
          dense: true,
          title: Text('${name(key)}, their own'),
          subtitle: Text(
            [
              for (final part in value)
                describePart(part, {
                  for (final MapEntry(:key, :value)
                      in widget.actionNames.entries)
                    key: value,
                }),
            ].join('\n'),
          ),
        ),
    ];
  }

  List<Widget> _traits(BuildContext context) {
    final theme = Theme.of(context);
    final scores = _scores;
    if (scores == null) return [_padded(const LinearProgressIndicator())];
    final rating = scores.rating(_person.id);
    if (rating == null || rating.traits.isEmpty) {
      return [
        _padded(
          Text(
            'Not rated: no active trait applies to them.',
            style: TextStyle(color: theme.hintColor),
          ),
        ),
      ];
    }
    return [
      _padded(
        Text(
          '${rating.rating ?? 'Skipped'}'
          '${rating.day == null ? '' : ' · ${rating.day}'}',
          style: theme.textTheme.headlineSmall,
        ),
      ),
      for (final score in rating.traits)
        ListTile(
          title: Text(
            score.weight == 1 ? score.name : '${score.name} ×${score.weight}',
          ),
          subtitle: Text(
            [
              for (final part in score.parts)
                '${_partLabel(part)} ${part.score ?? '–'}',
            ].join(' · '),
          ),
          trailing: Text(
            score.score == null ? '–' : '${score.score}',
            style: theme.textTheme.titleMedium,
          ),
          onTap: () => showTraitParts(
            context,
            score,
            labels: [for (final part in score.parts) _partLabel(part)],
            title: rating.day,
            events: scores.eventsBehind(score),
            personNames: widget.personNames,
            locationNames: widget.locationNames,
          ),
        ),
      if (rating.leftOut.isNotEmpty)
        _padded(
          Text(
            'Not rated: ${rating.leftOut.join(', ')} (off, archived, or not '
            'theirs).',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  /// A part's name: a judgment's rubric, else its kind's.
  static String _partLabel(PartScore part) =>
      part.rubric ?? partKinds[part.kind]?.label ?? part.key;

  List<Widget> _history(ThemeData theme) {
    final digest = _scores?.digest(_person.id);
    if (digest == null) return [_padded(const LinearProgressIndicator())];
    String entries(List<DigestEntry> list) => list.isEmpty
        ? 'None recorded'
        : [
            for (final e in list)
              '${widget.actionNames[e.label] ?? widget.locationNames[e.label] ?? e.label} ×${e.count} '
                  '(${e.first == e.last ? e.first : '${e.first} – ${e.last}'})',
          ].join('\n');
    return [
      _padded(
        Text(
          '${digest.eventsCounted} events in the last ${digest.windowDays} '
          'days.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      ListTile(
        dense: true,
        title: const Text('Actions'),
        subtitle: Text(entries(digest.actions)),
      ),
      ListTile(
        dense: true,
        title: const Text('Locations'),
        subtitle: Text(entries(digest.locations)),
      ),
    ];
  }

  List<Widget> _timeline(ThemeData theme) {
    final digest = _scores?.digest(_person.id);
    if (digest == null) return [_padded(const LinearProgressIndicator())];
    if (digest.events.isEmpty) {
      return [_padded(const Text('No events in this window.'))];
    }
    return [
      for (final event in digest.events.reversed)
        ListTile(
          dense: true,
          title: Text('${event['summary'] ?? '(no title)'}'),
          subtitle: Text(
            [
              _when(event),
              if ((event['action_ids'] as List?)?.isNotEmpty ?? false)
                [
                  for (final id in event['action_ids'] as List)
                    widget.actionNames['$id'] ?? '$id',
                ].join(', '),
              if (Facts.fromJson(event['facts']) case final facts?
                  when !facts.isEmpty) ...[
                facts.describe(widget.personNames, widget.locationNames),
                if (facts.notes[_person.id] case final note?) '“$note”',
              ],
            ].where((line) => line.isNotEmpty).join('\n'),
          ),
        ),
    ];
  }

  /// The events the user cancelled that count against their
  /// follow-through, newest first: when each was planned, what was to be
  /// done, whether they were to be there or it was for them, and when
  /// and how it was cancelled, with the traits it counted against.
  List<Widget> _cancelled(ThemeData theme) {
    final cancelled = _person.cancelledEvents;
    if (cancelled.isEmpty) {
      return [
        _padded(
          Text(
            'Nothing cancelled that counts against '
            '${_person.isSelf ? 'your' : 'their'} follow-through.',
            style: TextStyle(color: theme.hintColor),
          ),
        ),
      ];
    }
    final localizations = MaterialLocalizations.of(context);
    String at(DateTime t) =>
        '${localizations.formatMediumDate(t)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
    return [
      for (final c in cancelled)
        ListTile(
          dense: true,
          leading: Icon(Icons.event_busy, color: theme.colorScheme.error),
          title: Text(c.summary ?? '(no title)'),
          subtitle: Text(
            [
              [
                'Planned for ${at(c.start)}',
                if (c.engagement == 'for')
                  'for ${_person.isSelf ? 'you' : 'them'}'
                else if (!_person.isSelf)
                  'with them',
              ].join(', '),
              if (c.actionIds.isNotEmpty)
                [for (final id in c.actionIds) widget.actionNames[id] ?? id]
                    .join(', '),
              [
                switch (c.cancelledAt) {
                  final day? =>
                    'Cancelled ${localizations.formatMediumDate(day)}',
                  null => 'Cancelled',
                },
                if (c.byCompaction)
                  "— it didn't happen"
                else if (c.source == 'delete_event')
                  '— deleted',
              ].join(' '),
              if (c.traitIds.isNotEmpty)
                'Counts against '
                    '${c.traitIds.map((id) => _traitList[id]?.name ?? id).join(', ')}',
            ].join('\n'),
          ),
        ),
    ];
  }

  String _when(Map<String, dynamic> event) {
    final start = DateTime.tryParse('${event['start']}')?.toLocal();
    if (start == null) return '';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(start)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Text(text, style: theme.textTheme.titleMedium),
  );

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
}
