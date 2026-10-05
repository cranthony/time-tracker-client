import 'package:flutter/material.dart';

import '../models/facets.dart';
import '../models/person.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/traits_repository.dart';
import '../widgets/health.dart';
import 'trait_breakdown.dart';

/// A person -- Self included -- on one page: their relationship health,
/// the circles they're in, their traits' scores of the last day that's
/// over (tapping one shows the parts, events and Claude's judgments behind
/// it), how much each trait counts for them, what matters to them, their
/// history (the actions done and locations of their events, with how
/// often and when), and a timeline of those events with what happened at
/// each. [onEdit] edits them, returning them as saved.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.person,
    this.traits,
    this.circles = const [],
    this.personNames = const {},
    this.actionNames = const {},
    this.onEdit,
  });

  final Person person;
  final TraitsRepository? traits;
  final List<Circle> circles;

  /// Names people by id, for who events were with and for.
  final Map<String?, String> personNames;

  /// Names actions by id, for what was done at their events.
  final Map<String?, String> actionNames;
  final Future<Person?> Function()? onEdit;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  TraitsRating? _rating;
  Object? _ratingError;
  PersonDigest? _digest;
  Object? _digestError;

  late Person _person = widget.person;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadRating(), _loadDigest()]);
  }

  Future<void> _loadRating() async {
    final traits = widget.traits;
    if (traits == null) return;
    try {
      final rating = await traits.explainTraits(_person.id);
      if (!mounted) return;
      setState(() {
        _rating = rating;
        _ratingError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _ratingError = e);
    }
  }

  Future<void> _loadDigest() async {
    final traits = widget.traits;
    if (traits == null) return;
    try {
      final digest = await traits.personDigest(_person.id);
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _digestError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _digestError = e);
    }
  }

  Future<void> _edit() async {
    final saved = await widget.onEdit!();
    if (saved == null || !mounted) return;
    setState(() => _person = saved);
    await _loadRating();
  }

  Map<String, Map<String, dynamic>> get _eventsById => {
    for (final event in _digest?.events ?? const <Map<String, dynamic>>[])
      '${event['id']}': event,
  };

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
            ListTile(
              title: const Text('Relationship health'),
              subtitle: Text(switch (_person.health) {
                final h? => relationshipBand(h),
                null => 'Not rated yet',
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_person.healthTrend.isNotEmpty) ...[
                    TrendSparkline(
                      trend: _person.healthTrend,
                      scale: HealthScale.relationship,
                    ),
                    const SizedBox(width: 8),
                  ],
                  HealthDot(
                    rating: _person.health,
                    scale: HealthScale.relationship,
                  ),
                ],
              ),
            ),
            if (circles.isNotEmpty)
              ListTile(
                dense: true,
                title: const Text('Circles'),
                subtitle: Text(circles.map((c) => c.name).join(', ')),
              ),
            _heading(theme, 'Traits'),
            ..._traits(context),
            _heading(
              theme,
              _person.isSelf ? 'Notes on you' : 'What matters to them',
            ),
            _padded(switch (_person.notes) {
              final text? when text.trim().isNotEmpty => Text(text),
              _ => Text(
                'Nothing yet. Compaction adds to it as notes reveal things.',
                style: TextStyle(color: theme.hintColor),
              ),
            }),
            _heading(theme, 'History'),
            ..._history(theme),
            _heading(theme, 'Events'),
            ..._timeline(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _traits(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.traits == null) {
      return [_padded(const Text('Traits aren\'t available here.'))];
    }
    final rating = _rating;
    if (rating == null) return [_padded(_loading(_ratingError))];
    if (rating.traits.isEmpty) {
      return [
        _padded(
          Text(
            'Not rated yet: the reflection rates them by every active trait.',
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
            events: _eventsById,
            personNames: widget.personNames,
          ),
        ),
      if (rating.leftOut.isNotEmpty)
        _padded(
          Text(
            'Not rated: ${rating.leftOut.join(', ')} (off, archived, or '
            'weighed 0).',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  /// A part's name: a facet's rubric, else its kind's.
  static String _partLabel(PartScore part) =>
      part.rubric ?? partKinds[part.kind]?.label ?? part.key;

  List<Widget> _history(ThemeData theme) {
    if (widget.traits == null) return const [];
    final digest = _digest;
    if (digest == null) return [_padded(_loading(_digestError))];
    String entries(List<DigestEntry> list) => list.isEmpty
        ? 'None recorded'
        : [
            for (final e in list)
              '${widget.actionNames[e.label] ?? e.label} ×${e.count} '
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
    if (widget.traits == null) return const [];
    final digest = _digest;
    if (digest == null) return [_padded(_loading(_digestError))];
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
              if ((event['goal_ids'] as List?)?.isNotEmpty ?? false)
                [
                  for (final id in event['goal_ids'] as List)
                    widget.actionNames['$id'] ?? '$id',
                ].join(', '),
              if (Facets.fromJson(event['facets']) case final facets?
                  when !facets.isEmpty) ...[
                facets.describe(widget.personNames),
                if (facets.personNotes[_person.id] case final note?) '“$note”',
              ],
            ].where((line) => line.isNotEmpty).join('\n'),
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

  Widget _loading(Object? error) => error == null
      ? const LinearProgressIndicator()
      : Text(switch (error) {
          McpException(:final message) => message,
          _ => '$error',
        });
}
