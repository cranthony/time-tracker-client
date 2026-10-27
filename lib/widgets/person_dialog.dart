import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import 'hotkeys.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'people_picker.dart';
import 'quick_add_sheet.dart';
import 'scoring_editor.dart';
import 'traits_field.dart';

/// Adds a person (with no [person]) or edits one, on a page of its own
/// ([EditPage]): their name, a context
/// that tells them apart from others of the same name, the [circles]
/// they're in, which of [traits] apply to them -- every active one, or
/// those picked -- with their own parts for any, their summary of each of
/// those traits' facts (someone already there), and their status. Self is in no circle and always active. Saves with
/// [save], which gets the fields as `create_person` or `update_person`
/// takes them (null to clear one), and returns what it returned, or null
/// if it was called off. [actions] names the actions and groups a part
/// can count. With [scoreParts], the parts of their own of
/// someone already there are scored as they're edited. Someone added
/// starts with [name], if given, and with [fields] -- their name, context
/// and circles, as `create_person` takes them -- typed in the quick New
/// person sheet before its More.
Future<Person?> showPersonEditor(
  BuildContext context, {
  Person? person,
  String? name,
  Map<String, Object?> fields = const {},
  List<Circle> circles = const [],
  List<Trait> traits = const [],
  Map<String, String> actions = const {},
  PartsScorer? scoreParts,
  required Future<Person> Function(Map<String, Object?> fields) save,
}) => showEditPage<Person>(
  context,
  _PersonEditor(
    person: person,
    name: fields['name'] as String? ?? name,
    typed: fields,
    circles: circles,
    traits: traits,
    actions: actions,
    scoreParts: scoreParts,
    save: save,
  ),
);

class _PersonEditor extends StatefulWidget {
  const _PersonEditor({
    required this.person,
    required this.name,
    required this.typed,
    required this.circles,
    required this.traits,
    required this.actions,
    required this.scoreParts,
    required this.save,
  });

  final Person? person;
  final String? name;

  /// What a new person starts with, as `create_person` takes it.
  final Map<String, Object?> typed;
  final List<Circle> circles;
  final List<Trait> traits;
  final Map<String, String> actions;
  final PartsScorer? scoreParts;
  final Future<Person> Function(Map<String, Object?> fields) save;

  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final _name = TextEditingController(
    text: widget.person?.name ?? widget.name,
  );
  late final _context = TextEditingController(
    text: widget.person?.context ?? widget.typed['context'] as String?,
  );

  /// Their summary of each trait fact, by "trait id/fact id", for every
  /// trait's -- those shown being those of the traits that apply.
  late final _summaries = {
    for (final trait in widget.traits)
      if (trait.id case final traitId?)
        for (final fact in trait.facts)
          '$traitId/${fact.id}': TextEditingController(
            text: widget.person?.summary(traitId, fact.id),
          ),
  };
  late final _circleIds = {
    ...?widget.person?.circleIds,
    for (final id in widget.typed['circles'] as List? ?? const []) '$id',
  };
  late String _status = widget.person?.status ?? 'active';

  /// Which traits apply to them, and their own parts for any.
  late PersonTraits _traits = widget.person?.traits ?? const PersonTraits();
  bool _saving = false;

  bool get _isSelf => widget.person?.isSelf ?? false;

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    for (final summary in _summaries.values) {
      summary.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, Object?> get _fields => {
    'name': _name.text.trim(),
    'context': _text(_context),
    'traits': _traits.isDefault ? null : _traits.toJson(),
    // Every summary shown, as update_person's facts set them -- when one
    // changed.
    if (widget.person case final person? when _summariesChanged(person))
      'facts': {
        for (final (trait, facts) in _shownFacts)
          trait.id!: {
            for (final fact in facts)
              fact.id: _summaries['${trait.id}/${fact.id}']!.text.trim(),
          },
      },
    if (!_isSelf) ...{
      'circles': [..._circleIds],
      'status': _status,
    },
  };

  /// The active traits that apply to them, as their traits stand, each
  /// with its facts: those whose summaries are shown.
  List<(Trait, List<TraitFact>)> get _shownFacts => [
    for (final trait in widget.traits)
      if (trait.id != null &&
          trait.status == 'active' &&
          trait.facts.isNotEmpty &&
          (_traits.select?.contains(trait.id) ?? true))
        (trait, trait.facts),
  ];

  bool _summariesChanged(Person person) => [
    for (final (trait, facts) in _shownFacts)
      for (final fact in facts)
        _summaries['${trait.id}/${fact.id}']!.text.trim() !=
            (person.summary(trait.id!, fact.id) ?? ''),
  ].any((changed) => changed);

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
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
        FieldHotkey(
          'N',
          child: TextField(
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
        ),
        if (!_isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FieldHotkey(
              'C',
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
          ),
        if (!_isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CirclesField(
              circles: widget.circles,
              picked: [..._circleIds],
              hotkey: 'I',
              onChanged: (ids) => setState(
                () => _circleIds
                  ..clear()
                  ..addAll(ids),
              ),
            ),
          ),
        FieldHotkey(
          'T',
          focusOnly: true,
          child: TraitsField(
            traits: widget.traits,
            value: _traits,
            actions: widget.actions,
            partsTitle: (trait) =>
                '${trait.name} for ${_text(_name) ?? 'them'}',
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
            onChanged: (traits) => setState(() => _traits = traits),
          ),
        ),
        if (widget.person != null && _shownFacts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Facts', style: theme.textTheme.titleSmall),
          ),
          Text(
            'What each trait keeps about ${_isSelf ? 'you' : 'them'}, for '
            'its judgments. Compaction rewrites these as notes show '
            "something new; what you change here isn't logged.",
            style: theme.textTheme.bodySmall,
          ),
          for (final (trait, facts) in _shownFacts)
            for (final fact in facts)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _summaries['${trait.id}/${fact.id}'],
                  minLines: 3,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: '${fact.name} · ${trait.name}',
                    helperText: fact.summaryPrompt,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
        ],
        if (!_isSelf && widget.person != null) ...[
          const SizedBox(height: 16),
          FieldHotkey(
            'S',
            onPressed: () => setState(
              () => _status = nextOf(personStatuses.keys.toList(), _status),
            ),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final MapEntry(:key, :value) in personStatuses.entries)
                  ButtonSegment(value: key, label: Text(value)),
              ],
              selected: {_status},
              onSelectionChanged: (picked) =>
                  setState(() => _status = picked.single),
            ),
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

/// Adds a circle (with no [circle]), named [name] to start with, or edits
/// one: its name, note, whether it's a community -- set only as it's
/// made, shown as it is after -- and, for a plain circle, how its
/// people's scores combine -- its [members], by id, named -- in place of
/// [defaultScoring]; for a community, which of [traits] apply to it --
/// every active one, or those picked -- with its own parts for any
/// ([actions] naming the actions and groups a part can count, and
/// [scoreParts] scoring the parts of one already there as they're
/// edited), and its summary of each of those traits' facts (one already
/// there). Saves with [save], a new one's fields with its `kind`, a
/// community's with its `traits` and, when one changed, its `facts`;
/// "Delete", asked first, calls [delete]. Returns true if anything was
/// saved or deleted.
Future<bool> showCircleDialog(
  BuildContext context, {
  Circle? circle,
  String? name,
  Map<String, String> members = const {},
  Aggregation? defaultScoring,
  List<Trait> traits = const [],
  Map<String, String> actions = const {},
  PartsScorer? scoreParts,
  required Future<void> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _NamedDialog(
        noun: 'circle',
        name: circle?.name,
        typed: name,
        detail: circle?.note,
        detailField: 'note',
        detailLabel: 'Note (optional)',
        detailHint: 'Who they are to you',
        nameHint: 'e.g. Family',
        deleteExplanation: 'Everyone in it stays; they just leave the circle.',
        community: (value: circle?.isCommunity ?? false, fixed: circle != null),
        traits: traits.isEmpty
            ? null
            : (
                all: traits,
                value: circle?.traits ?? const PersonTraits(),
                actions: actions,
                of: circle,
                scoreParts: scoreParts,
              ),
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
/// under it. With [addGroup], a new group can be added from its group
/// picker (see [LocationGroupField]). [extra] shows under the rest -- its
/// travel times, from the Locations pane.
Future<Location?> showLocationDialog(
  BuildContext context, {
  Location? location,
  String? name,
  String? mapLocation,
  List<LocationGroup> groups = const [],
  required Future<Location> Function(Map<String, Object?> fields) save,
  Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup,
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
      group: groups.isEmpty && addGroup == null
          ? null
          : (value: location?.groupId, choices: groups, label: 'Group'),
      addGroup: addGroup,
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
/// returned. With [addGroup], a new group to be inside can be added from
/// its picker (see [LocationGroupField]). [extra] shows under the rest --
/// its travel times, from the Locations pane.
Future<LocationGroup?> showLocationGroupDialog(
  BuildContext context, {
  LocationGroup? group,
  List<LocationGroup> groups = const [],
  required Future<LocationGroup> Function(Map<String, Object?> fields) save,
  Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup,
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
      group: choices.isEmpty && addGroup == null
          ? null
          : (value: group?.groupId, choices: choices, label: 'Inside'),
      addGroup: addGroup,
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
    this.community,
    this.traits,
    this.map,
    this.group,
    this.addGroup,
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

  /// Whether it's a community, for a circle: as it is, and whether that's
  /// [fixed] -- set when it was made, never changed.
  final ({bool value, bool fixed})? community;

  /// A community's traits, for a circle: every trait that could apply
  /// ([all]), which do as it stands ([value]), the actions and groups a
  /// part can count, and, for one already there ([of]), its summary of
  /// each trait fact and what scores its parts as they're edited. Shown
  /// only while it's a community.
  final ({
    List<Trait> all,
    PersonTraits value,
    Map<String, String> actions,
    Circle? of,
    PartsScorer? scoreParts,
  })?
  traits;

  /// Where it is on a map, for a location: as it is, and what it starts
  /// as, if not that.
  final ({String? value, String? typed})? map;

  /// The location group it's in, for a location or a group: as it is, and
  /// the groups it can be in, by [label].
  final ({String? value, List<LocationGroup> choices, String label})? group;

  /// Adds a location group, to put it in.
  final Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup;

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
  late var _groups = widget.group?.choices ?? const <LocationGroup>[];
  late Aggregation? _scoring = widget.scoring?.value;
  bool _scoringChanged = false;
  late bool _community = widget.community?.value ?? false;

  /// Which traits apply to a community, and its own parts for any.
  late PersonTraits _traits = widget.traits?.value ?? const PersonTraits();
  bool _traitsChanged = false;

  /// A community's summary of each trait fact, by "trait id/fact id",
  /// for every trait's -- those shown being those of the traits that
  /// apply.
  late final _summaries = {
    for (final trait in widget.traits?.all ?? const <Trait>[])
      if (trait.id case final traitId?)
        for (final fact in trait.facts)
          '$traitId/${fact.id}': TextEditingController(
            text: widget.traits?.of?.summary(traitId, fact.id),
          ),
  };

  /// The active traits that apply to a community already there, as its
  /// traits stand, each with its facts: those whose summaries are shown.
  List<(Trait, List<TraitFact>)> get _shownFacts => [
    if (widget.traits case final traits? when traits.of != null)
      for (final trait in traits.all)
        if (trait.id != null &&
            trait.status == 'active' &&
            trait.facts.isNotEmpty &&
            (_traits.select?.contains(trait.id) ?? true))
          (trait, trait.facts),
  ];

  bool get _summariesChanged => [
    for (final (trait, facts) in _shownFacts)
      for (final fact in facts)
        _summaries['${trait.id}/${fact.id}']!.text.trim() !=
            (widget.traits?.of?.summary(trait.id!, fact.id) ?? ''),
  ].any((changed) => changed);

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    _map.dispose();
    for (final summary in _summaries.values) {
      summary.dispose();
    }
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
              // Set as it's made: an update never sends it.
              if (widget.community case (value: _, fixed: false))
                'kind': _community
                    ? CircleKind.community.json
                    : CircleKind.circle.json,
              if (_scoringChanged && !_community) 'scoring': _scoring?.toJson(),
              // A community's traits, as it's made or they're changed,
              // and its summaries, when one changed; a plain circle
              // takes neither.
              if (widget.traits case final traits? when _community) ...{
                if (traits.of == null || _traitsChanged)
                  'traits': _traits.isDefault ? null : _traits.toJson(),
                if (_summariesChanged)
                  'facts': {
                    for (final (trait, facts) in _shownFacts)
                      trait.id!: {
                        for (final fact in facts)
                          fact.id: _summaries['${trait.id}/${fact.id}']!.text
                              .trim(),
                      },
                  },
              },
            }),
          )
        : null;
    final letters = fieldLetters([
      'name',
      widget.detailLabel,
      if (widget.map != null) 'map',
      ?widget.group?.label,
      if (widget.community != null) 'community',
      if (widget.traits != null) 'traits',
      if (widget.scoring != null) 'combine',
      if (widget.extra != null) 'travel',
    ]);
    return SaveOrDiscard(
      changed: () =>
          _name.text.trim() != (widget.name ?? widget.typed ?? '').trim() ||
          _detail.text.trim() != (widget.detail ?? '').trim() ||
          _map.text.trim() !=
              (widget.map?.typed ?? widget.map?.value ?? '').trim() ||
          _group != widget.group?.value ||
          _community != (widget.community?.value ?? false) ||
          _scoringChanged ||
          _traitsChanged ||
          _summariesChanged,
      onSave: save,
      child: AlertDialog(
        scrollable: widget.extra != null || widget.traits != null,
        title: Text(
          widget.name == null ? 'New ${widget.noun}' : 'Edit ${widget.noun}',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldHotkey(
                letters['name'],
                child: TextField(
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
              ),
              FieldHotkey(
                letters[widget.detailLabel],
                child: TextField(
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
              ),
              if (widget.map != null) ...[
                const SizedBox(height: 16),
                FieldHotkey(
                  letters['map'],
                  child: TextField(
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
                ),
              ],
              if (widget.group case final group?) ...[
                const SizedBox(height: 16),
                FieldHotkey(
                  letters[group.label],
                  child: LocationGroupField(
                    label: '${group.label} (optional)',
                    groups: _groups,
                    value: _group,
                    addGroup: widget.addGroup,
                    onAdded: (added) {
                      if (mounted) {
                        setState(() => _groups = withGroup(_groups, added));
                      }
                    },
                    onChanged: (picked) => setState(() => _group = picked),
                  ),
                ),
              ],
              if (widget.community case final community?) ...[
                const SizedBox(height: 8),
                FieldHotkey(
                  letters['community'],
                  onPressed: community.fixed
                      ? null
                      : () => setState(() => _community = !_community),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This circle is a community'),
                    subtitle: Text(
                      community.fixed
                          ? "Set when it was made: a circle's kind can't "
                                'change.'
                          : _community
                          ? 'A subject of its own -- a team, a club -- with '
                                'traits and judgments of its own, scored by '
                                'them alone. An event or goal with it is '
                                'with it, not each of its people.'
                          : 'Off, it stands for its people: an event or '
                                'goal with it is with each of them, and its '
                                'score is theirs combined.',
                    ),
                    value: _community,
                    onChanged: community.fixed
                        ? null
                        : (on) => setState(() => _community = on),
                  ),
                ),
              ],
              if (widget.traits case final traits? when _community) ...[
                const SizedBox(height: 8),
                FieldHotkey(
                  letters['traits'],
                  focusOnly: true,
                  child: TraitsField(
                    traits: traits.all,
                    value: _traits,
                    actions: traits.actions,
                    own: 'Its own',
                    partsTitle: (trait) =>
                        '${trait.name} for '
                        '${_name.text.trim().isEmpty ? 'it' : _name.text.trim()}',
                    partsExplanation: (trait) =>
                        "Its own parts for ${trait.name}, in place of the "
                        "trait's.",
                    preview: switch ((traits.scoreParts, traits.of)) {
                      (final score?, final of?) => (trait, parts) => score(
                        Subject.community(of),
                        trait.id!,
                        parts,
                      ),
                      _ => null,
                    },
                    onChanged: (picked) => setState(() {
                      _traits = picked;
                      _traitsChanged = true;
                    }),
                  ),
                ),
                if (_shownFacts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      'Facts',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    'What each trait keeps about it, for its judgments. '
                    'Compaction rewrites these as notes show something '
                    "new; what you change here isn't logged.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final (trait, facts) in _shownFacts)
                    for (final fact in facts)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: _summaries['${trait.id}/${fact.id}'],
                          minLines: 3,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: '${fact.name} · ${trait.name}',
                            helperText: fact.summaryPrompt,
                            helperMaxLines: 3,
                            border: const OutlineInputBorder(),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                ],
              ],
              if (widget.scoring case final scoring? when !_community)
                FieldHotkey(
                  letters['combine'],
                  child: AggregationTile(
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
                ),
              if (widget.extra case final extra?) ...[
                const SizedBox(height: 16),
                FieldHotkey(letters['travel'], focusOnly: true, child: extra),
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
