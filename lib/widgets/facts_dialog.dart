import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/person.dart';
import '../models/proposal.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import 'person_dialog.dart';

/// Edits what happened at an event, its [facts] -- who was there with you,
/// who it was done for while they weren't, where it was, and a note on you
/// and on each person there -- and returns them: empty to remove them, or
/// null if it was called off. The assistant's [judgments] of it are shown,
/// not edited. The people and locations to pick from come from the
/// [PeopleScope]; a new location can be added from here.
Future<Facts?> showFactsDialog(
  BuildContext context,
  Facts? facts, {
  List<Judgment> judgments = const [],
  Map<String?, String> traitNames = const {},
  List<ProposalAddition> additions = const [],
}) => showDialog<Facts>(
  context: context,
  builder: (_) => _FactsDialog(
    facts: facts ?? const Facts(),
    judgments: judgments,
    traitNames: traitNames,
    additions: additions,
  ),
);

class _FactsDialog extends StatefulWidget {
  const _FactsDialog({
    required this.facts,
    required this.judgments,
    required this.traitNames,
    this.additions = const [],
  });

  final Facts facts;
  final List<Judgment> judgments;
  final Map<String?, String> traitNames;

  /// The people and locations a compaction proposal adds: offered too,
  /// by their refs, marked new.
  final List<ProposalAddition> additions;

  @override
  State<_FactsDialog> createState() => _FactsDialogState();
}

class _FactsDialogState extends State<_FactsDialog> {
  late final _with = {...widget.facts.withIds}..remove(selfPersonId);
  late final _for = {...widget.facts.forIds}..remove(selfPersonId);
  late String? _location = widget.facts.locationId;
  final _notes = <String, TextEditingController>{};
  PeopleRepository? _repository;
  PlanMemory? _memory;
  Future<PeopleList>? _people;
  Future<List<Location>>? _locations;

  @override
  void initState() {
    super.initState();
    for (final MapEntry(:key, :value) in widget.facts.notes.entries) {
      _notes[key] = TextEditingController(text: value);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) return;
    final repository = _repository = PeopleScope.of(context);
    if (repository == null) return;
    final memory = _memory = PlanMemoryScope.of(context);
    if (memory == null) {
      _people = repository.people();
      _locations = repository.locations();
      return;
    }
    // What the Events page loaded, or is loading, rather than asking
    // again; what's kept, if that fails.
    _people = _kept(memory.loadPeople(repository), () => memory.people);
    _locations = _kept(
      memory.loadLocations(repository),
      () => memory.locations,
    );
  }

  /// What [loading] leaves [kept], or what it kept already, if it fails.
  static Future<T> _kept<T>(Future<void> loading, T? Function() kept) async {
    try {
      await loading;
    } catch (_) {
      if (kept() case final had?) return had;
      rethrow;
    }
    return kept() as T;
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Facts get _facts => Facts(
    locationId: _location,
    withIds: [..._with],
    forIds: [..._for],
    notes: {
      for (final MapEntry(:key, :value) in _notes.entries)
        if (key == selfPersonId || _with.contains(key))
          if (value.text.trim().isNotEmpty) key: value.text.trim(),
    },
  );

  Future<void> _newLocation() async {
    final repository = _repository;
    if (repository == null) return;
    final created = await showLocationDialog(
      context,
      save: (fields) => repository.createLocation(
        Location(
          id: '',
          name: fields['name'] as String,
          hint: fields['hint'] as String?,
        ),
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _location = created.id;
      _locations = switch (_memory) {
        final memory? => _kept(
          memory.loadLocations(repository, again: true),
          () => memory.locations,
        ),
        null => repository.locations(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _facts.problem;
    return AlertDialog(
      title: const Text('What happened'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: FutureBuilder(
            future: _people,
            initialData: _memory?.people,
            builder: (context, snapshot) {
              final added = [
                for (final a in widget.additions)
                  if (a.kind == AdditionKind.person)
                    Person(
                      id: a.ref,
                      name: '${a.name} (new)',
                      context: a.detail,
                    ),
              ];
              final everyone = [
                ...snapshot.data?.withSelf ??
                    // Without the list, at least who's already there.
                    [
                      defaultSelf,
                      for (final id in {..._with, ..._for})
                        if (!added.any((p) => p.id == id))
                          Person(id: id, name: id),
                    ],
                ...added,
              ];
              final others = [
                for (final p in everyone)
                  if (!p.isSelf &&
                      (p.active || _with.contains(p.id) || _for.contains(p.id)))
                    p,
              ];
              final there = [
                everyone.firstWhere((p) => p.isSelf, orElse: () => defaultSelf),
                for (final p in others)
                  if (_with.contains(p.id)) p,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Only while there's no one to show: what's known shows at once.
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const LinearProgressIndicator(),
                  _chips(
                    theme,
                    'With you',
                    'Who was there',
                    others,
                    _with,
                    _for,
                  ),
                  _chips(
                    theme,
                    'For',
                    "Who it was done for, while they weren't there",
                    others,
                    _for,
                    _with,
                  ),
                  _locationPicker(),
                  for (final person in there)
                    _note(
                      person,
                      person.isSelf
                          ? 'How it was for you'
                          : 'How it was for them, what they shared',
                    ),
                  if (widget.judgments.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        "Claude's judgments",
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    for (final j in widget.judgments)
                      Text(
                        '${_name(everyone, j.personId)} · '
                        '${widget.traitNames[j.traitId] ?? j.traitId}: '
                        '${j.rating}${j.scale == null ? '' : ' of ${j.scale}'}'
                        '${j.reasoning == null ? '' : ' — ${j.reasoning}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        problem,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        if (!widget.facts.isEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const Facts()),
            child: const Text('Remove all'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem == null
              ? () => Navigator.of(context).pop(_facts)
              : null,
          child: const Text('Done'),
        ),
      ],
    );
  }

  static String _name(List<Person> people, String id) =>
      switch (people.where((p) => p.id == id).firstOrNull) {
        final p? => personName(p),
        null => id,
      };

  /// Everyone in [people], as chips, those in [picked] selected; picking
  /// one takes them out of [other], since no one is both there and not.
  Widget _chips(
    ThemeData theme,
    String label,
    String hint,
    List<Person> people,
    Set<String> picked,
    Set<String> other,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        Text(hint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        if (people.isEmpty)
          Text(
            'No one yet: add people on the Plan page.',
            style: TextStyle(color: theme.hintColor),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final person in people)
              FilterChip(
                label: Text(personName(person, context: true)),
                selected: picked.contains(person.id),
                onSelected: (on) => setState(() {
                  if (on) {
                    picked.add(person.id);
                    other.remove(person.id);
                  } else {
                    picked.remove(person.id);
                  }
                }),
              ),
          ],
        ),
      ],
    ),
  );

  /// Where it was: none, a location, or a new one.
  Widget _locationPicker() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: FutureBuilder(
      future: _locations,
      initialData: _memory?.locations,
      builder: (context, snapshot) {
        final locations = [
          ...snapshot.data ?? const <Location>[],
          for (final a in widget.additions)
            if (a.kind == AdditionKind.location)
              Location(id: a.ref, name: '${a.name} (new)', hint: a.detail),
        ];
        final known = locations.any((l) => l.id == _location);
        return DropdownButtonFormField<String?>(
          key: ValueKey((_location, locations.length)),
          initialValue: _location,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Location',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not said')),
            for (final l in locations)
              DropdownMenuItem(value: l.id, child: Text(l.name)),
            if (_location != null && !known)
              DropdownMenuItem(value: _location, child: Text(_location!)),
            if (_repository != null)
              const DropdownMenuItem(
                value: _newLocationValue,
                child: Text('New location…'),
              ),
          ],
          onChanged: (picked) {
            if (picked == _newLocationValue) {
              _newLocation();
              return;
            }
            setState(() => _location = picked);
          },
        );
      },
    ),
  );

  Widget _note(Person person, String hint) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: _notes.putIfAbsent(person.id, TextEditingController.new),
      minLines: 1,
      maxLines: 3,
      maxLength: 1000,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: person.isSelf
            ? 'Notes on you'
            : 'Notes on ${personName(person)}',
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        counterText: '',
      ),
    ),
  );
}

/// The location picker's value for adding one.
const _newLocationValue = '\u0000new';
