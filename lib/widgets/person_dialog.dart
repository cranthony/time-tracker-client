import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/focus_store.dart';
import 'hotkeys.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'focus_buttons.dart';
import 'picker_sheet.dart';
import 'scoring_editor.dart';
import 'traits_field.dart';

/// Adds a person (with no [person]) or edits one, on a page of its own
/// ([EditPage]): their name, a context
/// that tells them apart from others of the same name, the [circles]
/// they're in, what matters to them, which of [traits] apply to them --
/// every active one, or those picked -- with their own parts for any, and
/// their status. Self is in no circle and always active. Saves with
/// [save], which gets the fields as `create_person` or `update_person`
/// takes them (null to clear one), and returns what it returned, or null
/// if it was called off. [actions] names the actions and groups a part
/// can count. With [focus], a star beside Save prioritizes someone
/// already there, at once. With [scoreParts], the parts of their own of
/// someone already there are scored as they're edited. Someone added
/// starts with [name], if given.
Future<Person?> showPersonEditor(
  BuildContext context, {
  Person? person,
  String? name,
  List<Circle> circles = const [],
  List<Trait> traits = const [],
  Map<String, String> actions = const {},
  FocusStore? focus,
  PartsScorer? scoreParts,
  required Future<Person> Function(Map<String, Object?> fields) save,
}) => showEditPage<Person>(
  context,
  _PersonEditor(
    person: person,
    name: name,
    circles: circles,
    traits: traits,
    actions: actions,
    focus: focus,
    scoreParts: scoreParts,
    save: save,
  ),
);

class _PersonEditor extends StatefulWidget {
  const _PersonEditor({
    required this.person,
    required this.name,
    required this.circles,
    required this.traits,
    required this.actions,
    required this.focus,
    required this.scoreParts,
    required this.save,
  });

  final Person? person;
  final String? name;
  final List<Circle> circles;
  final List<Trait> traits;
  final Map<String, String> actions;
  final FocusStore? focus;
  final PartsScorer? scoreParts;
  final Future<Person> Function(Map<String, Object?> fields) save;

  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final _name = TextEditingController(
    text: widget.person?.name ?? widget.name,
  );
  late final _context = TextEditingController(text: widget.person?.context);
  late final _whatMatters = TextEditingController(
    text: widget.person?.whatMatters,
  );
  late final _circleIds = {...?widget.person?.circleIds};
  late String _status = widget.person?.status ?? 'active';

  /// Which traits apply to them, and their own parts for any.
  late PersonTraits _traits = widget.person?.traits ?? const PersonTraits();
  bool _saving = false;

  bool get _isSelf => widget.person?.isSelf ?? false;

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    _whatMatters.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, Object?> get _fields => {
    'name': _name.text.trim(),
    'context': _text(_context),
    'what_matters': _text(_whatMatters),
    'traits': _traits.isDefault ? null : _traits.toJson(),
    if (!_isSelf) ...{
      'circles': [..._circleIds],
      'status': _status,
    },
  };

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      navigator.pop(await widget.save(_fields));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        onRetry: _save,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _name.text.trim().isEmpty ? 'Give them a name.' : null;
    final person = widget.person;
    return EditPage(
      title: switch (person) {
        null => 'New person',
        final p when p.isSelf => 'Self',
        final p => 'Edit ${personName(p)}',
      },
      actions: [
        if ((widget.focus, person) case (final focus?, final person?)
            when !person.isSelf)
          prioritizeButton(focus, person),
      ],
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.person == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (!_isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _context,
              decoration: const InputDecoration(
                labelText: 'Context (optional)',
                hintText: 'e.g. met at salsa',
                helperText:
                    'What tells them apart from others of the same '
                    'name.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        if (!_isSelf) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Circles', style: theme.textTheme.titleSmall),
          ),
          if (widget.circles.isEmpty)
            Text(
              'No circles yet: add one from the People section.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final circle in widget.circles)
                  FilterChip(
                    label: Text(circle.name),
                    selected: _circleIds.contains(circle.id),
                    onSelected: (on) => setState(
                      () => on
                          ? _circleIds.add(circle.id)
                          : _circleIds.remove(circle.id),
                    ),
                  ),
              ],
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextField(
            controller: _whatMatters,
            minLines: 6,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isSelf
                  ? 'What matters to you'
                  : 'What matters to them',
              hintText: '- 2026-10-05: starts a new job in November',
              helperText:
                  'One dated line each: facts, moments coming up, '
                  'preferences.',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        TraitsField(
          traits: widget.traits,
          value: _traits,
          actions: widget.actions,
          partsTitle: (trait) => '${trait.name} for ${_text(_name) ?? 'them'}',
          partsExplanation: (trait) =>
              "Their own parts for ${trait.name}, in place of the "
              "trait's: their own cadence, say.",
          preview: switch ((widget.scoreParts, widget.person)) {
            (final score?, final person?) => (trait, parts) => score(
              Subject.person(person),
              trait.id!,
              parts,
            ),
            _ => null,
          },
          onChanged: (traits) => _traits = traits,
        ),
        if (!_isSelf && widget.person != null) ...[
          const SizedBox(height: 16),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(:key, :value) in personStatuses.entries)
                ButtonSegment(value: key, label: Text(value)),
            ],
            selected: {_status},
            onSelectionChanged: (picked) =>
                setState(() => _status = picked.single),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(switch (_status) {
              'archived' => 'Out of touch: kept, out of the way.',
              'deleted' => "Shouldn't have existed.",
              _ => 'Someone you spend time with.',
            }, style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }
}

/// Adds a circle (with no [circle]) or edits one: its name, note, and
/// how its people's scores combine -- its [members], by id, named --
/// in place of [defaultScoring]. Saves with [save]; "Delete", asked
/// first, calls [delete]. Returns true if anything was saved or deleted.
Future<bool> showCircleDialog(
  BuildContext context, {
  Circle? circle,
  Map<String, String> members = const {},
  Aggregation? defaultScoring,
  required Future<void> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _NamedDialog(
        noun: 'circle',
        name: circle?.name,
        detail: circle?.note,
        detailField: 'note',
        detailLabel: 'Note (optional)',
        detailHint: 'Who they are to you',
        nameHint: 'e.g. Family',
        deleteExplanation: 'Everyone in it stays; they just leave the circle.',
        scoring: (
          value: circle?.scoring,
          items: members,
          fallback: switch (defaultScoring) {
            final scoring? => "The defaults': ${scoring.describe()}",
            null => 'Mean',
          },
          fallbackValue: defaultScoring ?? Aggregation.mean,
        ),
        save: save,
        delete: delete,
      ),
    ) ??
    false;

/// Adds a location (with no [location]) or edits one: its name, a hint
/// for recognizing it, its map location, and -- if there are [groups] --
/// the group it's in. Saves with [save], returning what it returned, or
/// null if it was called off. "Delete", asked first, calls [delete]: then
/// [location] is returned. One added starts with [name], if given; with
/// [mapLocation], its map location starts as that, and one it had shows
/// under it. [extra] shows under the rest -- its travel times, from the
/// Locations pane.
Future<Location?> showLocationDialog(
  BuildContext context, {
  Location? location,
  String? name,
  String? mapLocation,
  List<LocationGroup> groups = const [],
  required Future<Location> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
  Widget? extra,
}) async {
  Location? saved;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _NamedDialog(
      noun: 'location',
      name: location?.name,
      typed: name,
      detail: location?.hint,
      detailField: 'hint',
      detailLabel: 'Hint (optional)',
      detailHint: "Other names, an address: \"the apartment; 'my place'\"",
      nameHint: 'e.g. Home',
      deleteExplanation:
          "Events there keep its id, but won't say where they were.",
      map: (value: location?.mapLocation, typed: mapLocation),
      group: groups.isEmpty
          ? null
          : (value: location?.groupId, choices: groups, label: 'Group'),
      save: (fields) async => saved = await save(fields),
      delete: delete,
      extra: extra,
    ),
  );
  return done == true ? saved ?? location : null;
}

/// Adds a location group (with no [group]) or edits one: its name, a note,
/// and the group it's inside, from [groups] -- never itself, or one inside
/// it. Saves with [save], returning what it returned, or null if it was
/// called off. "Delete", asked first, calls [delete]: then [group] is
/// returned. [extra] shows under the rest -- its travel times, from the
/// Locations pane.
Future<LocationGroup?> showLocationGroupDialog(
  BuildContext context, {
  LocationGroup? group,
  List<LocationGroup> groups = const [],
  required Future<LocationGroup> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
  Widget? extra,
}) async {
  LocationGroup? saved;
  final choices = [
    for (final g in groups)
      if (group == null || !enclosingGroupIds(g.id, groups).contains(group.id))
        g,
  ];
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _NamedDialog(
      noun: 'location group',
      name: group?.name,
      detail: group?.note,
      detailField: 'note',
      detailLabel: 'Note (optional)',
      detailHint: 'What it covers: "the blocks around the park"',
      nameHint: 'e.g. Brooklyn',
      deleteExplanation:
          'Its locations and groups stay: they move up into the group it '
          'was in.',
      group: choices.isEmpty
          ? null
          : (value: group?.groupId, choices: choices, label: 'Inside'),
      save: (fields) async => saved = await save(fields),
      delete: delete,
      extra: extra,
    ),
  );
  return done == true ? saved ?? group : null;
}

/// A name, and one more line of text, to save or delete.
class _NamedDialog extends StatefulWidget {
  const _NamedDialog({
    required this.noun,
    required this.name,
    required this.detail,
    required this.detailField,
    required this.detailLabel,
    required this.detailHint,
    required this.nameHint,
    required this.deleteExplanation,
    required this.save,
    required this.delete,
    this.scoring,
    this.map,
    this.group,
    this.typed,
    this.extra,
  });

  final String noun;
  final String? name;

  /// The name a new one starts with.
  final String? typed;
  final String? detail;
  final String detailField;
  final String detailLabel;
  final String detailHint;
  final String nameHint;
  final String deleteExplanation;
  final Future<void> Function(Map<String, Object?> fields) save;
  final Future<void> Function()? delete;

  /// How its people's scores combine, for a circle: as it is, its people
  /// by id, and what's used without it.
  final ({
    Aggregation? value,
    Map<String, String> items,
    String fallback,
    Aggregation fallbackValue,
  })?
  scoring;

  /// Where it is on a map, for a location: as it is, and what it starts
  /// as, if not that.
  final ({String? value, String? typed})? map;

  /// The location group it's in, for a location or a group: as it is, and
  /// the groups it can be in, by [label].
  final ({String? value, List<LocationGroup> choices, String label})? group;

  /// More, under the rest: for a location, its travel times.
  final Widget? extra;

  @override
  State<_NamedDialog> createState() => _NamedDialogState();
}

class _NamedDialogState extends State<_NamedDialog> {
  late final _name = TextEditingController(text: widget.name ?? widget.typed);
  late final _detail = TextEditingController(text: widget.detail);
  late final _map = TextEditingController(
    text: widget.map?.typed ?? widget.map?.value,
  );
  late String? _group = widget.group?.value;
  late Aggregation? _scoring = widget.scoring?.value;
  bool _scoringChanged = false;

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final navigator = Navigator.of(context);
    try {
      await action();
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        await showErrorSheet(
          context,
          title: "Couldn't save",
          error: e,
          onRetry: () => _run(action),
        );
      }
    }
  }

  Future<void> _delete() async {
    final name = widget.name ?? 'this ${widget.noun}';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(widget.deleteExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure == true) await _run(widget.delete!);
  }

  @override
  Widget build(BuildContext context) {
    final named = _name.text.trim().isNotEmpty;
    // The map location it had, if it starts with another.
    final had = switch (widget.map) {
      (value: final value?, typed: final typed?)
          when value.trim().isNotEmpty && value.trim() != typed.trim() =>
        value.trim(),
      _ => null,
    };
    final VoidCallback? save = named
        ? () => _run(
            () => widget.save({
              'name': _name.text.trim(),
              widget.detailField: _detail.text.trim().isEmpty
                  ? null
                  : _detail.text.trim(),
              // Only if it's changed, so a server without map
              // locations can still save the rest.
              if (widget.map case final map?
                  when _map.text.trim() != (map.value ?? ''))
                'map_location': _map.text.trim().isEmpty
                    ? null
                    : _map.text.trim(),
              if (widget.group case final group? when _group != group.value)
                'group_id': _group,
              if (_scoringChanged) 'scoring': _scoring?.toJson(),
            }),
          )
        : null;
    return SaveOrDiscard(
      changed: () =>
          _name.text.trim() != (widget.name ?? widget.typed ?? '').trim() ||
          _detail.text.trim() != (widget.detail ?? '').trim() ||
          _map.text.trim() !=
              (widget.map?.typed ?? widget.map?.value ?? '').trim() ||
          _group != widget.group?.value ||
          _scoringChanged,
      onSave: save,
      child: AlertDialog(
        scrollable: widget.extra != null,
        title: Text(
          widget.name == null ? 'New ${widget.noun}' : 'Edit ${widget.noun}',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.name == null,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: widget.nameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _detail,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: widget.detailLabel,
                  hintText: widget.detailHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (widget.map != null) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _map,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Map location (optional)',
                    hintText:
                        'An address or a link, for events there without one',
                    helperText: had == null ? null : 'Was: $had',
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (widget.group case final group?) ...[
                const SizedBox(height: 16),
                PickerField(
                  label: '${group.label} (optional)',
                  nodes: locationGroupNodes(group.choices),
                  value: _group,
                  none: 'None',
                  groupsPickable: true,
                  searchHint: 'Search groups',
                  onChanged: (picked) => setState(() => _group = picked),
                ),
              ],
              if (widget.scoring case final scoring?)
                AggregationTile(
                  title: 'How its people combine',
                  label: 'How its people combine',
                  explanation: "Their health, into the circle's.",
                  value: _scoring,
                  items: scoring.items,
                  noun: 'people',
                  fallback: scoring.fallback,
                  fallbackValue: scoring.fallbackValue,
                  onChanged: (picked) => setState(() {
                    _scoring = picked;
                    _scoringChanged = true;
                  }),
                ),
              if (widget.extra case final extra?) ...[
                const SizedBox(height: 16),
                extra,
              ],
            ],
          ),
        ),
        actions: [
          if (widget.name != null && widget.delete != null)
            TextButton(onPressed: _delete, child: const Text('Delete')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          HotkeyHint(
            Hotkey.save,
            child: FilledButton(onPressed: save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}
