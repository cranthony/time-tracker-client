import 'package:flutter/material.dart';

import '../models/facets.dart';
import '../models/person.dart';
import '../services/people_repository.dart';

/// Edits what happened at an event, its [facets] -- who it was with and
/// for, where it was, notes on it, and notes on each person there -- and
/// returns them: empty to remove them, or null if it was called off.
/// Claude's ratings of it against the traits' facets are shown, not
/// edited; they're kept for the people still there. The people to pick
/// from come from the [PeopleScope], Self among them.
Future<Facets?> showFacetsDialog(BuildContext context, Facets? facets) =>
    showDialog<Facets>(
      context: context,
      builder: (_) => _FacetsDialog(facets: facets ?? const Facets()),
    );

class _FacetsDialog extends StatefulWidget {
  const _FacetsDialog({required this.facets});

  final Facets facets;

  @override
  State<_FacetsDialog> createState() => _FacetsDialogState();
}

class _FacetsDialogState extends State<_FacetsDialog> {
  late final _with = {...widget.facets.withPersonIds};
  late final _for = {...widget.facets.forPersonIds};
  late final _location = TextEditingController(text: widget.facets.location);
  late final _notes = TextEditingController(text: widget.facets.notes);
  final _personNotes = <String, TextEditingController>{};
  Future<PeopleList>? _people;

  @override
  void initState() {
    super.initState();
    for (final MapEntry(:key, :value) in widget.facets.personNotes.entries) {
      _personNotes[key] = TextEditingController(text: value);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _people ??= PeopleScope.of(context)?.people();
  }

  @override
  void dispose() {
    _location.dispose();
    _notes.dispose();
    for (final c in _personNotes.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Facets get _facets => widget.facets.edited(
    withPersonIds: [..._with],
    forPersonIds: [..._for],
    // Lower-case, as the server keeps them, so they group.
    location: _text(_location)?.toLowerCase(),
    notes: _text(_notes),
    personNotes: {
      for (final MapEntry(:key, :value) in _personNotes.entries)
        key: ?_text(value),
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('What happened'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: FutureBuilder(
            future: _people,
            builder: (context, snapshot) {
              final people =
                  snapshot.data?.withSelf ??
                  // Without the list, at least who's already there.
                  [
                    defaultSelf,
                    for (final id in {..._with, ..._for})
                      if (id != selfPersonId) Person(id: id, name: id),
                  ];
              final shown = [
                for (final p in people)
                  if (p.active || _with.contains(p.id) || _for.contains(p.id))
                    p,
              ];
              final involved = [
                for (final p in people)
                  if (_with.contains(p.id) || _for.contains(p.id)) p,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator(),
                  _chips(theme, 'With', 'Who was there', shown, _with),
                  _chips(
                    theme,
                    'For',
                    'Who it was done for, there or not',
                    shown,
                    _for,
                  ),
                  _field(_location, 'Location', 'e.g. the hall'),
                  _field(
                    _notes,
                    'Notes',
                    'What happened, in a line or two',
                    maxLines: 3,
                  ),
                  for (final person in involved)
                    _field(
                      _personNotes.putIfAbsent(
                        person.id,
                        TextEditingController.new,
                      ),
                      'Notes on ${personName(person)}',
                      person.isSelf
                          ? 'How you were'
                          : 'How they were, what they shared',
                      maxLines: 2,
                    ),
                  if (widget.facets.judgments.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        "Claude's ratings",
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    for (final j in widget.facets.judgments)
                      Text(
                        '${j.traitId ?? 'Facet'}'
                        '${j.personId == null ? '' : ', for ${_name(people, j.personId!)}'}'
                        ': ${j.rating}'
                        '${j.why == null ? '' : ' — ${j.why}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        if (!widget.facets.isEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const Facets()),
            child: const Text('Remove all'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_facets),
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

  /// Everyone [shown], as chips, those in [picked] selected.
  Widget _chips(
    ThemeData theme,
    String label,
    String hint,
    List<Person> shown,
    Set<String> picked,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        Text(hint, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final person in shown)
              FilterChip(
                label: Text(personName(person)),
                selected: picked.contains(person.id),
                onSelected: (on) => setState(
                  () => on ? picked.add(person.id) : picked.remove(person.id),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    ),
  );
}
