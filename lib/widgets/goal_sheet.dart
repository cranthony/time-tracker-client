import 'people_picker.dart' show circleNode;
import 'day_picker.dart';
import 'circle_icon.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../models/person.dart';
import '../services/goal_drafts.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import 'color_picker.dart' show priorityColor;
import 'goal_editor.dart' show FormattedField;
import 'goal_fields.dart' show deadlineAt, inheritedPriorityLabel;
import 'goal_icon.dart';
import 'hotkeys.dart';
import 'picker_edits.dart';
import 'picker_sheet.dart';
import 'text_editor.dart';
import 'tree_picker.dart';

/// Asks for a new goal's title and the day it's due (today, to begin
/// with), the goal it goes under (the top level, to begin with), who it's
/// done with and for (no one, to begin with: chips each, at the right of
/// the goal it goes under's, a person picked by a tap, and taken off by a
/// tap on their chip; no one in both), its priority (its parent's, to
/// begin with: a chip beside the goal it goes under's) and its
/// description, in a sheet over the bottom of the screen, and hands its fields -- an active goal's, keyed as the
/// server takes them -- to
/// [keep] itself, before it closes; if [keep] fails, it stays open,
/// saying so, to try again. Adding is off while the goal would break a
/// rule against [goals], every goal there is, saying which. The people
/// come from the [PeopleScope] over [context], as the full page's do;
/// without one, there are no With or For rows.
///
/// Its More button closes it to go on in the full New goal page instead,
/// with what's typed: [MoreGoal]. What's typed is kept in [drafts] as
/// it's typed, until it's added -- so closing the sheet, or the app,
/// loses nothing, and the next sheet carries on with it. Its trash can
/// throws the draft away. Returns what was chosen, or null if dismissed.
/// Calls [onFieldFocused] once its field has focus and has asked for the
/// keyboard, as the New note sheet does.
///
/// Without a draft, it starts with [title] and due on [day], if given.
/// With [addParent], its Under picker can add a goal for it to go under,
/// titled as it's typed there and due on the day this one is, to start
/// with: what [addParent] returns -- the goal added, and every goal there
/// is now (any added over it too), or null if it was called off -- is
/// what it goes under.
Future<GoalSheetResult?> showAddGoalSheet(
  BuildContext context, {
  required Future<void> Function(Map<String, Object?> fields) keep,
  List<Goal> goals = const [],
  GoalDrafts? drafts,
  String? title,
  DateTime? day,
  Future<GoalAdded?> Function(String title, DateTime day)? addParent,
  DateTime Function() now = DateTime.now,
  VoidCallback? onFieldFocused,
}) async {
  _newGoalSheets++;
  try {
    final people = PeopleScope.of(context);
    final memory = PlanMemoryScope.of(context);
    return await showModalBottomSheet<GoalSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GoalSheet(
        keep: keep,
        goals: goals,
        drafts: drafts,
        title: title,
        day: day,
        addParent: addParent,
        people: people,
        memory: memory,
        now: now,
        onFieldFocused: onFieldFocused,
      ),
    );
  } finally {
    _newGoalSheets--;
  }
}

var _newGoalSheets = 0;

/// A goal added from a picker -- a New goal sheet's Under picker, for it
/// to go under, say -- and every goal there is now.
typedef GoalAdded = ({Goal added, List<Goal> goals});

/// Whether a New goal sheet is open, so a hotkey doesn't open another.
bool get newGoalSheetOpen => _newGoalSheets > 0;

sealed class GoalSheetResult {}

/// The goal added: its fields, as handed to the sheet's keep.
final class AddedGoal extends GoalSheetResult {
  AddedGoal(this.fields);
  final Map<String, Object?> fields;
}

/// Go on in the full New goal page, with what's set as it was. The draft
/// is kept till it's saved there.
final class MoreGoal extends GoalSheetResult {
  MoreGoal({
    required this.title,
    required this.deadline,
    this.description,
    this.descriptionFormat,
    this.priority,
    this.parentId,
    this.withWhom = const [],
    this.forWhom = const [],
  });
  final String title;
  final String deadline;
  final String? description;
  final TextFormat? descriptionFormat;

  /// Its own priority; null to inherit its parent's.
  final int? priority;

  /// The goal it goes under; null for the top level.
  final String? parentId;

  /// Who it's done with, and who it's for: people and circles, a plain
  /// circle with its except.
  final List<Named> withWhom;
  final List<Named> forWhom;

  /// Their ids.
  List<String> get withIds => namedIds(withWhom);
  List<String> get forIds => namedIds(forWhom);
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({
    required this.keep,
    required this.goals,
    required this.now,
    this.drafts,
    this.title,
    this.day,
    this.addParent,
    this.people,
    this.memory,
    this.onFieldFocused,
  });

  final Future<void> Function(Map<String, Object?> fields) keep;
  final List<Goal> goals;
  final GoalDrafts? drafts;

  /// What it starts with, without a draft.
  final String? title;
  final DateTime? day;

  /// Adds a goal for it to go under; null for none to be added.
  final Future<GoalAdded?> Function(String title, DateTime day)? addParent;

  /// Where the people to pick from come from; null for none to pick.
  final PeopleRepository? people;

  /// What the app has loaded, if anything: the people, before they're
  /// asked for again.
  final PlanMemory? memory;
  final DateTime Function() now;
  final VoidCallback? onFieldFocused;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final _today = _dayOf(widget.now());

  late final _title = TextEditingController(
    text: widget.drafts?.draft?.title ?? widget.title,
  );

  /// The day it's due; not before today, even for a draft from days ago.
  late DateTime _day = switch (widget.drafts?.draft?.day ?? widget.day) {
    final day? when !day.isBefore(_today) => _dayOf(day),
    _ => _today,
  };

  /// The time on [_day] it's due by; null for its end.
  late TimeOfDay? _time = switch (widget.drafts?.draft?.minuteOfDay) {
    final m? => TimeOfDay(hour: m ~/ 60, minute: m % 60),
    null => null,
  };

  String get _deadline => deadlineAt((day: _day, time: _time));

  late String? _description = widget.drafts?.draft?.description;
  late TextFormat? _descriptionFormat = widget.drafts?.draft?.descriptionFormat;

  /// Its own priority; null to inherit its parent's.
  late int? _priority = widget.drafts?.draft?.priority;

  /// The goal it goes under, if it's still one it can: null for the top
  /// level.
  late String? _parentId = switch (widget.drafts?.draft?.parentId) {
    final id? when _parents.any((g) => g.id == id) => id,
    _ => null,
  };

  /// Who it's done with, and who it's for -- people and circles, a plain
  /// circle with those of its people it leaves out: no one in both.
  late final List<Named> _with = [...?widget.drafts?.draft?.withWhom];
  late final List<Named> _for = [...?widget.drafts?.draft?.forWhom];

  /// Everyone, once they've loaded -- what the app had, till then; null
  /// without that, or with no one to pick from.
  late PeopleList? _people = widget.memory?.people;

  /// Whether there's anyone to pick from.
  bool get _peoplePickable => widget.people != null;

  /// Every goal there is: those it was given, or as they were once one
  /// was added for it to go under.
  late List<Goal> _goals = widget.goals;

  late var _tree = GoalTree(_goals);

  /// What it can go under: the active goals -- it's active itself.
  List<Goal> get _parents => [
    for (final g in _goals)
      if (g.active) g,
  ];

  /// Whether it's being kept, and hasn't been yet: no draft is kept
  /// meanwhile.
  bool _keeping = false;

  /// Why it couldn't be kept, the last time.
  String? _keepError;

  static DateTime _dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

  bool get _drafted => widget.drafts?.draft != null;

  @override
  void initState() {
    super.initState();
    if (widget.onFieldFocused != null) _focus.addListener(_focusChanged);
    _title.addListener(_changed);
    unawaited(_loadPeople());
  }

  /// Loads everyone, to pick from and to name those picked; what the app
  /// had stands, if that fails.
  Future<void> _loadPeople() async {
    final loading = knownPeople(widget.people, widget.memory);
    if (loading == null) return;
    try {
      final people = await loading;
      if (mounted) setState(() => _people = people);
    } catch (e) {
      debugPrint("Couldn't load the people: $e");
    }
  }

  final _focus = FocusNode();

  void _focusChanged() {
    if (!_focus.hasFocus) return;
    _focus.removeListener(_focusChanged);
    // After the field's own listener has asked for the keyboard.
    scheduleMicrotask(widget.onFieldFocused!);
  }

  @override
  void dispose() {
    _focus.dispose();
    _title.dispose();
    super.dispose();
  }

  void _changed() {
    _keepDraft();
    setState(() {});
  }

  /// Keeps what's typed as the draft -- or throws it away once there's no
  /// title to keep.
  void _keepDraft() {
    final drafts = widget.drafts;
    if (drafts == null || _keeping) return;
    if (_title.text.trim().isEmpty) {
      drafts.remove();
    } else {
      drafts.put(
        GoalDraft(
          title: _title.text,
          day: _day,
          minuteOfDay: switch (_time) {
            final t? => t.hour * TimeOfDay.minutesPerHour + t.minute,
            null => null,
          },
          description: _description,
          descriptionFormat: _descriptionFormat,
          priority: _priority,
          parentId: _parentId,
          withWhom: [..._with],
          forWhom: [..._for],
        ),
      );
    }
  }

  void _setDay(DateTime day) {
    setState(() => _day = _dayOf(day));
    _keepDraft();
  }

  void _shift(int days) {
    final next = DateTime(_day.year, _day.month, _day.day + days);
    if (next.isBefore(_today)) return;
    _setDay(next);
  }

  /// Picks the day it's due, and the time on it, if it has one.
  Future<void> _pickDay() async {
    final picked = await showDayTimePicker(
      context,
      initialDate: _day,
      initialTime: _time,
      firstDate: _today,
      lastDate: DateTime(_today.year + 20),
    );
    if (picked == null || !mounted) return;
    _time = picked.time;
    _setDay(picked.day);
  }

  /// Picks the goal it goes under, searching for what's typed as its
  /// title, by any word, selected to type over. With [_GoalSheet.addParent],
  /// a new one can be added, named as it's typed, and picked.
  Future<void> _pickParent() async {
    final parents = _parents;
    final addParent = widget.addParent;
    final picked = await pickNode(
      context,
      title: 'Under',
      nodes: [
        for (final g in byPriority(parents, _tree))
          PickerNode(
            id: g.id,
            label: goalTitle(g),
            parentId: g.parentId,
            path: [..._tree.pathOf(g.id), goalTitle(g)].join(' › '),
            group: parents.any((c) => c.parentId == g.id),
          ),
      ],
      value: _parentId,
      none: 'Top level',
      groupsPickable: true,
      marker: (_) => const GoalIcon(size: 18),
      searchHint: 'Search goals',
      query: _title.text,
      add: addParent == null
          ? null
          : (
              noun: 'goal',
              icon: Icons.add_task,
              onAdd: (name) async {
                final parent = await addParent(name, _day);
                if (parent == null || !mounted) return null;
                final (:added, :goals) = parent;
                setState(() {
                  _goals = [
                    for (final g in goals)
                      if (g.id != added.id) g,
                    added,
                  ];
                  _tree = GoalTree(_goals);
                });
                return added.id;
              },
            ),
    );
    if (picked == null || !mounted) return;
    setState(() => _parentId = picked.id);
    _keepDraft();
  }

  /// Everyone who can be picked: the active people, and anyone picked
  /// already, Self aside -- a goal isn't with or for oneself.
  List<Person> get _pickable => [
    for (final p in _people?.withSelf ?? const <Person>[])
      if (!p.isSelf &&
          (p.active || _ids(_with).contains(p.id) || _ids(_for).contains(p.id)))
        p,
  ];

  /// The circles that can be picked, too: each stands for its people, or
  /// a community for itself.
  List<Circle> get _circles => _people?.circles ?? const <Circle>[];

  static List<String> _ids(List<Named> named) => namedIds(named);

  /// [id]'s name, or the id itself, till they've loaded.
  String _name(String id) => switch (_pickable.where((p) => p.id == id)) {
    final found when found.isNotEmpty => personName(found.first),
    _ => switch (_people?.circle(id)) {
      final c? => circleName(c),
      null => id,
    },
  };

  /// Picks its priority from a menu below [chip]: its parent's, or one
  /// of its own.
  Future<void> _pickPriority(BuildContext chip) async {
    final box = chip.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(chip).context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final picked = await showMenu<int>(
      context: chip,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: -1, child: Text(_inheritLabel)),
        for (final p in const [0, 1, 2, 3])
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                CircleAvatar(radius: 8, backgroundColor: priorityColor(p)),
                const SizedBox(width: 12),
                Text('P$p'),
              ],
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _priority = picked < 0 ? null : picked);
    _keepDraft();
  }

  /// What it has with no priority of its own: its parent's, or the
  /// default at the top level.
  int get _inherited => switch (_parentId) {
    final id? => _tree.priorityOf(id),
    null => defaultGoalPriority,
  };

  String get _inheritLabel =>
      _parentId == null ? '(P$defaultGoalPriority)' : 'Inherit (P$_inherited)';

  /// Picks someone it's done with ([with_]) or for, searching for what's
  /// typed as its title, by any word, selected to type over, as its
  /// parent is picked: one tap adds them. Someone new is added in the
  /// quick New person sheet, named as it's typed, and picked. Picking them
  /// for one takes them off the other, since no one is both.
  Future<void> _pickPerson({required bool with_}) async {
    final (mine, other) = with_ ? (_with, _for) : (_for, _with);
    final circles = {for (final c in _circles) c.id: c};
    final picked = await pickNode(
      context,
      title: with_ ? 'With' : 'For',
      nodes: [
        for (final c in _circles)
          if (!_ids(mine).contains(c.id)) circleNode(c),
        for (final p in _pickable)
          if (!_ids(mine).contains(p.id))
            PickerNode(id: p.id, label: personName(p, context: true)),
      ],
      marker: circles.isEmpty
          ? null
          : (node) => Icon(switch (circles[node.id]) {
              final c? => circleIcon(c.kind, outlined: true),
              null => Icons.person_outline,
            }, size: 20),
      searchHint: circles.isEmpty
          ? 'Search people'
          : 'Search people and circles',
      query: _title.text,
      add: (
        noun: 'person',
        icon: Icons.person_add_alt,
        onAdd: (name) async {
          final added = await editPerson(context, name: name);
          if (added == null) return null;
          // To name their chip.
          await _loadPeople();
          return added.id;
        },
      ),
    );
    final id = picked?.id;
    if (id == null || !mounted) return;
    setState(() {
      other.removeWhere((n) => n.id == id);
      if (!_ids(mine).contains(id)) mine.add(Named(id));
    });
    _keepDraft();
  }

  /// Takes [id] off whichever of with and for they're in.
  void _removePerson(String id) {
    setState(() {
      _with.removeWhere((n) => n.id == id);
      _for.removeWhere((n) => n.id == id);
    });
    _keepDraft();
  }

  /// Picks which of plain circle [circle]'s people [named] leaves out,
  /// among [mine].
  Future<void> _pickExcept(List<Named> mine, Named named, Circle circle) async {
    final except = await pickExcept(
      context,
      circle: circle,
      members: [
        for (final id in circle.memberIds)
          if (id != selfPersonId)
            _pickable.where((p) => p.id == id).firstOrNull ??
                Person(id: id, name: id),
      ],
      except: named.except,
      isWith: identical(mine, _with),
    );
    if (except == null || !mounted) return;
    setState(() {
      final at = mine.indexOf(named);
      if (at >= 0) mine[at] = named.withExcept(except);
    });
    _keepDraft();
  }

  /// Edits its description in [showTextEditor].
  Future<void> _editDescription() async {
    final edited = await showTextEditor(
      context,
      title: 'Description',
      text: _description,
      format: _descriptionFormat,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _description = edited.text.isEmpty ? null : edited.text;
      _descriptionFormat = edited.format;
    });
    _keepDraft();
  }

  /// The new goal's fields, keyed as the server takes them.
  Map<String, Object?> get _fields => {
    'title': _title.text.trim(),
    'deadline': _deadline,
    'status': 'active',
    'parent_id': ?_parentId,
    'description': ?_description,
    if (_description != null) 'description_format': ?_descriptionFormat?.wire,
    'priority': ?_priority,
    if (_with.isNotEmpty) 'with_ids': namedToJson(_with),
    if (_for.isNotEmpty) 'for_ids': namedToJson(_for),
  };

  /// Why it can't be added, besides having no title; null if it can.
  String? get _problem {
    if (_title.text.trim().isEmpty) return null;
    final problems = planned(_goals, [
      GoalCreate(Goal.fromJson({'id': '\u0000new', ..._fields})),
    ], now: widget.now());
    return problems.isEmpty ? null : problems.join(' ');
  }

  bool get _addable =>
      !_keeping && _title.text.trim().isNotEmpty && _problem == null;

  Future<void> _submit() async {
    if (!_addable) return;
    final fields = _fields;
    setState(() {
      _keeping = true;
      _keepError = null;
    });
    try {
      await widget.keep(fields);
    } catch (e) {
      if (mounted) {
        setState(() {
          _keeping = false;
          _keepError = "Couldn't add the goal: $e";
        });
      }
      return;
    }
    await widget.drafts?.remove();
    // Kept, even if the sheet was dismissed meanwhile.
    if (!mounted) return;
    Navigator.of(context).pop(AddedGoal(fields));
  }

  void _more() => Navigator.of(context).pop(
    MoreGoal(
      title: _title.text.trim(),
      deadline: _deadline,
      description: _description,
      descriptionFormat: _descriptionFormat,
      priority: _priority,
      parentId: _parentId,
      withWhom: [..._with],
      forWhom: [..._for],
    ),
  );

  /// Who it's done with ([with_]), or for, as chips: one to add someone,
  /// then one each for those picked, tapped to take them off -- a plain
  /// circle's, tapped to pick which of its people it leaves out.
  List<Widget> _peopleChips({required bool with_}) {
    final ids = with_ ? _with : _for;
    return [
      FieldHotkey(
        with_ ? 'W' : 'R',
        child: ActionChip(
          avatar: const Icon(Icons.person_add_alt_1),
          label: Text(with_ ? 'With' : 'For'),
          tooltip: with_
              ? 'Add who you’ll do it with'
              : 'Add who it’s for, who won’t be part of doing it',
          onPressed: _keeping ? null : () => _pickPerson(with_: with_),
        ),
      ),
      for (final named in ids)
        if (_people?.circle(named.id) case final circle?)
          InputChip(
            avatar: Icon(circleIcon(circle.kind, outlined: true), size: 18),
            label: Text(namedLabel(named, _name)),
            tooltip: circle.isCommunity
                ? 'Take ${_name(named.id)} off'
                : 'Pick who of ${_name(named.id)} it leaves out',
            onPressed: _keeping
                ? null
                : circle.isCommunity
                ? () => _removePerson(named.id)
                : () => _pickExcept(ids, named, circle),
            onDeleted: _keeping ? null : () => _removePerson(named.id),
          )
        else
          InputChip(
            label: Text(_name(named.id)),
            tooltip: 'Take ${_name(named.id)} off',
            onPressed: _keeping ? null : () => _removePerson(named.id),
            onDeleted: _keeping ? null : () => _removePerson(named.id),
          ),
    ];
  }

  /// Throws the draft away, and closes.
  Future<void> _discard() async {
    await widget.drafts?.remove();
    if (mounted) Navigator.of(context).pop();
  }

  static const _dense = VisualDensity(horizontal: -4);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final problem = _problem;
    final strings = MaterialLocalizations.of(context);
    final day = [
      strings.formatMediumDate(_day),
      if (_time case final time?) strings.formatTimeOfDay(time),
    ].join(', ');
    final parent = _tree[_parentId];
    return HotkeyBindings(
      bindings: [
        HotkeyBinding(
          const HotkeyTrigger.ctrl(LogicalKeyboardKey.enter),
          _submit,
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          // Above the keyboard, or else the gesture bar.
          bottom: max(media.viewInsets.bottom, media.viewPadding.bottom) + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('New goal', style: theme.textTheme.titleLarge),
                ),
                if (_drafted)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: theme.colorScheme.error,
                    tooltip: 'Discard draft',
                    onPressed: _keeping ? null : _discard,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FieldHotkey(
              'T',
              child: TextField(
                controller: _title,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'An outcome you can mark done',
                  filled: true,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 8),
            // The parent and its priority at the left, and who it's for,
            // then with, at the right -- under them, where they don't fit
            // beside them.
            _LineOrTwo(
              start: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: FieldHotkey(
                      'U',
                      child: ActionChip(
                        avatar: const GoalIcon(size: 18),
                        label: Text(
                          parent == null
                              ? 'Top level'
                              : 'Under ${[..._tree.pathOf(parent.id), goalTitle(parent)].join(' › ')}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        tooltip: 'The goal it goes under',
                        onPressed: _keeping ? null : _pickParent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FieldHotkey(
                    'P',
                    child: Builder(
                      builder: (chip) => ActionChip(
                        avatar: CircleAvatar(
                          backgroundColor: priorityColor(
                            _priority ?? _inherited,
                          ),
                        ),
                        label: Text(
                          _priority == null ? _inheritLabel : 'P$_priority',
                        ),
                        tooltip: _priority == null
                            ? inheritedPriorityLabel(_tree, _parentId)
                            : 'Its own priority',
                        onPressed: _keeping ? null : () => _pickPriority(chip),
                      ),
                    ),
                  ),
                ],
              ),
              end: _peoplePickable
                  ? Wrap(
                      spacing: 4,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ..._peopleChips(with_: false),
                        ..._peopleChips(with_: true),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            FieldHotkey(
              'S',
              child: FormattedField(
                label: 'Description',
                text: _description,
                format: _descriptionFormat,
                onTap: _editDescription,
              ),
            ),
            for (final error in [?problem, ?_keepError])
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
            Builder(
              builder: (context) {
                // Wraps only where even it alone is too wide for a line.
                final date = Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: 'A day earlier',
                      visualDensity: _dense,
                      onPressed: _day.isAfter(_today) ? () => _shift(-1) : null,
                    ),
                    FieldHotkey(
                      'D',
                      child: ActionChip(
                        avatar: const Icon(Icons.event),
                        label: Text(day),
                        tooltip: _time == null
                            ? 'Due by the end of the day'
                            : 'Due by then',
                        onPressed: _pickDay,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'A day later',
                      visualDensity: _dense,
                      onPressed: () => _shift(1),
                    ),
                    FieldHotkey(
                      'O',
                      child: TextButton(
                        style: TextButton.styleFrom(visualDensity: _dense),
                        onPressed: () => _setDay(_today),
                        child: const Text('Today'),
                      ),
                    ),
                  ],
                );
                final buttons = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FieldHotkey(
                      'M',
                      child: TextButton(
                        onPressed: _keeping ? null : _more,
                        child: const Text('More'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    HotkeyHint(
                      Hotkey.save,
                      child: FilledButton(
                        onPressed: _addable ? _submit : null,
                        child: Text(_keepError == null ? 'Add' : 'Try again'),
                      ),
                    ),
                  ],
                );
                return _LineOrTwo(start: date, end: buttons);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// [start] at the left and [end] at the right of one line, where they fit
/// side by side; where they don't -- on a phone -- [start] on a line of
/// its own, kept together, and [end] under it at the right.
class _LineOrTwo extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _LineOrTwo({required this.start, required this.end});

  final Widget start;
  final Widget end;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.start => start,
    _Slot.end => end,
  };

  @override
  _RenderLineOrTwo createRenderObject(BuildContext context) =>
      _RenderLineOrTwo();
}

enum _Slot { start, end }

class _RenderLineOrTwo extends RenderBox
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  /// Between the lines, when it takes two.
  static const _gap = 4.0;

  RenderBox get _start => childForSlot(_Slot.start)!;
  RenderBox get _end => childForSlot(_Slot.end)!;

  @override
  void performLayout() {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    final start = _start..layout(loose, parentUsesSize: true);
    final end = _end..layout(loose, parentUsesSize: true);
    final width = constraints.maxWidth;
    final startData = start.parentData! as BoxParentData;
    final endData = end.parentData! as BoxParentData;
    if (start.size.width + end.size.width <= width) {
      final height = max(start.size.height, end.size.height);
      startData.offset = Offset(0, (height - start.size.height) / 2);
      endData.offset = Offset(
        width - end.size.width,
        (height - end.size.height) / 2,
      );
      size = constraints.constrain(Size(width, height));
    } else {
      startData.offset = Offset.zero;
      endData.offset = Offset(
        max(0, width - end.size.width),
        start.size.height + _gap,
      );
      size = constraints.constrain(
        Size(width, start.size.height + _gap + end.size.height),
      );
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => max(
    _start.getMinIntrinsicWidth(height),
    _end.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _start.getMaxIntrinsicWidth(height) + _end.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => max(
    _start.getMinIntrinsicHeight(width),
    _end.getMinIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _start.getMaxIntrinsicHeight(width) +
      _gap +
      _end.getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    final start = _start.getDryLayout(loose);
    final end = _end.getDryLayout(loose);
    return constraints.constrain(
      start.width + end.width <= constraints.maxWidth
          ? Size(constraints.maxWidth, max(start.height, end.height))
          : Size(constraints.maxWidth, start.height + _gap + end.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in [_start, _end]) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_end, _start]) {
      final offset = (child.parentData! as BoxParentData).offset;
      if (result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, at) => child.hitTest(result, position: at),
      )) {
        return true;
      }
    }
    return false;
  }
}
