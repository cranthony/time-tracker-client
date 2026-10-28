import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/person.dart';
import '../models/plan_action.dart';
import 'action_icon.dart';
import 'actions_picker.dart';
import 'hotkeys.dart';
import 'people_picker.dart';
import 'picker_sheet.dart';

// Quick ways to add a person, a location, a location group or an action:
// a sheet over the bottom of the screen, as the New note and New goal sheets are, with the
// fields most often set -- and, where there's more to set than fits, a
// More button that goes on in the full page or dialog with what's typed.

/// Asks for a new person's name, context and circles (of [circles]), in a
/// sheet, starting with [name] and [about] (their context) if given, and saves them with
/// [save], given the fields as `create_person` takes them; if [save]
/// fails, it stays open, saying so, to try again. Its More button closes
/// it to go on with [more], given what's typed, for the rest of their
/// fields. Returns what [save] (or [more]) returned, or null if it was
/// called off.
Future<T?> showAddPersonSheet<T extends Object>(
  BuildContext context, {
  String? name,
  String? about,
  List<Circle> circles = const [],
  required Future<T> Function(Map<String, Object?> fields) save,
  Future<T?> Function(Map<String, Object?> fields)? more,
}) => _show(
  context,
  _PersonSheet(name: name, contextText: about, circles: circles, save: save),
  more,
);

/// Asks for a new location's name, hint, map location and group (of
/// [groups]), in a sheet, starting with [name], [hint] and [mapLocation]
/// if given, and saves it with [save], given the fields as
/// `create_location` takes them; if [save] fails, it stays open, saying
/// so, to try again. That's every field a location has, so there's no
/// More. With [addGroup], a new group can be added from its group picker
/// (see [LocationGroupField]). Returns what [save] returned, or null if it
/// was called off.
Future<T?> showAddLocationSheet<T extends Object>(
  BuildContext context, {
  String? name,
  String? hint,
  String? mapLocation,
  List<LocationGroup> groups = const [],
  required Future<T> Function(Map<String, Object?> fields) save,
  Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup,
}) => _show(
  context,
  _LocationSheet(
    name: name,
    hint: hint,
    mapLocation: mapLocation,
    groups: groups,
    save: save,
    addGroup: addGroup,
  ),
  null,
);

/// Asks for a new location group's name, note and the group it's inside
/// (of [groups]), in a sheet, starting with [name] if given, and saves it
/// with [save], given the fields as `create_location_group` takes them;
/// if [save] fails, it stays open, saying so, to try again. The group
/// it's inside can be a new one too, added with [save] in turn. That's
/// every field a group has, so there's no More. Returns the group as
/// saved, or null if it was called off.
Future<LocationGroup?> showAddLocationGroupSheet(
  BuildContext context, {
  String? name,
  List<LocationGroup> groups = const [],
  required Future<LocationGroup> Function(Map<String, Object?> fields) save,
}) => _show(
  context,
  _LocationGroupSheet(name: name, groups: groups, save: save),
  null,
);

/// Asks for a new action's name, the group it's in (of [actions]) and
/// its note -- or, with [group], a group's -- in a sheet, starting with
/// [name] and in [parentId] if given, and saves it with [save], given the
/// fields as `create_action` takes them; if [save] fails, it stays open,
/// saying so, to try again. Its More button closes it to go on with
/// [more], given what's typed, for its priority, color and the rest. With
/// [addGroup], a new group can be added from its group picker (see
/// [ActionGroupField]). Returns what [save] (or [more]) returned, or null
/// if it was called off.
Future<T?> showAddActionSheet<T extends Object>(
  BuildContext context, {
  String? name,
  String? parentId,
  bool group = false,
  required List<PlanAction> actions,
  required Future<T> Function(Map<String, Object?> fields) save,
  Future<T?> Function(Map<String, Object?> fields)? more,
  Future<AddedAction> Function(Map<String, Object?> fields)? addGroup,
}) => _show(
  context,
  _ActionSheet(
    name: name,
    parentId: parentId,
    group: group,
    actions: actions,
    save: save,
    hasMore: more != null,
    addGroup: addGroup,
  ),
  more,
);

/// An action or group just added: its id, and every action and group as
/// they're to be shown now, it among them.
typedef AddedAction = ({String id, List<PlanAction> actions});

/// What a quick add sheet was closed with: what it saved, or what's typed
/// to go on with in More.
sealed class _Closed<T> {}

final class _Saved<T> extends _Closed<T> {
  _Saved(this.saved);
  final T saved;
}

final class _More<T> extends _Closed<T> {
  _More(this.fields);
  final Map<String, Object?> fields;
}

Future<T?> _show<T extends Object>(
  BuildContext context,
  Widget sheet,
  Future<T?> Function(Map<String, Object?> fields)? more,
) async {
  final closed = await showModalBottomSheet<_Closed<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => sheet,
  );
  return switch (closed) {
    _Saved(:final saved) => saved,
    _More(:final fields) when more != null && context.mounted => await more(
      fields,
    ),
    _ => null,
  };
}

/// What each quick add sheet's state shares: saving its fields, staying
/// open to try again if that fails, and going on in More.
mixin _Adding<W extends StatefulWidget, T> on State<W> {
  /// Whether it's being saved.
  bool saving = false;

  /// Why it couldn't be saved, the last time.
  String? saveError;

  /// The fields to save, as its create tool takes them.
  Map<String, Object?> get fields;

  /// Whether there's enough to save.
  bool get complete;

  Future<T> Function(Map<String, Object?> fields) get save;

  bool get addable => !saving && complete;

  Future<void> add() async {
    if (!addable) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    final T saved;
    try {
      saved = await save(fields);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = "Couldn't add it: $e";
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(_Saved<T>(saved));
  }

  void goOn() => Navigator.of(context).pop(_More<T>(fields));
}

/// A quick add sheet's frame: [title], its [fields] down it, why it
/// couldn't be saved, if it couldn't, and More (if [onMore]) and Add.
/// Ctrl+Enter adds.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.fields,
    required this.onAdd,
    required this.saving,
    required this.saveError,
    this.onMore,
  });

  final String title;
  final List<Widget> fields;
  final VoidCallback? onAdd;
  final VoidCallback? onMore;
  final bool saving;
  final String? saveError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return HotkeyBindings(
      bindings: [
        HotkeyBinding(
          const HotkeyTrigger.ctrl(LogicalKeyboardKey.enter),
          () => onAdd?.call(),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          // Above the keyboard, or else the gesture bar.
          bottom: max(media.viewInsets.bottom, media.viewPadding.bottom) + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (i, field) in fields.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                field,
              ],
              if (saveError case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onMore case final more?) ...[
                    FieldHotkey(
                      'M',
                      child: TextButton(
                        onPressed: saving ? null : more,
                        child: const Text('More'),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  HotkeyHint(
                    Hotkey.save,
                    child: FilledButton(
                      onPressed: onAdd,
                      child: Text(saveError == null ? 'Add' : 'Try again'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [text] trimmed, or null if that leaves nothing.
String? _trimmed(String text) => text.trim().isEmpty ? null : text.trim();

/// The location group something's in, of [groups], under [label]: none,
/// or one picked in a sheet, as [PickerField] picks. With [addGroup], a
/// new one can be added there, named as it's typed, in the quick New
/// location group sheet: [onAdded] is told of it -- and of any group
/// added inside that sheet in turn -- so it can be shown, then it's
/// picked.
class LocationGroupField extends StatelessWidget {
  const LocationGroupField({
    super.key,
    required this.label,
    required this.groups,
    required this.value,
    required this.onChanged,
    this.addGroup,
    this.onAdded,
  });

  final String label;
  final List<LocationGroup> groups;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup;
  final ValueChanged<LocationGroup>? onAdded;

  @override
  Widget build(BuildContext context) => PickerField(
    label: label,
    nodes: locationGroupNodes(groups),
    value: value,
    none: 'None',
    groupsPickable: true,
    searchHint: 'Search groups',
    onChanged: onChanged,
    add: switch (addGroup) {
      final addGroup? => (
        noun: 'location group',
        icon: Icons.create_new_folder_outlined,
        onAdd: (name) async {
          final added = await showAddLocationGroupSheet(
            context,
            name: name.isEmpty ? null : name,
            groups: groups,
            save: (fields) async {
              final added = await addGroup(fields);
              onAdded?.call(added);
              return added;
            },
          );
          return added?.id;
        },
      ),
      null => null,
    },
  );
}

/// The action group something's in, of [actions]: none (top-level), or
/// one picked in a sheet, as [ActionField] picks -- never an action, a
/// group put away (unless it's [value]), or one in [exclude]. With
/// [addGroup], a new one can be added there, named as it's typed, in the
/// quick New group sheet: [onAdded] is told of every action as they are
/// with it -- and with any group added inside that sheet in turn -- so it
/// can be shown, then it's picked.
class ActionGroupField extends StatelessWidget {
  const ActionGroupField({
    super.key,
    required this.actions,
    required this.value,
    required this.onChanged,
    this.exclude = const {},
    this.addGroup,
    this.onAdded,
  });

  final List<PlanAction> actions;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Set<String> exclude;
  final Future<AddedAction> Function(Map<String, Object?> fields)? addGroup;
  final ValueChanged<List<PlanAction>>? onAdded;

  @override
  Widget build(BuildContext context) => ActionField(
    actions: actions,
    value: value,
    title: 'Pick its group',
    noneLabel: 'None (top-level)',
    // Only groups hold anything; not one put away, unless it's there
    // already.
    exclude: {
      ...exclude,
      for (final action in actions)
        if ((!action.isGroup ||
                const {'archived', 'deleted'}.contains(action.status)) &&
            action.id != value)
          ?action.id,
    },
    marker: (action) => ActionIcon(action, size: 18),
    onChanged: onChanged,
    add: switch (addGroup) {
      final addGroup? => (
        noun: 'group',
        icon: Icons.create_new_folder_outlined,
        onAdd: (name) async {
          Future<AddedAction> add(Map<String, Object?> fields) async {
            final added = await addGroup(fields);
            onAdded?.call(added.actions);
            return added;
          }

          final added = await showAddActionSheet<AddedAction>(
            context,
            name: name.isEmpty ? null : name,
            group: true,
            actions: actions,
            save: add,
            addGroup: add,
          );
          return added?.id;
        },
      ),
      null => null,
    },
  );
}

/// [groups] with [added], if they don't have it already.
List<LocationGroup> withGroup(
  List<LocationGroup> groups,
  LocationGroup added,
) => groups.any((g) => g.id == added.id) ? groups : [...groups, added];

InputDecoration _decoration(String label, {String? hint, String? helper}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      border: const OutlineInputBorder(),
      isDense: true,
    );

class _PersonSheet<T> extends StatefulWidget {
  const _PersonSheet({
    required this.name,
    required this.contextText,
    required this.circles,
    required this.save,
  });

  final String? name;
  final String? contextText;
  final List<Circle> circles;
  final Future<T> Function(Map<String, Object?> fields) save;

  @override
  State<_PersonSheet<T>> createState() => _PersonSheetState<T>();
}

class _PersonSheetState<T> extends State<_PersonSheet<T>>
    with _Adding<_PersonSheet<T>, T> {
  late final _name = TextEditingController(text: widget.name);
  late final _context = TextEditingController(text: widget.contextText);
  final _circleIds = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    super.dispose();
  }

  @override
  Future<T> Function(Map<String, Object?> fields) get save => widget.save;

  @override
  bool get complete => _name.text.trim().isNotEmpty;

  @override
  Map<String, Object?> get fields => {
    'name': _name.text.trim(),
    'context': _trimmed(_context.text),
    if (_circleIds.isNotEmpty) 'circles': [..._circleIds],
  };

  @override
  Widget build(BuildContext context) {
    return _Frame(
      title: 'New person',
      saving: saving,
      saveError: saveError,
      onAdd: addable ? add : null,
      onMore: goOn,
      fields: [
        FieldHotkey(
          'N',
          child: TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: _decoration('Name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => add(),
          ),
        ),
        FieldHotkey(
          'C',
          child: TextField(
            controller: _context,
            decoration: _decoration(
              'Context (optional)',
              hint: 'e.g. met at salsa',
              helper: 'What tells them apart from others of the same name.',
            ),
            onSubmitted: (_) => add(),
          ),
        ),
        CirclesField(
          circles: widget.circles,
          picked: [..._circleIds],
          hotkey: 'I',
          onChanged: (ids) => setState(
            () => _circleIds
              ..clear()
              ..addAll(ids),
          ),
        ),
      ],
    );
  }
}

class _LocationSheet<T> extends StatefulWidget {
  const _LocationSheet({
    required this.name,
    required this.hint,
    required this.mapLocation,
    required this.groups,
    required this.save,
    required this.addGroup,
  });

  final String? name;
  final String? hint;
  final String? mapLocation;
  final List<LocationGroup> groups;
  final Future<T> Function(Map<String, Object?> fields) save;
  final Future<LocationGroup> Function(Map<String, Object?> fields)? addGroup;

  @override
  State<_LocationSheet<T>> createState() => _LocationSheetState<T>();
}

class _LocationSheetState<T> extends State<_LocationSheet<T>>
    with _Adding<_LocationSheet<T>, T> {
  late final _name = TextEditingController(text: widget.name);
  late final _hint = TextEditingController(text: widget.hint);
  late final _map = TextEditingController(text: widget.mapLocation);
  late var _groups = widget.groups;
  String? _group;

  @override
  void dispose() {
    _name.dispose();
    _hint.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Future<T> Function(Map<String, Object?> fields) get save => widget.save;

  @override
  bool get complete => _name.text.trim().isNotEmpty;

  @override
  Map<String, Object?> get fields => {
    'name': _name.text.trim(),
    'hint': _trimmed(_hint.text),
    // Only when they're set, so a server without them can still save the
    // rest.
    'map_location': ?_trimmed(_map.text),
    'group_id': ?_group,
  };

  @override
  Widget build(BuildContext context) => _Frame(
    title: 'New location',
    saving: saving,
    saveError: saveError,
    onAdd: addable ? add : null,
    fields: [
      FieldHotkey(
        'N',
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Name', hint: 'e.g. Home'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => add(),
        ),
      ),
      FieldHotkey(
        'H',
        child: TextField(
          controller: _hint,
          minLines: 1,
          maxLines: 3,
          decoration: _decoration(
            'Hint (optional)',
            hint: "Other names, an address: \"the apartment; 'my place'\"",
          ),
        ),
      ),
      FieldHotkey(
        'P',
        child: TextField(
          controller: _map,
          minLines: 1,
          maxLines: 3,
          decoration: _decoration(
            'Map location (optional)',
            hint: 'An address or a link, for events there without one',
          ),
        ),
      ),
      if (_groups.isNotEmpty || widget.addGroup != null)
        FieldHotkey(
          'G',
          child: LocationGroupField(
            label: 'Group (optional)',
            groups: _groups,
            value: _group,
            addGroup: widget.addGroup,
            onAdded: (added) {
              if (mounted) setState(() => _groups = withGroup(_groups, added));
            },
            onChanged: (picked) => setState(() => _group = picked),
          ),
        ),
    ],
  );
}

class _LocationGroupSheet extends StatefulWidget {
  const _LocationGroupSheet({
    required this.name,
    required this.groups,
    required this.save,
  });

  final String? name;
  final List<LocationGroup> groups;
  final Future<LocationGroup> Function(Map<String, Object?> fields) save;

  @override
  State<_LocationGroupSheet> createState() => _LocationGroupSheetState();
}

class _LocationGroupSheetState extends State<_LocationGroupSheet>
    with _Adding<_LocationGroupSheet, LocationGroup> {
  late final _name = TextEditingController(text: widget.name);
  final _note = TextEditingController();
  late var _groups = widget.groups;
  String? _group;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Future<LocationGroup> Function(Map<String, Object?> fields) get save =>
      widget.save;

  @override
  bool get complete => _name.text.trim().isNotEmpty;

  @override
  Map<String, Object?> get fields => {
    'name': _name.text.trim(),
    'note': _trimmed(_note.text),
    'group_id': ?_group,
  };

  @override
  Widget build(BuildContext context) => _Frame(
    title: 'New location group',
    saving: saving,
    saveError: saveError,
    onAdd: addable ? add : null,
    fields: [
      FieldHotkey(
        'N',
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: _decoration('Name', hint: 'e.g. Brooklyn'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => add(),
        ),
      ),
      FieldHotkey(
        'O',
        child: TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: _decoration(
            'Note (optional)',
            hint: 'What it covers: "the blocks around the park"',
          ),
        ),
      ),
      FieldHotkey(
        'I',
        child: LocationGroupField(
          label: 'Inside (optional)',
          groups: _groups,
          value: _group,
          addGroup: widget.save,
          onAdded: (added) {
            if (mounted) setState(() => _groups = withGroup(_groups, added));
          },
          onChanged: (picked) => setState(() => _group = picked),
        ),
      ),
    ],
  );
}

class _ActionSheet<T> extends StatefulWidget {
  const _ActionSheet({
    required this.name,
    required this.parentId,
    required this.group,
    required this.actions,
    required this.save,
    required this.hasMore,
    required this.addGroup,
  });

  final String? name;
  final String? parentId;
  final bool group;
  final List<PlanAction> actions;
  final Future<T> Function(Map<String, Object?> fields) save;
  final bool hasMore;
  final Future<AddedAction> Function(Map<String, Object?> fields)? addGroup;

  @override
  State<_ActionSheet<T>> createState() => _ActionSheetState<T>();
}

class _ActionSheetState<T> extends State<_ActionSheet<T>>
    with _Adding<_ActionSheet<T>, T> {
  late final _name = TextEditingController(text: widget.name);
  final _note = TextEditingController();
  late String? _parentId = widget.parentId;
  late var _actions = widget.actions;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Future<T> Function(Map<String, Object?> fields) get save => widget.save;

  @override
  bool get complete => _name.text.trim().isNotEmpty;

  @override
  Map<String, Object?> get fields => {
    'name': _name.text.trim(),
    'parent_id': _parentId,
    'note': ?_trimmed(_note.text),
    if (widget.group) 'kind': 'group',
  };

  @override
  Widget build(BuildContext context) => _Frame(
    title: widget.group ? 'New group' : 'New action',
    saving: saving,
    saveError: saveError,
    onAdd: addable ? add : null,
    onMore: widget.hasMore ? goOn : null,
    fields: [
      FieldHotkey(
        'N',
        child: TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: _decoration(
            'Name',
            hint: widget.group ? 'e.g. Cooking' : 'e.g. Make tofu',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => add(),
        ),
      ),
      Text('Group', style: Theme.of(context).textTheme.titleSmall),
      FieldHotkey(
        'G',
        child: ActionGroupField(
          actions: _actions,
          value: _parentId,
          addGroup: widget.addGroup,
          onAdded: (actions) {
            if (mounted) setState(() => _actions = actions);
          },
          onChanged: (id) => setState(() => _parentId = id),
        ),
      ),
      FieldHotkey(
        'O',
        child: TextField(
          controller: _note,
          minLines: 1,
          maxLines: 4,
          decoration: _decoration(
            'Note (optional)',
            hint: widget.group ? 'What it covers' : 'What counts as it',
          ),
        ),
      ),
    ],
  );
}
