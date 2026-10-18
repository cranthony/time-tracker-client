import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/maps.dart';
import '../models/event.dart';
import '../models/facts.dart';
import '../models/goal.dart';
import '../models/plan_action.dart';
import '../models/proposal.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/recurrence.dart';
import '../models/repeat.dart';
import '../models/trait.dart';
import '../services/goals_repository.dart';
import '../services/habits_repository.dart';
import '../services/mcp_client.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'error_sheet.dart';
import 'color_picker.dart';
import 'event_description.dart';
import 'event_dialog.dart' show followThroughOption;
import '../outbox/event_outbox.dart' show allWaiting;
import 'follow_through_dialog.dart' show CalledOff;
import 'hotkeys.dart';
import 'other_events.dart';
import 'waiting_note.dart';
import 'facts_dialog.dart';
import 'goal_flows.dart';
import 'goal_icon.dart';
import 'goal_picker.dart';
import 'picker_sheet.dart';
import 'plow_icon.dart';
import 'properties_dialog.dart' show ConfirmOption, confirmationContent;
import 'recurrence_dialog.dart';
import 'repeat_editor.dart';
import 'share_dialog.dart';

/// What a summary dialog closed with, when it wasn't just closed.
sealed class SummaryOutcome<T> {
  const SummaryOutcome();
}

/// A change was saved; [value] is what the save returned.
final class SummarySaved<T> extends SummaryOutcome<T> {
  const SummarySaved(this.value);

  final T value;
}

/// "Details" was tapped, to see every property.
final class SummaryDetails<T> extends SummaryOutcome<T> {
  const SummaryDetails();
}

/// Shows the properties of [event] one edits most: its priority, summary,
/// times, whether it's part of a series, location, description, whether
/// it's at a fixed time, its actions, and its facets -- what happened at it,
/// for its actions' traits -- edited in a dialog of their own
/// ([showFacetsDialog]).
///
/// Tapping one opens it for editing, in place; "Save" sends every change
/// with [save], as `update_event` takes them. The trash can cancels the
/// event, after asking. Without [save], or for an event with no id,
/// nothing can be edited.
///
/// [actions] are the actions known, by id, to show the event's by name and
/// color; [loadActions] lists them to pick from. In a series, its "Repeats"
/// chip calls [openSeries] with the series' id; if that saved a change
/// (returning true), this closes, returning null. "Details" closes it
/// with [SummaryDetails]. Changing its times keeps them clear of the
/// events in [otherEvents]. What of it's [waiting] for a change to be
/// saved -- its fields, or with [allWaiting], all of it -- can't be
/// changed, and says so. With [repeatable], one that isn't in a series
/// says "No recurrence", which opens to make it the first of one.
Future<SummaryOutcome<List<Event>>?> showEventSummaryDialog(
  BuildContext context,
  Event event, {
  Future<List<Event>> Function(Map<String, Object?> changes)? save,
  Future<List<Event>> Function(bool countsAgainstFollowThrough)? cancel,
  OtherEvents otherEvents = const OtherEvents.none(),
  Map<String, PlanAction> actions = const {},
  Future<List<PlanAction>> Function()? loadActions,
  Future<bool> Function(String seriesId)? openSeries,
  List<ProposalAddition> additions = const [],
  Set<String> waiting = const {},
  bool repeatable = false,
}) {
  final seriesId = event.properties['recurring_event_id'] as String?;
  final day = MaterialLocalizations.of(context).formatMediumDate(event.start);
  final summary = switch (event.summary) {
    final s? when s.isNotEmpty => '"$s"',
    _ => 'This event',
  };
  return showDialog<SummaryOutcome<List<Event>>>(
    context: context,
    builder: (_) => _SummaryDialog<List<Event>>(
      values: {
        ...event.properties,
        'summary': event.summary,
        'start': localIsoTimestamp(event.start),
        'end': localIsoTimestamp(event.end),
        // One waiting to be saved, making it a series.
        'repeat': switch (event.properties['repeat']) {
          final Map repeat => Repeat.fromJson(repeat.cast()),
          _ => null,
        },
      },
      actions: actions,
      loadActions: loadActions,
      otherEvents: otherEvents,
      whoWhere: true,
      facets: true,
      repeatable: repeatable && seriesId == null,
      save: save == null || event.id == null
          ? null
          : (changes) async =>
                () => save(_encoded(changes)),
      remove: cancel == null || event.id == null || event.isCancelled
          ? null
          : _Removal(
              tooltip: 'Cancel event',
              question: 'Cancel this event?',
              explanation:
                  '$summary on $day leaves the list.'
                  '${seriesId == null ? '' : ' The rest of the series stays.'}'
                  " This can't be undone.",
              keepLabel: 'Keep event',
              label: 'Cancel event',
              option: followThroughOption,
              run: cancel,
            ),
      openSeries: switch ((openSeries, seriesId)) {
        (final open?, final id?) => () => open(id),
        _ => null,
      },
      additions: additions,
      waiting: waiting,
    ),
  );
}

/// Shows a new event, from [start] to [end], as [showEventSummaryDialog]
/// shows one -- who it's with and for, where it is, and its notes among
/// the rest -- blank but for its times, with its summary open to type.
/// "Create", once it has a summary, sends it with [create], as
/// `create_event` takes it. Returns what [create] returned (the events the
/// server changed), or null if it was called off. Its times are kept
/// clear of the events in [otherEvents]. With [clear], a trash can at its
/// top right offers to make no new event, but just clear the time --
/// asking first. With [repeatable], it says "No recurrence", which opens
/// to make it the first event of a series.
Future<List<Event>?> showNewEventDialog(
  BuildContext context, {
  required DateTime start,
  required DateTime end,
  OtherEvents otherEvents = const OtherEvents.none(),
  required Future<List<Event>> Function(Map<String, Object?> fields) create,
  ClearTime? clear,
  Map<String, PlanAction> actions = const {},
  Future<List<PlanAction>> Function()? loadActions,
  List<ProposalAddition> additions = const [],
  Map<String, Object?> initial = const {},
  bool repeatable = false,
}) async {
  final values = {
    ...initial,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
  };
  final outcome = await showDialog<SummaryOutcome<List<Event>>>(
    context: context,
    builder: (_) => _SummaryDialog<List<Event>>(
      values: values,
      creating: true,
      otherEvents: otherEvents,
      actions: actions,
      loadActions: loadActions,
      // As an event's: who and where, from its facts, and its notes.
      whoWhere: true,
      facets: true,
      repeatable: repeatable,
      additions: additions,
      save: (changes) async =>
          () => create(_encoded({...values, ...changes})),
      remove: switch (clear) {
        final clear? => _Removal(
          tooltip: 'Clear this time instead',
          question: clear.question,
          explanation: clear.explanation,
          keepLabel: 'Keep them',
          label: clear.label,
          run: (_) => clear.run(),
        ),
        null => null,
      },
    ),
  );
  return switch (outcome) {
    SummarySaved(:final value) => value,
    _ => null,
  };
}

/// Shows the recurring series [recurrence] as [showEventSummaryDialog]
/// shows an event, with how it repeats under its summary, and its first
/// event's times. Who its events are with and for, and where, are picked
/// as an event's are; what happened is left to each event.
///
/// "Save" first asks whether the change is for every event in the series
/// or [fromEventId] and those after it, then sends it with [save]. With
/// [delete], the trash can deletes [fromEventId] and the events after it,
/// after asking (see [EventsRepository.deleteRecurrence] for why never the
/// whole series); [fromEventStart] says which event that is.
Future<SummaryOutcome<List<Recurrence>>?> showSeriesSummaryDialog(
  BuildContext context,
  Recurrence recurrence, {
  required Future<List<Recurrence>> Function(
    Map<String, Object?> changes,
    SeriesScope scope,
  )
  save,
  required String fromEventId,
  required DateTime fromEventStart,
  Future<List<Recurrence>> Function()? delete,
  Map<String, PlanAction> actions = const {},
  Future<List<PlanAction>> Function()? loadActions,
}) {
  final day = MaterialLocalizations.of(context)
      .formatMediumDate(fromEventStart);
  return showDialog<SummaryOutcome<List<Recurrence>>>(
    context: context,
    builder: (_) => _SummaryDialog<List<Recurrence>>(
      values: {
        ...recurrence.properties,
        'summary': recurrence.summary,
        'start': localIsoTimestamp(recurrence.start),
        'end': localIsoTimestamp(recurrence.end),
        'repeat': recurrence.repeat,
        'schedule': recurrence.schedule,
      },
      series: true,
      whoWhere: true,
      actions: actions,
      loadActions: loadActions,
      save: (changes) async {
        final scope = await askSeriesScope(context, changes);
        if (scope == null) return null;
        return () => save(_encoded(changes), scope);
      },
      remove: switch (delete) {
        // Always this and following, never the whole series: see
        // EventsRepository.deleteRecurrence.
        final delete? => _Removal(
          tooltip: 'Delete this and following events',
          question: 'Delete this and following events?',
          explanation:
              'The event on $day and every one after it in the series are '
              "deleted. Earlier ones stay as they are. This can't be undone.",
          keepLabel: 'Keep events',
          label: 'Delete events',
          run: (_) => delete(),
        ),
        null => null,
      },
    ),
  );
}

/// [changes] as the server takes them: a [Repeat] as its JSON.
Map<String, Object?> _encoded(Map<String, Object?> changes) => {
  for (final MapEntry(:key, :value) in changes.entries)
    key: value is Repeat ? value.toJson() : value,
};

/// The trash can's action: what it asks, and [run]s once confirmed --
/// with whether [option], if it offers one, was switched on.
/// What a new event's trash can does instead of making it: clear the
/// time, with [run], once [question] is answered with [label].
typedef ClearTime = ({
  String question,
  String explanation,
  String label,
  Future<List<Event>> Function() run,
});

class _Removal {
  const _Removal({
    required this.tooltip,
    required this.question,
    required this.explanation,
    required this.keepLabel,
    required this.label,
    required this.run,
    this.option,
  });

  final String tooltip;
  final String question;
  final String explanation;
  final String keepLabel;
  final String label;
  final ConfirmOption? option;
  final Future<Object?> Function(bool option) run;
}

/// The properties the dialog edits, one at a time.
enum _Field { priority, commute, summary, time, repeat, location, description }

/// The priorities offered as chips; "Other" takes any other.
const _priorities = [0, 1, 2, 3];

class _SummaryDialog<T> extends StatefulWidget {
  const _SummaryDialog({
    required this.values,
    required this.actions,
    required this.loadActions,
    required this.save,
    required this.remove,
    this.series = false,
    this.creating = false,
    this.otherEvents = const OtherEvents.none(),
    this.openSeries,
    this.whoWhere = false,
    this.facets = false,
    this.additions = const [],
    this.waiting = const {},
    this.repeatable = false,
  });

  /// What of it waits for a change to be saved, and so can't change; see
  /// [waitsFor].
  final Set<String> waiting;

  /// As the server sent them, with times in local time, and a series'
  /// repeat as a [Repeat].
  final Map<String, Object?> values;
  final Map<String, PlanAction> actions;
  final Future<List<PlanAction>> Function()? loadActions;

  /// Asks anything saving the changes needs, then gives what saves them;
  /// null if that was called off, keeping it open.
  final Future<Future<T> Function()?> Function(Map<String, Object?> changes)?
  save;
  final _Removal? remove;

  /// Whether it's a series, rather than an event.
  final bool series;

  /// Whether it's an event that isn't in a series, but can be made the
  /// first of one: "No recurrence" opens to say how it repeats, sent as
  /// its `repeat`.
  final bool repeatable;

  /// Whether it's a new event, not yet on the server: it opens with its
  /// summary to type, and "Create" sends it once it has one.
  final bool creating;

  /// The other events its times are kept clear of.
  final OtherEvents otherEvents;
  final Future<bool> Function()? openSeries;

  /// Whether it shows who it's with and for, and where, from its facts,
  /// rather than its location as it's put: an event's, or a series'.
  final bool whoWhere;

  /// Whether it shows its facets -- what happened at it: an event's, not
  /// a series'.
  final bool facets;

  /// The people and locations a compaction proposal adds, which its
  /// facts may name by their refs ("new:priya").
  final List<ProposalAddition> additions;

  @override
  State<_SummaryDialog<T>> createState() => _SummaryDialogState<T>();
}

class _SummaryDialogState<T> extends State<_SummaryDialog<T>> {
  /// What's been changed, keyed as the server takes it; null clears.
  final _changes = <String, Object?>{};

  _Field? _editing;
  final _text = TextEditingController();

  /// Whether "Other" was picked, to type a priority not among
  /// [_priorities].
  bool _otherPriority = false;

  late Future<List<PlanAction>>? _actionList = _loadActions();

  Future<List<PlanAction>>? _loadActions() =>
      widget.loadActions?.call()?..then((list) {
        if (mounted) setState(() => _actionsLoaded = list);
      }, onError: (Object _) {});

  /// The action [id], as last loaded, or as the page had it.
  PlanAction? _action(String id) =>
      _actionsLoaded?.where((a) => a.id == id).firstOrNull ??
      widget.actions[id];

  /// [_actionList], once it's in: the picker is drawn from it at once,
  /// rather than waiting a frame on a future that's done.
  List<PlanAction>? _actionsLoaded;

  /// Everyone's names, once the [PeopleScope] has them, for who it was
  /// with and for; the locations', for where; and the traits', from the
  /// [TraitsScope], for its judgments.
  Map<String?, String> _personNames = {selfPersonId: defaultSelf.name};
  Map<String?, String> _locationNames = const {};

  /// Each location's map location, by id, where it has one.
  Map<String, String> _locationMaps = const {};
  Map<String?, String> _traitNames = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPeople();
  }

  bool _peopleAsked = false;

  Future<void> _loadPeople() async {
    if (_peopleAsked) return;
    _peopleAsked = true;
    final repository = PeopleScope.of(context);
    final traits = TraitsScope.of(context);
    // What the Events page loaded already, at once; then what's loading,
    // or else afresh.
    if (PlanMemoryScope.of(context) case final memory?) {
      _named(memory.people, memory.locations, memory.traits);
      await memory.prefetchNames(
        traits: traits,
        people: repository,
        habits: HabitsScope.of(context),
        onLoaded: () {
          if (mounted) {
            setState(
              () => _named(memory.people, memory.locations, memory.traits),
            );
          }
        },
      );
      return;
    }
    try {
      final people = await repository?.people();
      final locations = await repository?.locations();
      final traitList = await traits?.traits(
        statuses: const ['active', 'off', 'archived'],
      );
      if (!mounted) return;
      setState(() => _named(people, locations, traitList));
    } catch (_) {
      // Named by id, then.
    }
  }

  /// Names everyone, every location and every trait in [people],
  /// [locations] and [traits], where they're known.
  void _named(
    PeopleList? people,
    List<Location>? locations,
    List<Trait>? traits,
  ) {
    if (people != null) {
      _personNames = {for (final p in people.withSelf) p.id: personName(p)};
    }
    if (locations != null) {
      _locationNames = {for (final l in locations) l.id: l.name};
      _locationMaps = {for (final l in locations) l.id: ?l.mapLocation};
    }
    // What a proposal adds, by ref, until it's made.
    for (final a in widget.additions) {
      final named = '${a.name} (new)';
      switch (a.kind) {
        case AdditionKind.person:
          _personNames = {..._personNames, a.ref: named};
        case AdditionKind.location:
          _locationNames = {..._locationNames, a.ref: named};
        case AdditionKind.action:
      }
    }
    if (traits != null) {
      _traitNames = {for (final t in traits) t.id: t.name};
    }
  }

  bool _saving = false;
  String? _error;

  bool get _editable => widget.save != null && !widget.waiting.contains('*');

  /// Whether [key] waits for a change to be saved.
  bool _waits(String key) => waitsFor(widget.waiting, key);

  @override
  void initState() {
    super.initState();
    if (widget.creating) {
      _editing = _Field.summary;
      // One it starts with, to change.
      _text.text = '${_value('summary') ?? ''}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Object? _value(String key) =>
      _changes.containsKey(key) ? _changes[key] : widget.values[key];

  /// Sets [key] to [value], dropping the change if that's how it was.
  void _set(String key, Object? value) => setState(() {
    if (_same(value, widget.values[key])) {
      _changes.remove(key);
    } else {
      _changes[key] = value;
    }
  });

  static bool _same(Object? a, Object? b) => switch ((a, b)) {
    (final String a, final String b)
        when DateTime.tryParse(a) != null && DateTime.tryParse(b) != null =>
      DateTime.parse(a).isAtSameMomentAs(DateTime.parse(b)),
    (final List a, final List b) => jsonEncode(a) == jsonEncode(b),
    (null, '') || ('', null) => true,
    _ => a == b,
  };

  void _open(_Field field) => setState(() {
    _editing = _editing == field ? null : field;
    _text.text = switch (field) {
      _Field.summary => '${_value('summary') ?? ''}',
      _Field.location => '${_value('location') ?? ''}',
      _Field.description => '${_value('description') ?? ''}',
      _Field.priority => switch (_value('priority')) {
        final int p when !_priorities.contains(p) => '$p',
        _ => '',
      },
      _ => '',
    };
    _otherPriority = false;
  });

  DateTime _time(String key) => DateTime.parse(_value(key) as String).toLocal();

  Future<void> _save() async {
    final start = _time('start');
    final end = _time('end');
    if (!end.isAfter(start)) {
      setState(() => _error = 'The end has to be after the start.');
      return;
    }
    // Overlaps it had already are left alone.
    final moved =
        widget.creating ||
        _changes.containsKey('start') ||
        _changes.containsKey('end');
    if (widget.otherEvents.overlapping(start, end) case final other?
        when moved) {
      setState(() => _error = 'It would overlap ${_describe(other)}.');
      return;
    }
    // A change shortening it is refused while its goals' or actions'
    // minutes don't fit: the server would cut them down when it's read.
    final minutes = end.difference(start).inMinutes;
    final problems = [
      if (moved || _changes.containsKey('goals'))
        ...shareProblems(_goalShares, minutes),
      if (moved || _changes.containsKey('action_ids'))
        ...shareProblems(_actionShares, minutes, kind: 'action'),
    ];
    if (problems.isNotEmpty) {
      setState(() => _error = problems.join(' '));
      return;
    }
    final save = await widget.save!(Map.of(_changes));
    if (save != null && mounted) await _run(save);
  }

  /// Runs [action], closing with what it returns, or showing why it
  /// failed.
  Future<void> _run(Future<Object?> Function() action) async {
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await action();
      navigator.pop(SummarySaved<T>(saved as T));
    } on CalledOff {
      // Kept open, as it was.
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        message: e is SignInRequiredException
            ? 'You were signed out. Sign in again from the Events page, then '
                  'try again.'
            : null,
        onRetry: () => _run(action),
      );
    }
  }

  Future<void> _confirmRemove(_Removal removal) async {
    var on = removal.option?.initial ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(removal.question),
          content: confirmationContent(
            removal.explanation,
            removal.option,
            on: on,
            toggle: (value) => setState(() => on = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(removal.keepLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(removal.label),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) await _run(() => removal.run(on));
  }

  /// Whether [key] can be changed now, tapped or by its hotkey.
  bool _canEdit(String key) => _editable && !_saving && !_waits(key);

  /// S: opens the summary, its text selected, to type over.
  void _selectSummary() {
    if (!_canEdit('summary')) return;
    if (_editing != _Field.summary) _open(_Field.summary);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
  }

  /// L: where it is -- picked, from its facts, or typed.
  void _openWhere() {
    if (widget.whoWhere) {
      if (_canEdit('facts')) _pickWho(where: true);
    } else if (_canEdit('location') && _editing != _Field.location) {
      _open(_Field.location);
    }
  }

  /// Ctrl+Enter: saves, or creates, as its button does, once it can.
  void _saveByKey() {
    if (_saving) return;
    if (widget.creating) {
      if ((_value('summary') as String? ?? '').trim().isNotEmpty) _save();
    } else if (_changes.isNotEmpty) {
      _save();
    }
  }

  /// Its hotkeys: Tab and Shift+Tab between its parts, Enter opening the one
  /// highlighted; a letter for each part, and Delete for the trash can.
  /// Ctrl+Enter and Esc save and discard ([SaveOrDiscard]).
  List<HotkeyBinding> get _hotkeys => [
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyW), () {
      if (widget.whoWhere && _canEdit('facts')) _pickWho();
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyL), _openWhere),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyD), () {
      if (_canEdit('description')) _editDescription();
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyA), () {
      if (_canEdit('action_ids')) _pickActions?.call();
    }),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyS),
      _selectSummary,
    ),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyP), () {
      if (_canEdit('priority')) _open(_Field.priority);
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyC), () {
      if (widget.facets && _canEdit('facts')) _open(_Field.commute);
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyT), () {
      if (_canEdit('start')) _open(_Field.time);
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyR), () {
      if ((widget.series || widget.repeatable) && _canEdit('repeat')) {
        _openRepeat();
      }
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyN), () {
      if (widget.facets && _canEdit('facts')) _editNotes();
    }),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.delete), () {
      if (widget.remove case final remove? when _editable && !_saving) {
        _confirmRemove(remove);
      }
    }),
  ];

  @override
  Widget build(BuildContext context) => SaveOrDiscard(
    changed: () => _changes.isNotEmpty,
    onSave: _saveByKey,
    onDiscard: () {
      if (!_saving) Navigator.of(context).pop();
    },
    // Out of the summary's field first, for its letters.
    escLeavesFields: true,
    more: _hotkeys,
    child: _dialog(context),
  );

  Widget _dialog(BuildContext context) {
    final theme = Theme.of(context);
    final changed = _changes.isNotEmpty;
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error case final error?)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    "Couldn't save. $error",
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              if (widget.waiting.isNotEmpty)
                WaitingNote(waiting: widget.waiting),
              _topRow(context),
              if (_editing == _Field.priority) _priorityEditor(context),
              if (_editing == _Field.commute) _commuteEditor(),
              _summary(context),
              HotkeyHint(Hotkey.time, child: _timeLine(context)),
              if (widget.series || widget.repeatable)
                HotkeyHint(Hotkey.repeat, child: _repeatLine(context)),
              if (widget.openSeries case final open?) _seriesChip(open),
              const SizedBox(height: 8),
              // Its who, and its location; a new event's, where, as it's
              // put.
              if (widget.whoWhere) ...[
                _whoRow(context),
                _whoRow(context, where: true),
              ] else
                _textRow(
                  context,
                  field: _Field.location,
                  key: 'location',
                  icon: Icons.place_outlined,
                  hint: 'Add location',
                  hotkey: Hotkey.location,
                ),
              _descriptionRow(context),
              _actionsRow(context),
              if (GoalsScope.of(context) != null) _goalsRow(context),
              if (widget.facets) _factsRow(context),
            ],
          ),
        ),
      ),
      actions: widget.creating
          ? [
              HotkeyHint(
                Hotkey.discard,
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              HotkeyHint(
                Hotkey.save,
                child: FilledButton(
                  // Every event has a summary.
                  onPressed:
                      _saving ||
                          (_value('summary') as String? ?? '').trim().isEmpty
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ),
            ]
          : changed
          ? [
              HotkeyHint(
                Hotkey.discard,
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              HotkeyHint(
                Hotkey.save,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(SummaryDetails<T>()),
                child: const Text('Details'),
              ),
              HotkeyHint(
                Hotkey.discard,
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
    );
  }

  /// A dot saying [key] was changed, if it was.
  Widget? _changedDot(String key, {bool? changed}) =>
      changed ?? _changes.containsKey(key)
      ? Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Tooltip(
            message: 'Changed',
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        )
      : null;

  /// The priority chip, an event's commute chip, a series' "Series", and
  /// the trash can.
  Widget _topRow(BuildContext context) {
    final theme = Theme.of(context);
    final own = _value('priority') as int?;
    // Its actions' priority, while its own isn't set or changed.
    final fromActions = _changes.containsKey('priority')
        ? null
        : widget.values['effective_priority'] as int?;
    final shown = own ?? fromActions;
    // Neither its own nor its actions': not a priority's color.
    final color = shown == null
        ? theme.colorScheme.outline
        : priorityColor(shown);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // Filled when it's its own; outlined when it's its actions'.
        color: own == null ? null : color,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        switch (shown) {
          final p? => 'P$p',
          // Cleared, and so to follow its actions' once saved.
          null when _changes.containsKey('priority') => 'From actions',
          null => 'No priority',
        },
        style: theme.textTheme.labelLarge?.copyWith(
          color: own == null ? theme.colorScheme.onSurface : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Row(
      children: [
        // Wrapping to a second line when they don't fit beside the trash.
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: own == null && shown != null
                        ? "Priority, from its actions"
                        : 'Priority',
                    child: InkWell(
                      onTap: _editable && !_saving && !_waits('priority')
                          ? () => _open(_Field.priority)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: HotkeyHint(Hotkey.priority, child: chip),
                      ),
                    ),
                  ),
                  ?_changedDot('priority'),
                ],
              ),
              if (widget.facets) ...[
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HotkeyHint(Hotkey.commute, child: _commuteChip(context)),
                    ?_changedDot(
                      'facts',
                      changed: _commute != _factsWere.commute,
                    ),
                  ],
                ),
              ],
              if (widget.series)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    'Series',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.remove case final remove? when _editable)
          HotkeyHint(
            Hotkey.deleteEvent,
            child: IconButton(
              tooltip: remove.tooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : () => _confirmRemove(remove),
            ),
          ),
      ],
    );
  }

  /// Whether it's a commute, as it'll be saved.
  bool get _commute => Facts.fromJson(_value('facts'))?.commute ?? false;

  Facts get _factsWere =>
      Facts.fromJson(widget.values['facts']) ?? const Facts();

  /// Whether its facts were changed, besides whether it's a commute, which
  /// its chip shows.
  bool get _factsChanged =>
      _changes.containsKey('facts') &&
      (Facts.fromJson(_changes['facts']) ?? const Facts()).withCommute(
            _factsWere.commute,
          ) !=
          _factsWere;

  /// "Commute": filled when it's one, outlined and faded when it's not;
  /// tapped, it opens its switch.
  Widget _commuteChip(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final on = _commute;
    final color = on ? colors.onSecondaryContainer : colors.outline;
    return Tooltip(
      message: on ? 'Part of a commute' : 'Not part of a commute',
      child: InkWell(
        onTap: _editable && !_saving && !_waits('facts')
            ? () => _open(_Field.commute)
            : null,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: on ? colors.secondaryContainer : null,
              border: Border.all(
                color: on ? colors.secondaryContainer : colors.outlineVariant,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_walk, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  'Commute',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commuteEditor() => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: const Text('This event is part of a commute'),
    value: _commute,
    onChanged: (on) => _setFacts(
      (Facts.fromJson(_value('facts')) ?? const Facts()).withCommute(on),
    ),
  );

  Widget _priorityEditor(BuildContext context) {
    final own = _value('priority') as int?;
    final other = _otherPriority || (own != null && !_priorities.contains(own));
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in _priorities)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text('P$p'),
                  selected: own == p && !other,
                  onSelected: (_) {
                    _otherPriority = false;
                    _set('priority', p);
                  },
                ),
              ChoiceChip(
                showCheckmark: false,
                label: const Text('Other'),
                selected: other,
                onSelected: (_) => setState(() => _otherPriority = true),
              ),
              ChoiceChip(
                showCheckmark: false,
                label: const Text('From its actions'),
                selected: own == null && !other,
                onSelected: (_) {
                  _otherPriority = false;
                  _set('priority', null);
                },
              ),
            ],
          ),
          if (other)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _text,
                autofocus: _text.text.isEmpty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  isDense: true,
                ),
                onChanged: (typed) {
                  if (int.tryParse(typed.trim()) case final p?) {
                    _set('priority', p);
                  }
                },
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '0 is the most important.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    if (_editing == _Field.summary) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: _text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleLarge,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Summary',
          ),
          onChanged: (typed) =>
              // Every event has a summary: one emptied is kept as it was.
              typed.trim().isEmpty
              ? setState(() => _changes.remove('summary'))
              : _set('summary', typed.trim()),
          onSubmitted: (_) => setState(() => _editing = null),
        ),
      );
    }
    final summary = _value('summary') as String?;
    return HotkeyHint(Hotkey.summary, child: _summaryLine(theme, summary));
  }

  Widget _summaryLine(ThemeData theme, String? summary) {
    return InkWell(
      onTap: _editable && !_saving && !_waits('summary')
          ? () => _open(_Field.summary)
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
        child: Row(
          children: [
            Flexible(
              child: Text(
                summary == null || summary.isEmpty ? '(no summary)' : summary,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            ?_changedDot('summary'),
          ],
        ),
      ),
    );
  }

  /// The times on one short line, opening to pick them; for a series, its
  /// first event's.
  Widget _timeLine(BuildContext context) {
    final theme = Theme.of(context);
    final strings = MaterialLocalizations.of(context);
    final start = _time('start');
    final end = _time('end');
    String time(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final shown = widget.series
        ? sameDay
              ? '${time(start)} – ${time(end)} · from '
                    '${strings.formatMediumDate(start)}'
              : '${time(start)} – ${strings.formatMediumDate(end)}, '
                    '${time(end)} · from ${strings.formatMediumDate(start)}'
        : sameDay
        ? '${strings.formatMediumDate(start)} · ${time(start)} – ${time(end)}'
        : '${strings.formatMediumDate(start)}, ${time(start)} – '
              '${strings.formatMediumDate(end)}, ${time(end)}';
    final editing = _editing == _Field.time;
    final line = InkWell(
      onTap: _editable && !_saving && !_waits('start')
          ? () => _open(_Field.time)
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              size: 18,
              color: editing
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                shown,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: editing
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?(_changedDot('start') ?? _changedDot('end')),
          ],
        ),
      ),
    );
    if (!editing) return line;
    return _EditingFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line,
          _timePicker(context, 'Start', 'start'),
          _timePicker(context, 'End', 'end'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              [
                if (widget.series) "The series' first event.",
                'Changing the start keeps its length; − and + take a '
                    'quarter hour off or add one.',
                ?_room(start, end),
              ].join(' '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The free time either side of it, between the events before and
  /// after, if there are any.
  String? _room(DateTime start, DateTime end) {
    final strings = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    final earliest = widget.otherEvents.earliestStart(start);
    final latest = widget.otherEvents.latestEnd(end);
    return switch ((earliest, latest)) {
      (final from?, final to?) =>
        'Free from ${time(from)} to ${time(to)}, between the events '
            'either side.',
      (final from?, null) => 'Free from ${time(from)}, after the event before.',
      (null, final to?) =>
        'Free until ${time(to)}, when the next event starts.',
      (null, null) => null,
    };
  }

  /// [label], then [key]'s date and time to pick, with − and + either
  /// side of the time to move it a quarter hour (see [OtherEvents]).
  Widget _timePicker(BuildContext context, String label, String key) {
    final strings = MaterialLocalizations.of(context);
    final current = _time(key);
    final start = _time('start');
    final end = _time('end');
    final others = widget.otherEvents;
    final (earlier, later) = key == 'start'
        ? (others.earlierStart(start), others.laterStart(start, end))
        : (others.earlierEnd(start, end), others.laterEnd(end));
    void move(DateTime to) =>
        key == 'start' ? _setTimes(to, end) : _setTimes(start, to);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(label)),
          Flexible(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.calendar_today),
                  label: Text(strings.formatMediumDate(current)),
                  onPressed: () => _pickDate(key),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: '$label 15 min earlier',
                      visualDensity: VisualDensity.compact,
                      onPressed: earlier == null ? null : () => move(earlier),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.schedule),
                      label: Text(
                        strings.formatTimeOfDay(
                          TimeOfDay.fromDateTime(current),
                        ),
                      ),
                      onPressed: () => _pickTime(key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: '$label 15 min later',
                      visualDensity: VisualDensity.compact,
                      onPressed: later == null ? null : () => move(later),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [other] by its summary and times, for saying it's in the way.
  String _describe(Event other) {
    final strings = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    final name = switch (other.summary) {
      final s? when s.isNotEmpty => '"$s"',
      _ => 'another event',
    };
    return '$name, ${time(other.start)} – ${time(other.end)}';
  }

  /// Sets [key]'s time to [time], picked; a new start moves the end with
  /// it, so the length stays as it was. Either is kept clear of the
  /// events in the way: a start inside one moves to its end, and an end
  /// past the next one's start comes back to it.
  void _setTime(String key, DateTime time) {
    final start = _time('start');
    final end = _time('end');
    final DateTime newStart;
    final DateTime newEnd;
    if (key == 'start') {
      (newStart, newEnd) = widget.otherEvents.moveStart(
        time,
        end.difference(start),
      );
    } else {
      newStart = start;
      newEnd = time.isAfter(start)
          ? widget.otherEvents.fitEnd(start, time)
          : time;
    }
    _setTimes(newStart, newEnd);
  }

  void _setTimes(DateTime start, DateTime end) {
    _set('start', localIsoTimestamp(start));
    _set('end', localIsoTimestamp(end));
    setState(() => _error = null);
  }

  Future<void> _pickDate(String key) async {
    final current = _time(key);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _setTime(
      key,
      DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      ),
    );
  }

  Future<void> _pickTime(String key) async {
    final current = _time(key);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    _setTime(
      key,
      DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  /// A series' schedule in words, opening to change it; one made
  /// elsewhere that the app can't say is shown, but can't be changed. An
  /// event that can be made a series says "No recurrence", which opens to
  /// repeat it weekly, to change -- or, with "Don't repeat", not.
  Widget _repeatLine(BuildContext context) {
    final theme = Theme.of(context);
    final repeat = _value('repeat') as Repeat?;
    final adding = widget.repeatable;
    final schedule = adding
        ? switch (repeat) {
            final repeat? => _onItsDay(repeat).describe(),
            null => 'No recurrence',
          }
        : _changes.containsKey('repeat')
        ? repeat?.describe()
        : widget.values['schedule'] as String? ?? repeat?.describe();
    final editing = _editing == _Field.repeat;
    final color = editing
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final line = InkWell(
      onTap:
          !_editable ||
              _saving ||
              _waits('repeat') ||
              (!adding && repeat == null)
          ? null
          : _openRepeat,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.repeat, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule ?? 'Repeats',
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                  if (repeat == null && !adding)
                    Text(
                      "Made elsewhere, in a way the app can't change.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ?_changedDot('repeat'),
          ],
        ),
      ),
    );
    if (!editing || repeat == null) return line;
    return _EditingFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line,
          const SizedBox(height: 4),
          RepeatEditor(
            repeat: repeat,
            firstStart: _time('start'),
            onChanged: (repeat) => _set('repeat', repeat),
          ),
          if (adding)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.close),
                label: const Text("Don't repeat"),
                onPressed: () {
                  _set('repeat', null);
                  setState(() => _editing = null);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// [repeat], weekly without its weekdays, on the day it starts: as it
  /// will repeat, to say so.
  Repeat _onItsDay(Repeat repeat) =>
      repeat.every == 'week' && repeat.weekdays == null
      ? repeat.copyWith(weekdays: [Repeat.weekdayOf(_time('start'))])
      : repeat;

  Widget _seriesChip(Future<bool> Function() open) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ActionChip(
        avatar: const Icon(Icons.repeat),
        label: const Text('Repeats · see series'),
        visualDensity: VisualDensity.compact,
        onPressed: _saving
            ? null
            : () async {
                final navigator = Navigator.of(context);
                if (await open() && mounted) navigator.pop();
              },
      ),
    ),
  );

  /// One property after its [icon] -- or a [glyph] drawn in its place --
  /// tapped to edit or toggle it. A [trailing] button, at its end, has
  /// the first line's height and the row's padding to be tapped in, so
  /// the row's no taller for it.
  Widget _row(
    BuildContext context, {
    IconData? icon,
    Widget? glyph,
    required Widget child,
    required VoidCallback? onTap,
    bool editing = false,
    String? changedKey,
    bool? changed,
    Widget? trailing,
    Hotkey? hotkey,
  }) {
    final theme = Theme.of(context);
    final waits = changedKey != null && _waits(changedKey);
    final leading = glyph ?? Icon(icon);
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        InkWell(
          onTap: _editable && !_saving && !waits ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconTheme(
                          data: IconThemeData(
                            size: 22,
                            color: editing
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          child: hotkey == null
                              ? leading
                              : HotkeyHint(hotkey, child: leading),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: child),
                        if (waits) const WaitingMark(),
                        if (changedKey != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child:
                                _changedDot(changedKey, changed: changed) ??
                                const SizedBox(),
                          ),
                      ],
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A text property: its value, or [hint] if it's blank, with no label.
  Widget _textRow(
    BuildContext context, {
    required _Field field,
    required String key,
    required IconData icon,
    required String hint,
    bool multiline = false,
    Hotkey? hotkey,
  }) {
    final theme = Theme.of(context);
    final editing = _editing == field;
    final value = _value(key) as String?;
    final blank = value == null || value.trim().isEmpty;
    return _row(
      context,
      icon: icon,
      editing: editing,
      changedKey: key,
      hotkey: hotkey,
      onTap: editing ? null : () => _open(field),
      child: editing
          ? TextField(
              controller: _text,
              autofocus: true,
              minLines: multiline ? 2 : 1,
              maxLines: multiline ? 6 : 1,
              keyboardType: multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: hint,
              ),
              onChanged: (typed) =>
                  _set(key, typed.trim().isEmpty ? null : typed.trim()),
              onSubmitted: multiline
                  ? null
                  : (_) => setState(() => _editing = null),
            )
          : Text(
              blank ? hint : value,
              maxLines: multiline ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: blank ? theme.hintColor : null,
              ),
            ),
    );
  }

  /// Its actions, and how much of it each takes.
  List<ActionShare> get _actionShares => [
    for (final a in _value('action_ids') as List? ?? const [])
      ?ActionShare.fromJson(a),
  ];

  List<String> get _actionIds => [for (final a in _actionShares) a.actionId];

  /// [share], which says how much of the event an action or goal takes
  /// ("45m", "30%+r"), or what it takes without one: a chip that sets it
  /// with [onTap].
  Widget _shareChip(
    BuildContext context,
    Share share,
    String rest,
    VoidCallback? onTap,
  ) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text(share.label.isEmpty ? rest : share.label),
      onPressed: onTap,
    ),
  );

  /// Sets how much of it the action [id] takes ([showShareDialog]).
  Future<void> _setActionShare(String id) async {
    setState(() => _editing = null);
    final shares = _actionShares;
    final share = shares.firstWhere((s) => s.actionId == id);
    final set = await showShareDialog(
      context,
      title: switch (_action(id)) {
        final action? => actionName(action),
        null => id,
      },
      share: share,
      eventMinutes: _time('end').difference(_time('start')).inMinutes,
      kind: 'action',
      rest:
          "It shares the time the other actions' minutes and percents "
          'leave evenly with the others given neither.',
      make: (minutes, percent, remaining) => ActionShare(
        id,
        minutes: minutes,
        percent: percent,
        remaining: remaining,
      ),
    );
    if (set == null || !mounted) return;
    _set('action_ids', [
      for (final s in shares) (s.actionId == id ? set : s).toJson(),
    ]);
  }

  /// Its actions, each after a diamond in the action's color, as on the
  /// timeline; picked in a sheet up from the foot ([showActionsSheet]).
  Widget _actionsRow(BuildContext context) {
    final theme = Theme.of(context);
    final shares = _actionShares;
    final ids = [for (final s in shares) s.actionId];
    final names = [
      if (!_changes.containsKey('action_ids'))
        for (final name in widget.values['action_names'] as List? ?? const [])
          name as String?,
    ];
    return _row(
      context,
      glyph: const PlowIcon(),
      changedKey: 'action_ids',
      hotkey: Hotkey.actions,
      onTap: _pickActions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ids.isEmpty)
            Text(
              'Add actions',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            ),
          for (final (i, id) in ids.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  ActionDiamond(
                    color: switch (_action(id)) {
                      final action? => parseColor(
                        action.effectiveColor ?? action.backgroundColor,
                      ),
                      null => null,
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(switch (_action(id)) {
                      final action? => actionName(action),
                      null => (i < names.length ? names[i] : null) ?? id,
                    }, style: theme.textTheme.bodyLarge),
                  ),
                  _shareChip(
                    context,
                    shares[i],
                    ids.length == 1 ? 'All of it' : 'Even share',
                    _canEdit('action_ids') ? () => _setActionShare(id) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Its goals, and how much of it each takes.
  List<GoalShare> get _goalShares => [
    for (final g in _value('goals') as List? ?? const [])
      ?GoalShare.fromJson(g),
  ];

  List<Goal> get _goals => PlanMemoryScope.of(context)?.goals ?? const [];

  /// Its goals, each after a goal icon with what it takes ("45m", "30%",
  /// or nothing for all of it); picked in a sheet up from the foot
  /// ([showGoalsSheet]).
  Widget _goalsRow(BuildContext context) {
    final theme = Theme.of(context);
    final shares = _goalShares;
    final tree = GoalTree(_goals);
    return _row(
      context,
      glyph: const GoalIcon(),
      changedKey: 'goals',
      onTap: _pickGoals,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shares.isEmpty)
            Text(
              'Add goals',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            ),
          for (final share in shares)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(switch (tree[share.goalId]) {
                      final goal? => goalTitle(goal),
                      null => share.goalId,
                    }, style: theme.textTheme.bodyLarge),
                  ),
                  if (share.label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(share.label),
                      ),
                    )
                  else
                    Text('The rest', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Picks its goals in a sheet up from the foot -- offering to activate
  /// any picked that's inactive, from its start.
  Future<void> _pickGoals() async {
    setState(() => _editing = null);
    final start = _time('start');
    final minutes = _time('end').difference(start).inMinutes;
    final was = {for (final s in _goalShares) s.goalId};
    final picked = await showGoalsSheet(
      context,
      goals: _goals,
      picked: _goalShares,
      eventMinutes: minutes,
    );
    if (picked == null || !mounted) return;
    final tree = GoalTree(_goals);
    final waking = [
      for (final s in picked)
        if (!was.contains(s.goalId))
          if (tree[s.goalId] case final goal? when goal.inactive) goal,
    ];
    if (waking.isNotEmpty) {
      final memory = PlanMemoryScope.of(context);
      final repository = GoalsScope.of(context);
      final names = waking.map((g) => '“${goalTitle(g)}”').join(', ');
      final wake = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(waking.length == 1 ? 'Activate it?' : 'Activate them?'),
          content: Text(
            '$names ${waking.length == 1 ? 'is' : 'are'} inactive. Activate '
            '${waking.length == 1 ? 'it' : 'them'} from when this event '
            'starts?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Leave inactive'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Activate'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if ((wake ?? false) && memory != null && repository != null) {
        await GoalActions(
          context: context,
          repository: repository,
          memory: memory,
        ).activate(waking, at: start);
        if (!mounted) return;
      }
    }
    _set('goals', [for (final s in picked) s.toJson()]);
  }

  /// Picks its actions in a sheet up from the foot; null until there are
  /// actions to pick from.
  VoidCallback? get _pickActions => switch (_actionList) {
    final actions? => () async {
      setState(() => _editing = null);
      final picked = await showActionsSheet(
        context,
        actions: actions,
        loaded: _actionsLoaded,
        picked: _actionIds,
        query: _value('summary') as String?,
        reload: widget.loadActions,
        marker: (action) => ActionDiamond(
          color: parseColor(action.effectiveColor ?? action.backgroundColor),
        ),
      );
      if (!mounted) return;
      // One may have been added, or edited, from the sheet.
      _actionList = _loadActions();
      if (picked == null) return;
      // Each kept with the share it had.
      final had = {for (final s in _actionShares) s.actionId: s};
      _set('action_ids', [
        for (final id in picked) (had[id] ?? ActionShare(id)).toJson(),
      ]);
    },
    null => null,
  };

  /// [facts] as its facts, a change if they're not as they were.
  void _setFacts(Facts facts) {
    final was = Facts.fromJson(widget.values['facts']) ?? const Facts();
    setState(() {
      if (facts == was) {
        _changes.remove('facts');
      } else {
        // Null removes them: see clearableFields.
        _changes['facts'] = facts.isEmpty ? null : facts.toJson();
      }
    });
  }

  /// Who it was with and for, in a line after a person -- or, [where],
  /// its location, after a pin; picked in a sheet up from the foot
  /// ([showWhoWhereSheet]).
  ///
  /// Where, its map location shows if it has no location, and a map
  /// button opens that in a maps app -- an arrow, if it's a link, opens
  /// the link. Without one, the button opens its location's, if that
  /// has one.
  Widget _whoRow(BuildContext context, {bool where = false}) {
    final theme = Theme.of(context);
    final facts = Facts.fromJson(_value('facts')) ?? const Facts();
    final own = (_value('location') as String?)?.trim() ?? '';
    final map = own.isNotEmpty
        ? own
        : [for (final id in facts.locationIds) ?_locationMaps[id]?.trim()]
                  .where((m) => m.isNotEmpty)
                  .firstOrNull ??
              '';
    final line = where
        ? facts.locationIds.isEmpty
              ? own
              : facts.locationIds
                    .map((id) => _locationNames[id] ?? id)
                    .join(', ')
        : Facts(
            withIds: facts.withIds,
            forIds: facts.forIds,
          ).describe(_personNames);
    return _row(
      context,
      icon: where ? Icons.place_outlined : Icons.person_outline,
      changedKey: 'facts',
      changed: _factsChanged,
      hotkey: where ? Hotkey.location : Hotkey.who,
      onTap: () => _pickWho(where: where),
      trailing: where && map.isNotEmpty
          // The row's padding to tap in, so it's no taller for it.
          ? IconButton(
              icon: Icon(placeButton(map).icon),
              tooltip: placeButton(map).tooltip,
              constraints: const BoxConstraints.tightFor(width: 48, height: 44),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              color: theme.colorScheme.primary,
              onPressed: () => openInMaps(map),
            )
          : null,
      child: Text(
        line.isEmpty ? (where ? 'Add location' : 'Add who') : line,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: line.isEmpty ? theme.hintColor : null,
        ),
      ),
    );
  }

  /// Picks who it was with and for -- or, [where], where it was -- in a
  /// sheet up from the foot ([showWhoWhereSheet]).
  Future<void> _pickWho({bool where = false}) async {
    setState(() => _editing = null);
    final edited = await showWhoWhereSheet(
      context,
      Facts.fromJson(_value('facts')) ?? const Facts(),
      where: where,
      mapLocation: _value('location') as String?,
      query: _value('summary') as String?,
      additions: widget.additions,
    );
    if (!mounted) return;
    // Someone, or a location, may have been added, or renamed, from the
    // sheet.
    if (PlanMemoryScope.of(context) case final memory?) {
      setState(() => _named(memory.people, memory.locations, memory.traits));
    }
    if (edited == null) return;
    _setFacts(edited.facts);
    if (where) {
      final typed = edited.mapLocation?.trim() ?? '';
      // Null clears it: see clearableFields.
      _set('location', typed.isEmpty ? null : typed);
    }
  }

  /// Its description, as its HTML lays it out, cut off if it's long
  /// ([EventDescription]), or a hint; read in full, and written, in a
  /// sheet up from the foot ([showTextSheet]).
  Widget _descriptionRow(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value('description') as String?;
    final blank = value == null || value.trim().isEmpty;
    return _row(
      context,
      icon: Icons.notes,
      changedKey: 'description',
      hotkey: Hotkey.description,
      onTap: _editDescription,
      child: blank
          ? Text(
              'Add description',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: EventDescription(value, maxLines: 6, expandable: false),
            ),
    );
  }

  /// Reads and writes its description in a sheet up from the foot
  /// ([showTextSheet]).
  Future<void> _editDescription() async {
    setState(() => _editing = null);
    final text = await showTextSheet(
      context,
      title: 'Description',
      text: _value('description') as String?,
      hint: 'Add description',
    );
    if (text == null || !mounted) return;
    _set('description', text.isEmpty ? null : text);
  }

  /// The notes on you and on each person there, and how many judgments
  /// the assistant made of it; tapped to edit the notes in
  /// [showFactsDialog].
  /// R: its recurrence, to change -- or, for a new event with none, one
  /// every week, to start from.
  void _openRepeat() {
    if (_value('repeat') == null) {
      if (!widget.repeatable) return;
      _set('repeat', const Repeat(every: 'week'));
    }
    _open(_Field.repeat);
  }

  /// N: what happened -- its notes -- in a dialog of its own.
  Future<void> _editNotes() async {
    setState(() => _editing = null);
    final edited = await showFactsDialog(
      context,
      Facts.fromJson(_value('facts')),
      judgments: judgmentsFromJson(widget.values['judgments']),
      traitNames: _traitNames,
      additions: widget.additions,
      // Who and where, in their own row.
      pickers: false,
    );
    if (edited != null && mounted) _setFacts(edited);
  }

  Widget _factsRow(BuildContext context) {
    final theme = Theme.of(context);
    final facts = Facts.fromJson(_value('facts'));
    final judgments = judgmentsFromJson(widget.values['judgments']);
    final empty = (facts?.notes.isEmpty ?? true) && judgments.isEmpty;
    return _row(
      context,
      icon: Icons.note_alt_outlined,
      changedKey: 'facts',
      changed: _factsChanged,
      hotkey: Hotkey.eventNotes,
      onTap: _editNotes,
      child: empty
          ? Text(
              'Add what happened',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final MapEntry(:key, :value)
                    in facts?.notes.entries ??
                        const <MapEntry<String, String>>[])
                  Text(
                    '${_personNames[key] ?? key}: $value',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (judgments.isNotEmpty)
                  Text(
                    '${judgments.length} judgment'
                    '${judgments.length == 1 ? '' : 's'} by Claude',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
    );
  }
}

/// An outlined box around a property open for editing.
class _EditingFrame extends StatelessWidget {
  const _EditingFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

/// A small diamond in an action's [color], or outlined if it has none, as
/// the timeline marks an event's actions.
class ActionDiamond extends StatelessWidget {
  const ActionDiamond({super.key, required this.color, this.size = 8});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: color == null
            ? Border.all(color: Theme.of(context).colorScheme.onSurfaceVariant)
            : null,
      ),
    ),
  );
}
