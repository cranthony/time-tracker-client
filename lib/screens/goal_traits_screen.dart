import 'package:flutter/material.dart';

import '../models/facets.dart';
import '../models/goal.dart';
import '../models/measure.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/traits_repository.dart';
import 'trait_breakdown.dart';

/// A goal rated by traits -- usually a person -- on one page: its traits'
/// scores of the last day that's over (tapping one shows the parts and
/// events behind it), how it's rated (its traits, their weights, and its
/// own parts, such as its cadences -- edited with [onEditMeasure]), what
/// matters to them (from its description, edited here), its history
/// digest (activities and places, with how often and when), and a
/// timeline of its events with what happened at each.
class GoalTraitsScreen extends StatefulWidget {
  const GoalTraitsScreen({
    super.key,
    required this.goal,
    required this.repository,
    this.goalNames = const {},
    this.onEditMeasure,
  });

  final Goal goal;

  /// Edits the goal's measure, returning the goal as saved, or null if
  /// nothing was; without it, the measure can't be edited here.
  final Future<Goal?> Function(Goal goal)? onEditMeasure;
  final TraitsRepository repository;

  /// Names goals by id, for who events were with and for.
  final Map<String?, String> goalNames;

  @override
  State<GoalTraitsScreen> createState() => _GoalTraitsScreenState();
}

class _GoalTraitsScreenState extends State<GoalTraitsScreen> {
  TraitsRating? _rating;
  Object? _ratingError;
  GoalDigest? _digest;
  Object? _digestError;

  late Goal _goal = widget.goal;

  String get _goalId => widget.goal.id!;

  Future<void> _editMeasure() async {
    final saved = await widget.onEditMeasure!(_goal);
    if (saved == null || !mounted) return;
    setState(() => _goal = saved);
    await _loadRating();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadRating(), _loadDigest()]);
  }

  Future<void> _loadRating() async {
    try {
      final rating = await widget.repository.explainTraits(_goalId);
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
    try {
      final digest = await widget.repository.goalDigest(_goalId);
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _digestError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _digestError = e);
    }
  }

  Map<String, Map<String, dynamic>> get _eventsById => {
    for (final event in _digest?.events ?? const <Map<String, dynamic>>[])
      '${event['id']}': event,
  };

  Future<void> _editWhatMatters() async {
    final messenger = ScaffoldMessenger.of(context);
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _WhatMattersDialog(text: _digest?.whatMatters ?? ''),
    );
    if (edited == null) return;
    try {
      // The rest of the description is kept as it is.
      final description = await widget.repository.description(_goalId);
      await widget.repository.setDescription(
        _goalId,
        withWhatMatters(description, edited),
      );
      await _loadDigest();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e) {
            McpException(:final message) => "Couldn't save. $message",
            _ => "Couldn't save. $e",
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(goalName(widget.goal))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _heading(theme, 'Traits'),
            ..._traits(context),
            _heading(
              theme,
              "How it's rated",
              action: widget.onEditMeasure == null
                  ? null
                  : IconButton(
                      tooltip: 'Edit how it is rated',
                      icon: const Icon(Icons.tune),
                      onPressed: _editMeasure,
                    ),
            ),
            for (final (label, value) in describeMeasureSettings(
              _goal.measure ?? const {},
              goalNames: widget.goalNames,
            ))
              ListTile(dense: true, title: Text(label), subtitle: Text(value)),
            _heading(
              theme,
              whatMattersHeading,
              action: IconButton(
                tooltip: 'Edit what matters to them',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _digest == null ? null : _editWhatMatters,
              ),
            ),
            _padded(switch (_digest) {
              GoalDigest(whatMatters: final text?)
                  when text.trim().isNotEmpty =>
                Text(text),
              GoalDigest() => Text(
                'Nothing yet. Compaction and reflections add to it as notes '
                'reveal things.',
                style: TextStyle(color: theme.hintColor),
              ),
              null => _loading(_digestError),
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
    final rating = _rating;
    if (rating == null) return [_padded(_loading(_ratingError))];
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
          title: Text(score.name),
          subtitle: Text(
            [
              for (final part in score.parts)
                '${partKinds[part.kind]?.label ?? part.key} '
                    '${part.score ?? '–'}',
            ].join(' · '),
          ),
          trailing: Text(
            score.score == null ? '–' : '${score.score}',
            style: theme.textTheme.titleMedium,
          ),
          onTap: () => showTraitParts(
            context,
            score,
            title: rating.day,
            events: _eventsById,
            goalNames: widget.goalNames,
          ),
        ),
      if (rating.leftOut.isNotEmpty)
        _padded(
          Text(
            'Not rated: ${rating.leftOut.map(traitLabel).join(', ')} '
            "(off, archived, or not a trait).",
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  List<Widget> _history(ThemeData theme) {
    final digest = _digest;
    if (digest == null) return [_padded(_loading(_digestError))];
    String entries(List<DigestEntry> list) => list.isEmpty
        ? 'None recorded'
        : [
            for (final e in list)
              '${e.label} ×${e.count} (${e.first == e.last ? e.first : '${e.first} – ${e.last}'})',
          ].join('\n');
    return [
      _padded(
        Text(
          '${digest.eventsCounted} events in the last ${digest.windowDays} '
          'days, ${digest.withFacets} with what happened recorded.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      ListTile(
        dense: true,
        title: const Text('Activities'),
        subtitle: Text(entries(digest.activities)),
      ),
      ListTile(
        dense: true,
        title: const Text('Places'),
        subtitle: Text(entries(digest.places)),
      ),
    ];
  }

  List<Widget> _timeline(ThemeData theme) {
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
              if (Facets.fromJson(event['facets']) case final facets?
                  when !facets.isEmpty) ...[
                facets.describe(widget.goalNames),
                if (facets.why case final why?) '“$why”',
              ],
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

  Widget _heading(ThemeData theme, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Row(
      children: [
        Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
        ?action,
      ],
    ),
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

/// Edits a goal's "What matters to them" section's text; returns it, or
/// null if it was called off.
class _WhatMattersDialog extends StatefulWidget {
  const _WhatMattersDialog({required this.text});

  final String text;

  @override
  State<_WhatMattersDialog> createState() => _WhatMattersDialogState();
}

class _WhatMattersDialogState extends State<_WhatMattersDialog> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(whatMattersHeading),
    content: SizedBox(
      width: 460,
      child: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 6,
        maxLines: 16,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '- 2026-10-05: starts a new job in November',
          helperText:
              'One dated line each: facts, moments coming up, preferences.',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
