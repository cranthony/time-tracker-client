import 'package:flutter/material.dart';

import '../models/assessment.dart';
import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/health.dart';
import '../widgets/status_message.dart';

/// One goal's health over its recent periods: a chart of its ratings (the
/// band edges marked, proposed ones hollow), and each assessment below it,
/// newest first, with how it was reached. Tapping a bar picks it out in
/// the list.
class GoalHistoryScreen extends StatefulWidget {
  const GoalHistoryScreen({
    super.key,
    required this.goal,
    required this.repository,
  });

  final Goal goal;
  final GoalsRepository repository;

  @override
  State<GoalHistoryScreen> createState() => _GoalHistoryScreenState();
}

class _GoalHistoryScreenState extends State<GoalHistoryScreen> {
  List<Assessment>? _history;
  Object? _error;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await widget.repository.history(widget.goal);
      if (!mounted) return;
      setState(() {
        _history = history;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(goalName(widget.goal))),
      body: RefreshIndicator(onRefresh: _load, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final history = _history;
    if (_error != null && history == null) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.cloud_off,
          text:
              "Couldn't load its history.\n${switch (_error) {
                SignInRequiredException() => 'Sign in again from the Goals page.',
                McpException(:final message) => message,
                final e => '$e',
              }}",
        ),
      );
    }
    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final goal = widget.goal;
    final cadence = goal.cadence;
    if (history.isEmpty) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.insights_outlined,
          text: cadence == null
              ? 'This goal has no cadence, so it isn\'t assessed.'
              : 'No assessments yet.\nRatings are confirmed in a '
                    '${cadences[cadence]?.toLowerCase() ?? cadence} reflection.',
        ),
      );
    }
    final newestFirst = history.reversed.toList();
    final selected = _selected;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            HealthDot(rating: goal.health),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (goal.health case final health?)
                    'Health ${healthBand(health)}'
                  else
                    'Not rated yet',
                  if (cadence != null) cadences[cadence] ?? cadence,
                  if (goal.healthPeriod case final period?)
                    'last rated $period',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        HealthHistoryChart(
          assessments: history,
          selected: selected,
          onSelected: (i) => setState(() => _selected = i),
        ),
        const SizedBox(height: 4),
        Text(
          'Oldest to newest; tap a bar to find it below. Hollow bars are '
          'proposed, not yet confirmed in a reflection.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final (i, a) in newestFirst.indexed)
          _AssessmentTile(
            assessment: a,
            highlighted: selected == history.length - 1 - i,
          ),
      ],
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment, required this.highlighted});

  final Assessment assessment;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = assessment;
    final rating = a.rating;
    final why = [a.explanation, a.rationale].nonNulls.join('\n');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: highlighted,
      leading: SizedBox(
        width: 48,
        child: rating == null
            ? Text('skipped', style: TextStyle(color: theme.hintColor))
            : HealthDot(rating: rating),
      ),
      title: Text(
        [a.period, if (!a.confirmed) 'proposed', ?a.method].join(' · '),
      ),
      subtitle: why.isEmpty ? null : Text(why),
    );
  }
}
