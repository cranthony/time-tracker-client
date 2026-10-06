import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../services/traits_repository.dart';
import '../widgets/health.dart';
import 'trait_breakdown.dart';

/// A trait on one page, to read: its definition and status, its score and
/// recent trend where people are scored (tapping it shows the people and
/// parts behind it), each of its parts -- a judgment's rubric, rating
/// scale and the facts it's judged from -- and who it applies to, with
/// those who have their own parts for it. The pencil ([onEdit]) edits
/// it, returning it as saved.
class TraitScreen extends StatefulWidget {
  const TraitScreen({
    super.key,
    required this.trait,
    this.repository,
    this.days = const [],
    this.people,
    this.actionNames = const {},
    this.onEdit,
  });

  final Trait trait;

  /// Where its scores come from, to show what's behind one.
  final TraitsRepository? repository;

  /// Its daily scores, oldest first; empty where people aren't scored.
  final List<TraitDay> days;

  /// Everyone, to say who it applies to; null if they aren't known.
  final PeopleList? people;

  /// Names the actions and groups a part counts, by id.
  final Map<String?, String> actionNames;
  final Future<Trait?> Function(Trait trait)? onEdit;

  @override
  State<TraitScreen> createState() => _TraitScreenState();
}

class _TraitScreenState extends State<TraitScreen> {
  late Trait _trait = widget.trait;

  Future<void> _edit() async {
    final saved = await widget.onEdit!(_trait);
    if (saved != null && mounted) setState(() => _trait = saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final days = widget.days;
    final people = widget.people?.withSelf
        .where((p) => p.active && p.traits.applies(_trait.id ?? ''))
        .toList();
    final own = [
      for (final p in people ?? const <Person>[])
        if (p.traits.parts.containsKey(_trait.id)) p,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_trait.name),
        actions: [
          if (widget.onEdit != null)
            IconButton(
              tooltip: 'Edit ${_trait.name}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_trait.definition case final definition?)
            Text(definition, style: theme.textTheme.bodyLarge),
          if (_trait.status != 'active')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${traitStatuses[_trait.status] ?? _trait.status}: not '
                'rated for now.',
                style: muted,
              ),
            ),
          for (final problem in _trait.problems)
            Text(problem, style: TextStyle(color: theme.colorScheme.error)),
          if (days.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Score'),
              subtitle: Text(days.last.day),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TrendSparkline(
                    trend: [
                      for (final day in days.skip(
                        days.length > 8 ? days.length - 8 : 0,
                      ))
                        day.score,
                    ],
                  ),
                  const SizedBox(width: 8),
                  HealthDot(rating: days.last.score),
                ],
              ),
              onTap: widget.repository == null
                  ? null
                  : () => showTraitHistory(
                      context,
                      trait: _trait,
                      days: days,
                      repository: widget.repository!,
                      personNames: {
                        for (final p in widget.people?.withSelf ?? <Person>[])
                          p.id: personName(p),
                      },
                    ),
            ),
          _heading(theme, 'Parts'),
          for (final part in _trait.parts) _PartCard(part, widget.actionNames),
          if (people != null) ...[
            _heading(theme, 'Applies to'),
            Text(
              people.isEmpty
                  ? 'No one, for now.'
                  : people.map((p) => personName(p)).join(', '),
            ),
            if (own.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'With parts of their own: '
                  '${own.map((p) => personName(p)).join(', ')}',
                  style: muted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(text, style: theme.textTheme.titleMedium),
  );
}

/// One of a trait's parts, to read: what kind it is, what it reads
/// (events with someone, or done for them), its weight if it isn't 1,
/// and for a judgment, its rubric, rating scale and facts.
class _PartCard extends StatelessWidget {
  const _PartCard(this.part, this.actionNames);

  final Part part;
  final Map<String?, String> actionNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final kind = partKinds[part['kind']];
    final weight = part['weight'];
    final judgment = part['kind'] == 'judgment';
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                kind?.label ?? '${part['kind']}',
                part['engagement_type'] == 'for' ? 'for them' : 'with them',
                if (weight != null && weight != 1) 'weight $weight',
              ].join(' · '),
              style: muted,
            ),
            const SizedBox(height: 4),
            Text(
              judgment
                  ? '${part['rubric'] ?? ''}'
                  : describePart(part, actionNames),
              style: theme.textTheme.titleSmall,
            ),
            if (judgment) ...[
              const SizedBox(height: 6),
              for (final rating in judgmentRatings(part))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${rating.score}',
                          style: small?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(child: Text(rating.label, style: small)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Judged from ${[for (final MapEntry(:key, :value) in judgmentFactsOf(part).entries) '${(judgmentFacts[key]?.label ?? key).toLowerCase()}${value == null ? '' : ' (last $value days)'}'].join(', ')}',
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
