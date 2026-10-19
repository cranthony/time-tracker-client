import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/plan_memory.dart';
import '../widgets/health.dart';
import '../widgets/hotkeys.dart';
import 'event_list_screen.dart';
import 'person_screen.dart';

/// A heading over one of a page's sections.
Widget sectionHeading(ThemeData theme, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
  child: Text(text, style: theme.textTheme.titleMedium),
);

/// [child], inset as a section's text is.
Widget sectionPadded(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  child: child,
);

/// The app bar's pencil, editing [name]: E presses it.
Widget editButton(String name, VoidCallback onPressed) => EditHotkey(
  child: IconButton(
    tooltip: 'Edit $name',
    icon: const Icon(Icons.edit_outlined),
    onPressed: onPressed,
  ),
);

/// A page's state that shows the scores again as [memory] works them
/// out again, calling [onRescored] first.
mixin Rescored<T extends StatefulWidget> on State<T> {
  /// Where the scores are worked out, from the events.
  PlanMemory? get memory;

  /// What changes, besides the scores, as they're worked out again.
  void onRescored() {}

  @override
  void initState() {
    super.initState();
    memory?.addListener(_rescored);
  }

  @override
  void dispose() {
    memory?.removeListener(_rescored);
    super.dispose();
  }

  void _rescored() {
    if (mounted) setState(onRescored);
  }
}

/// The sections a person's page and a habit's share, for [subjectId]:
/// its health, its traits and their scores, its events and the events
/// cancelled that count against it, each in brief with a button opening
/// the lot on a page of its own titled with [name]. The scores, health
/// and events are only shown if [scored]. [whom], [whose] and [withWhom]
/// word who it is ("them", "their", "with them"; "it", "its"); [own]
/// its own parts of a trait; [why] why a trait isn't rated for it.
class SubjectSections {
  const SubjectSections(
    this.context, {
    required this.memory,
    required this.scored,
    required this.subjectId,
    required this.name,
    required this.healthTitle,
    required this.scale,
    required this.traits,
    required this.cancelled,
    required this.traitList,
    required this.whom,
    required this.whose,
    this.withWhom,
    this.own = 'their own',
    required this.why,
    this.trends = false,
    this.noteOf,
    this.person,
    this.factLogs,
    this.actionNames = const {},
    this.personNames = const {},
    this.locationNames = const {},
    this.loadAllEvents,
  });

  final BuildContext context;
  final PlanMemory? memory;
  final bool scored;
  final String subjectId;
  final String name;
  final String healthTitle;
  final HealthScale scale;
  final PersonTraits traits;
  final List<CancelledEvent> cancelled;
  final Map<String, Trait> traitList;
  final String whom;
  final String whose;
  final String? withWhom;
  final String own;
  final String why;

  /// Whether each trait's score shows its trend.
  final bool trends;

  /// Whose notes on its events are shown.
  final String? noteOf;

  /// The person it is, if it's a person: each trait's score shows what it
  /// keeps about them, and [factLogs] (by trait id) what changed in it.
  final Person? person;
  final Future<List<FactLog>> Function(String traitId)? factLogs;
  final Map<String?, String> actionNames;
  final Map<String?, String> personNames;
  final Map<String?, String> locationNames;

  /// Asks for all its events, not just those scored, for "Load all" on
  /// the page of them; returns what builds their tiles.
  final Future<List<Widget> Function(BuildContext)> Function()? loadAllEvents;

  /// Everyone's scores, its among them, if they're worked out yet.
  TraitScores? get _scores => memory?.scores;

  ThemeData get _theme => Theme.of(context);

  /// Its health -- its band, its last days and its latest rating.
  List<Widget> health() => [
    if (scored)
      ListTile(
        title: Text(healthTitle),
        subtitle: Text(switch (_scores?.health(subjectId)) {
          final h? => scale.band(h),
          null => 'Not rated yet',
        }),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scores?.healthTrend(subjectId) case final trend?
                when trend.nonNulls.isNotEmpty) ...[
              TrendSparkline(trend: trend, scale: scale),
              const SizedBox(width: 8),
            ],
            HealthDot(
              rating: _scores?.health(subjectId),
              scale: scale,
              consistency: _scores?.consistency(subjectId) ?? 0,
            ),
          ],
        ),
      ),
  ];

  /// Which traits apply to it, and its own parts for any, then their
  /// scores.
  List<Widget> traitSection() => [
    sectionHeading(_theme, 'Traits'),
    ...traitsApplied(
      _theme,
      traits,
      traitList: traitList,
      actionNames: actionNames,
      defaults: PlanMemoryScope.of(context)?.scoringDefaults.traits,
      own: own,
    ),
    // What J and K go down and up: each trait's score, tapped for how
    // it was reached.
    if (scored)
      HotkeyItems(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: traitScoreTiles(
            context,
            _scores,
            subjectId,
            whom: whom,
            why: why,
            trends: trends,
            scale: scale,
            personNames: personNames,
            locationNames: locationNames,
            person: person,
            traitList: traitList,
            factLogs: factLogs,
          ),
        ),
      ),
  ];

  /// Its events in brief -- how many, their time, the most recent and the
  /// oldest -- with "All events" opening the lot on a page of its own,
  /// where [loadAllEvents], if given, can load all of them.
  List<Widget> events() => [
    if (scored) ...[
      sectionHeading(_theme, 'Events'),
      ...eventsSummary(
        context,
        _scores?.digest(subjectId),
        noteOf: noteOf,
        actionNames: actionNames,
        personNames: personNames,
        locationNames: locationNames,
        onAll: () => _openList(
          'Events',
          (context) => eventTiles(
            context,
            _scores?.digest(subjectId),
            noteOf: noteOf,
            actionNames: actionNames,
            personNames: personNames,
            locationNames: locationNames,
          ),
          loadAll: loadAllEvents,
        ),
      ),
    ],
  ];

  /// The events cancelled that count against its follow-through, in
  /// brief as its events are, with "All cancelled events" opening the lot.
  List<Widget> cancelledSection() => [
    sectionHeading(_theme, 'Cancelled'),
    ...cancelledSummary(
      context,
      cancelled,
      whose: whose,
      whom: whom,
      withWhom: withWhom,
      traitList: traitList,
      actionNames: actionNames,
      onAll: () => _openList(
        'Cancelled',
        (context) => cancelledTiles(
          context,
          cancelled,
          whose: whose,
          whom: whom,
          withWhom: withWhom,
          traitList: traitList,
          actionNames: actionNames,
        ),
      ),
    ),
  ];

  /// A page of [title] listing what [tiles] builds, built again as
  /// they're scored again; with [loadAll], its "Load all" button.
  void _openList(
    String title,
    List<Widget> Function(BuildContext) tiles, {
    Future<List<Widget> Function(BuildContext)> Function()? loadAll,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventListScreen(
        title: '$title · $name',
        listenable: memory,
        tiles: tiles,
        loadAll: loadAll,
      ),
    ),
  );
}
