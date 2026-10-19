import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../services/goal_drafts.dart';
import 'hotkeys.dart';

/// Asks for a new goal's title and the day it's due (today, to begin
/// with), in a sheet over the bottom of the screen, and hands its fields
/// -- an active, top-level goal's, keyed as the server takes them -- to
/// [keep] itself, before it closes; if [keep] fails, it stays open,
/// saying so, to try again. Adding is off while the goal would break a
/// rule against [goals], every goal there is, saying which.
///
/// Its More button closes it to go on in the full New goal page instead,
/// with what's typed: [MoreGoal]. What's typed is kept in [drafts] as
/// it's typed, until it's added -- so closing the sheet, or the app,
/// loses nothing, and the next sheet carries on with it. Its trash can
/// throws the draft away. Returns what was chosen, or null if dismissed.
/// Calls [onFieldFocused] once its field has focus and has asked for the
/// keyboard, as the New note sheet does.
Future<GoalSheetResult?> showAddGoalSheet(
  BuildContext context, {
  required Future<void> Function(Map<String, Object?> fields) keep,
  List<Goal> goals = const [],
  GoalDrafts? drafts,
  DateTime Function() now = DateTime.now,
  VoidCallback? onFieldFocused,
}) async {
  _newGoalSheets++;
  try {
    return await showModalBottomSheet<GoalSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GoalSheet(
        keep: keep,
        goals: goals,
        drafts: drafts,
        now: now,
        onFieldFocused: onFieldFocused,
      ),
    );
  } finally {
    _newGoalSheets--;
  }
}

var _newGoalSheets = 0;

/// Whether a New goal sheet is open, so a hotkey doesn't open another.
bool get newGoalSheetOpen => _newGoalSheets > 0;

sealed class GoalSheetResult {}

/// The goal added: its fields, as handed to the sheet's keep.
final class AddedGoal extends GoalSheetResult {
  AddedGoal(this.fields);
  final Map<String, Object?> fields;
}

/// Go on in the full New goal page, with [title] and [deadline] as
/// typed. The draft is kept till it's saved there.
final class MoreGoal extends GoalSheetResult {
  MoreGoal({required this.title, required this.deadline});
  final String title;
  final String deadline;
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({
    required this.keep,
    required this.goals,
    required this.now,
    this.drafts,
    this.onFieldFocused,
  });

  final Future<void> Function(Map<String, Object?> fields) keep;
  final List<Goal> goals;
  final GoalDrafts? drafts;
  final DateTime Function() now;
  final VoidCallback? onFieldFocused;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final _today = _dayOf(widget.now());

  late final _title = TextEditingController(text: widget.drafts?.draft?.title);

  /// The day it's due; not before today, even for a draft from days ago.
  late DateTime _day = switch (widget.drafts?.draft?.day) {
    final day? when !day.isBefore(_today) => _dayOf(day),
    _ => _today,
  };

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
      drafts.put(GoalDraft(title: _title.text, day: _day));
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

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _today,
      lastDate: DateTime(_today.year + 20),
    );
    if (picked == null || !mounted) return;
    _setDay(picked);
  }

  /// The new goal's fields, keyed as the server takes them.
  Map<String, Object?> get _fields => {
    'title': _title.text.trim(),
    'deadline': deadlineOf(_day),
    'status': 'active',
  };

  /// Why it can't be added, besides having no title; null if it can.
  String? get _problem {
    if (_title.text.trim().isEmpty) return null;
    final problems = planned(widget.goals, [
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

  void _more() =>
      Navigator.of(context)
          .pop(MoreGoal(title: _title.text.trim(), deadline: deadlineOf(_day)));

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
    final day = MaterialLocalizations.of(context).formatMediumDate(_day);
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
                        tooltip: 'Due by the end of the day',
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
