import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/people_repository.dart';
import '../services/traits_repository.dart';
import '../widgets/color_picker.dart' show contrastingColor;
import '../widgets/health.dart';
import '../widgets/person_dialog.dart';
import '../widgets/plan_section.dart';
import 'person_screen.dart';

/// The Plan page's People section -- who the user wants to be with: Self,
/// always first, then everyone else, each with the circles they're in
/// and their relationship health, gray (disconnected) to green (healthy),
/// with its last 8 days. Above them, the circles, each with its own
/// health: tapping one shows only the people in it, and "Edit" beside it
/// edits it. Tapping a person opens their page ([PersonScreen]); their
/// menu edits or archives them. "+" adds a person or a circle. Archived
/// people are shown only when asked for. [onPeople] is told who's there
/// each time they load.
class PeopleSection extends StatefulWidget {
  const PeopleSection({
    super.key,
    required this.repository,
    required this.expanded,
    required this.onExpanded,
    this.traits,
    this.onPeople,
    this.actionNames = const {},
    this.actions = const {},
    this.locationNames = const {},
  });

  final PeopleRepository repository;

  /// For each person's traits, and those their dialog offers.
  final TraitsRepository? traits;
  final bool expanded;
  final ValueChanged<bool> onExpanded;
  final ValueChanged<PeopleList>? onPeople;

  /// Names actions by id, for a person's history.
  final Map<String?, String> actionNames;

  /// The actions and groups a person's own parts can count, by id.
  final Map<String, String> actions;

  /// Names locations by id, for where a person's events were.
  final Map<String?, String> locationNames;

  @override
  State<PeopleSection> createState() => PeopleSectionState();
}

class PeopleSectionState extends State<PeopleSection> {
  PeopleList? _people;
  Object? _error;
  bool _archived = false;

  /// The circle whose people alone are shown, if one's picked.
  String? _circle;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Loads everyone afresh.
  Future<void> reload() async {
    try {
      final people = await widget.repository.people();
      if (!mounted) return;
      setState(() {
        _people = people;
        _error = null;
        if (!people.circles.any((c) => c.id == _circle)) _circle = null;
      });
      widget.onPeople?.call(people);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The traits that could apply to someone: active, and off.
  Future<List<Trait>> _traits() async {
    try {
      return await widget.traits?.traits() ?? const [];
    } catch (_) {
      return const []; // Which apply can wait.
    }
  }

  Future<void> _editPerson(Person? person) async {
    final traits = await _traits();
    if (!mounted) return;
    final repository = widget.repository;
    final saved = await showPersonDialog(
      context,
      person: person,
      circles: _people?.circles ?? const [],
      traits: traits,
      actions: widget.actions,
      save: (fields) => person == null
          ? repository.createPerson(Person.fromJson({'id': '', ...fields}))
          : repository.updatePerson(person.id, fields),
    );
    if (saved != null) await reload();
  }

  Future<void> _editCircle(Circle? circle) async {
    final repository = widget.repository;
    final saved = await showCircleDialog(
      context,
      circle: circle,
      save: (fields) async => circle == null
          ? await repository.createCircle(
              Circle(
                id: '',
                name: fields['name'] as String,
                note: fields['note'] as String?,
              ),
            )
          : await repository.updateCircle(circle.id, fields),
      delete: circle == null ? null : () => repository.deleteCircle(circle.id),
    );
    if (saved) await reload();
  }

  Future<void> _setStatus(Person person, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updatePerson(person.id, {'status': status});
      await reload();
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

  void _open(Person person) {
    final people = _people;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(
          person: person,
          traits: widget.traits,
          circles: people?.circles ?? const [],
          personNames: {
            for (final p in people?.withSelf ?? const <Person>[])
              p.id: personName(p),
          },
          actionNames: widget.actionNames,
          locationNames: widget.locationNames,
          onEdit: () async {
            await _editPerson(person);
            return _people?.withSelf
                .where((p) => p.id == person.id)
                .firstOrNull;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return PlanSection(
      title: 'People',
      annotation: 'who',
      expanded: widget.expanded,
      onExpanded: widget.onExpanded,
      actions: [
        IconButton(
          tooltip: _archived ? 'Hide archived people' : 'Show archived people',
          icon: Icon(
            _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
          ),
          onPressed: () {
            setState(() => _archived = !_archived);
            widget.onExpanded(true);
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Add a person or circle',
          icon: const Icon(Icons.add),
          enabled: people != null,
          onSelected: (choice) =>
              choice == 'circle' ? _editCircle(null) : _editPerson(null),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'person', child: Text('New person')),
            PopupMenuItem(value: 'circle', child: Text('New circle')),
          ],
        ),
      ],
      children: switch ((people, _error)) {
        (null, final error?) => [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Couldn't load people. ${switch (error) {
                McpException(:final message) => message,
                _ => '$error',
              }}",
            ),
          ),
          // Self is there regardless.
          _tile(context, defaultSelf, const []),
        ],
        (null, _) => const [LinearProgressIndicator()],
        (final people?, _) => _list(context, people),
      },
    );
  }

  List<Widget> _list(BuildContext context, PeopleList people) {
    final theme = Theme.of(context);
    final circle = people.circles.where((c) => c.id == _circle).firstOrNull;
    final shown = [
      for (final person in people.withSelf)
        if ((_archived || person.active) &&
            (circle == null || person.circleIds.contains(circle.id)))
          person,
    ];
    return [
      if (people.circles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in people.circles)
                FilterChip(
                  avatar: switch (c.health) {
                    final h? => _HealthRing(health: h),
                    null => null,
                  },
                  label: Text(c.name),
                  tooltip: switch (c.health) {
                    final h? => '${c.name}: health $h, ${relationshipBand(h)}',
                    null => c.note ?? c.name,
                  },
                  selected: _circle == c.id,
                  showCheckmark: false,
                  onSelected: (on) =>
                      setState(() => _circle = on ? c.id : null),
                ),
              if (circle != null)
                TextButton.icon(
                  onPressed: () => _editCircle(circle),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('Edit ${circle.name}'),
                ),
            ],
          ),
        ),
      if (circle != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${circle.name}: ${people.inCircle(circle.id).length} '
                  '${people.inCircle(circle.id).length == 1 ? 'person' : 'people'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (circle.healthTrend.isNotEmpty) ...[
                TrendSparkline(
                  trend: circle.healthTrend,
                  scale: HealthScale.relationship,
                ),
                const SizedBox(width: 8),
              ],
              if (circle.health != null)
                HealthDot(
                  rating: circle.health,
                  scale: HealthScale.relationship,
                ),
            ],
          ),
        ),
      for (final person in shown) _tile(context, person, people.circles),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No one in this circle yet.'),
        ),
      if (people.people.where((p) => !p.isSelf).isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Tap + to add the people you want to spend time with.',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  Widget _tile(BuildContext context, Person person, List<Circle> circles) {
    final theme = Theme.of(context);
    final names = [
      for (final c in circles)
        if (person.circleIds.contains(c.id)) c.name,
    ];
    final muted = !person.active;
    return ListTile(
      onTap: () => _open(person),
      leading: CircleAvatar(
        backgroundColor: switch (person.health) {
          final h? => relationshipColor(h),
          null => theme.colorScheme.surfaceContainerHighest,
        },
        foregroundColor: switch (person.health) {
          final h? => contrastingColor(relationshipColor(h)),
          null => theme.colorScheme.onSurfaceVariant,
        },
        child: person.isSelf
            ? const Icon(Icons.person)
            : Text(person.name.isEmpty ? '?' : person.name[0].toUpperCase()),
      ),
      title: Text(
        personName(person),
        style: muted ? TextStyle(color: theme.hintColor) : null,
      ),
      subtitle: switch ([
        if (person.isSelf) 'You',
        ?person.context,
        if (names.isNotEmpty) names.join(', '),
        if (muted) personStatuses[person.status] ?? person.status,
      ]) {
        final lines when lines.isNotEmpty => Text(lines.join(' · ')),
        _ => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (person.healthTrend.isNotEmpty) ...[
            TrendSparkline(
              trend: person.healthTrend,
              scale: HealthScale.relationship,
            ),
            const SizedBox(width: 8),
          ],
          if (person.health != null)
            HealthDot(rating: person.health, scale: HealthScale.relationship),
          PopupMenuButton<String>(
            tooltip: 'More for ${personName(person)}',
            onSelected: (choice) => switch (choice) {
              'edit' => _editPerson(person),
              final status => _setStatus(person, status),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!person.isSelf)
                person.active
                    ? const PopupMenuItem(
                        value: 'archived',
                        child: Text('Archive'),
                      )
                    : const PopupMenuItem(
                        value: 'active',
                        child: Text('Restore'),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A circle's relationship health, as a ring in its color.
class _HealthRing extends StatelessWidget {
  const _HealthRing({required this.health});

  final int health;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: relationshipColor(health), width: 3),
    ),
  );
}
