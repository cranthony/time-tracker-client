import '../models/named.dart';

import 'package:flutter/material.dart';

import '../models/people_times.dart';
import '../models/person.dart';
import '../models/scoring.dart';
import '../models/trait_scores.dart';
import '../services/plan_memory.dart';
import '../widgets/health.dart';
import '../widgets/person_tile.dart';
import '../widgets/relationship_habits.dart';
import 'person_screen.dart';
import 'subject_sections.dart';

/// A circle on one page, as a person's is: its relationship health -- its
/// people's, combined as it says -- and its trend, its note, and with
/// [times], the time with any of its people in the summary's 24 hours and
/// 7 days and the last (or next) event with any of them. Then its habits,
/// the open goals done with or for any of its people, and its people,
/// each with their health, opening their page with [onOpenPerson]. It's
/// shown as [memory] has it, as it changes; [onEdit] edits it, and once
/// it's deleted, the page closes.
class CircleScreen extends StatefulWidget {
  const CircleScreen({
    super.key,
    required this.circle,
    required this.memory,
    this.times,
    this.durations = true,
    this.onOpenPerson,
    this.onEdit,
  });

  final Circle circle;
  final PlanMemory memory;
  final PeopleTimes? times;
  final bool durations;
  final void Function(Person person)? onOpenPerson;
  final Future<void> Function(Circle circle)? onEdit;

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> with Rescored {
  @override
  PlanMemory get memory => widget.memory;

  /// It, as the app has it now; null once it's deleted.
  Circle? get _circle {
    final people = memory.people;
    if (people == null) return widget.circle;
    return people.circles.where((c) => c.id == widget.circle.id).firstOrNull;
  }

  TraitScores? get _scores => memory.scores;

  Future<void> _edit(Circle circle) async {
    await widget.onEdit!(circle);
    if (!mounted) return;
    if (_circle == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circle = _circle ?? widget.circle;
    final members = memory.people?.inCircle(circle.id) ?? const <Person>[];
    final ids = [for (final p in members) p.id];
    final names = memory.people?.names ?? const <String, String>{};
    final health = _scores?.groupHealth(ids, scoring: circle.scoring);
    final trend = _scores?.groupTrend(ids, scoring: circle.scoring);
    final times = widget.times;
    final time = times == null
        ? null
        : [
            ?timeLine(
              times.window,
              times.circleDay(circle.id),
              times.circleWeek(circle.id),
              durations: widget.durations,
            ),
            nearestLine(context, times.window, times.circleNearest(circle.id)),
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(circleName(circle)),
        actions: [
          if (widget.onEdit != null)
            editButton(circleName(circle), () => _edit(circle)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: const Text('Relationship health'),
            subtitle: Text(
              [
                switch (health) {
                  final h? => HealthScale.relationship.band(h),
                  null => 'Not rated yet',
                },
                'Its people combined: '
                    '${(circle.scoring ?? memory.scoringDefaults.circles ?? Aggregation.mean).describe()}',
              ].join('\n'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trend case final trend? when trend.nonNulls.isNotEmpty) ...[
                  TrendSparkline(trend: trend, scale: HealthScale.relationship),
                  const SizedBox(width: 8),
                ],
                HealthDot(rating: health, scale: HealthScale.relationship),
              ],
            ),
          ),
          if (circle.note case final note?)
            ListTile(
              dense: true,
              title: const Text('Note'),
              subtitle: Text(note),
            ),
          if (time != null)
            ListTile(
              dense: true,
              title: const Text('Time together'),
              subtitle: Text(time.join('\n')),
            ),
          sectionHeading(theme, 'Habits'),
          sectionPadded(RelationshipHabits(memory: memory, circle: circle)),
          ...openGoalTiles(
            context,
            memory,
            {circle.id, ...ids},
            who: (goal, isFor) =>
                '${isFor ? 'For' : 'With'} '
                '${namedList(isFor ? goal.forWhom : goal.withWhom, (id) => names[id] ?? id)}',
          ),
          sectionHeading(
            theme,
            '${members.length} ${members.length == 1 ? 'person' : 'people'}',
          ),
          if (members.isEmpty)
            sectionPadded(
              Text(
                'No one in this circle yet.',
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          for (final person in members)
            PersonTile(
              person: person,
              health: _scores?.health(person.id),
              trend: _scores?.healthTrend(person.id) ?? const [],
              consistency: _scores?.consistency(person.id) ?? 0,
              times: times,
              durations: widget.durations,
              onTap: switch (widget.onOpenPerson) {
                final open? => () => open(person),
                null => null,
              },
            ),
        ],
      ),
    );
  }
}
