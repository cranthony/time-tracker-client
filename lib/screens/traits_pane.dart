import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait_scores.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/health.dart';
import '../widgets/hotkeys.dart';
import '../widgets/plan_pane.dart';
import '../widgets/refreshing_bar.dart';
import 'person_pages.dart';
import 'traits_section.dart';

/// The Plan page's Traits pane -- how the user wants to be: Self at the
/// top, with their relationship health and its last 8 days, and a button
/// that opens their page ([PersonScreen]); under it every trait
/// ([TraitsSection]). It shows what [memory] has, while it loads afresh.
class TraitsPane extends StatefulWidget {
  const TraitsPane({
    super.key,
    required this.repository,
    required this.people,
    required this.memory,
    this.actionNames = const {},
    this.actions = const {},
    this.locationNames = const {},
  });

  final TraitsRepository repository;

  /// Where Self is loaded from, and saved to.
  final PeopleRepository people;
  final PlanMemory memory;

  /// Names actions by id, for Self's history.
  final Map<String?, String> actionNames;

  /// The actions and groups a trait's or Self's own parts can count, by
  /// id.
  final Map<String, String> actions;

  /// Names locations by id, for where Self's events were.
  final Map<String?, String> locationNames;

  @override
  State<TraitsPane> createState() => TraitsPaneState();
}

class TraitsPaneState extends State<TraitsPane> {
  final _traitsKey = GlobalKey<TraitsSectionState>();

  PersonPages get _pages => PersonPages(
    repository: widget.people,
    memory: widget.memory,
    traits: widget.repository,
    actionNames: widget.actionNames,
    actions: widget.actions,
    locationNames: widget.locationNames,
    onSaved: () => _loadSelf(again: true),
  );

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
    _loadSelf();
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  /// Shows what changed: the scores, as they're worked out again.
  void _changed() {
    if (mounted) setState(() {});
  }

  /// Loads Self, with everyone; best effort: Self is there regardless.
  Future<void> _loadSelf({bool again = false}) async {
    try {
      await widget.memory.loadPeople(widget.people, again: again);
    } catch (_) {
      // The People pane says why.
    }
    if (mounted) setState(() {});
  }

  /// Loads the traits afresh, Self, and the events around today they're
  /// scored from.
  Future<void> reload() => Future.wait([
    _loadSelf(again: true),
    ?_traitsKey.currentState?.reload(),
    ?widget.memory.eventStore?.warm().catchError((Object _) {}),
  ]);

  TraitScores? get _scores => widget.memory.scores;

  @override
  Widget build(BuildContext context) {
    // Asked for first: asking is what has them worked out again.
    widget.memory.scores;
    final pages = _pages;
    return PlanPane(
      // Health as it was, while it's worked out again.
      child: RefreshingBar(
        refreshing: widget.memory.rescoring,
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _selfHead(context, widget.memory.people?.self ?? defaultSelf),
              TraitsSection(
                key: _traitsKey,
                repository: widget.repository,
                memory: widget.memory,
                personNames: pages.personNames,
                actions: widget.actions,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Self, with their health and its trend, and the way to their page.
  Widget _selfHead(BuildContext context, Person self) {
    final theme = Theme.of(context);
    final health = _scores?.health(self.id);
    final trend = _scores?.healthTrend(self.id) ?? const <int?>[];
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Expanded(child: Text('Self', style: theme.textTheme.titleMedium)),
            if (trend.nonNulls.isNotEmpty) ...[
              TrendSparkline(trend: trend, scale: HealthScale.relationship),
              const SizedBox(width: 8),
            ],
            if (health != null)
              HealthDot(
                rating: health,
                scale: HealthScale.relationship,
                consistency: _scores?.consistency(self.id) ?? 0,
              ),
            NewHotkey(
              child: IconButton(
                tooltip: 'Your page',
                icon: const Icon(Icons.person_outline),
                onPressed: () => _pages.open(context, self),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
