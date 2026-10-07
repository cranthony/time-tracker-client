import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/facts.dart';
import '../models/plan_action.dart';
import '../models/proposal.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/recurrence.dart';
import '../models/repeat.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'color_picker.dart';
import 'event_dialog.dart' show followThroughOption;
import 'other_events.dart';
import 'facts_dialog.dart';
import 'actions_picker.dart';
import 'properties_dialog.dart' show ConfirmOption, confirmationContent;
import 'recurrence_dialog.dart';
import 'repeat_editor.dart';

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
/// events in [otherEvents].
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
      },
      actions: actions,
      loadActions: loadActions,
      otherEvents: otherEvents,
      facets: true,
      save: save == null || event.id == null
          ? null
          : (changes) async =>
                () => save(changes),
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
    ),
  );
}

/// Shows a new event, from [start] to [end], as [showEventSummaryDialog]
/// shows one, blank but for its times, with its summary open to type.
/// "Create", once it has a summary, sends it with [create], as
/// `create_event` takes it. Returns what [create] returned (the events the
/// server changed), or null if it was called off. Its times are kept
/// clear of the events in [otherEvents]. With [clear], a trash can at its
/// top right offers to make no new event, but just clear the time --
/// asking first.
Future<List<Event>?> showNewEventDialog(
  BuildContext context, {
  required DateTime start,
  required DateTime end,
  OtherEvents otherEvents = const OtherEvents.none(),
  required Future<List<Event>> Function(Map<String, Object?> fields) create,
  ClearTime? clear,
  Map<String, PlanAction> actions = const {},
  Future<List<PlanAction>> Function()? loadActions,
}) async {
  final values = {
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
      save: (changes) async =>
          () => create({...values, ...changes}),
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
/// event's times.
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
      actions: actions,
      loadActions: loadActions,
      save: (changes) async {
        final scope = await askSeriesScope(context, changes);
        if (scope == null) return null;
        return () => save({
          for (final MapEntry(:key, :value) in changes.entries)
            key: value is Repeat ? value.toJson() : value,
        }, scope);
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
enum _Field { priority, summary, time, repeat, location, description, actions }

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
    this.facets = false,
    this.additions = const [],
  });

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

  /// Whether it's a new event, not yet on the server: it opens with its
  /// summary to type, and "Create" sends it once it has one.
  final bool creating;

  /// The other events its times are kept clear of.
  final OtherEvents otherEvents;
  final Future<bool> Function()? openSeries;

  /// Whether it shows its facets: an event's, not a series'.
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

  late final Future<List<PlanAction>>? _actionList = widget.loadActions?.call()
    ?..then((list) {
      if (mounted) setState(() => _actionsLoaded = list);
    }, onError: (Object _) {});

  /// [_actionList], once it's in: the picker is drawn from it at once,
  /// rather than waiting a frame on a future that's done.
  List<PlanAction>? _actionsLoaded;

  /// Everyone's names, once the [PeopleScope] has them, for who it was
  /// with and for; the locations', for where; and the traits', from the
  /// [TraitsScope], for its judgments.
  Map<String?, String> _personNames = {selfPersonId: defaultSelf.name};
  Map<String?, String> _locationNames = const {};
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

  bool get _editable => widget.save != null;

  @override
  void initState() {
    super.initState();
    if (widget.creating) _editing = _Field.summary;
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
    (final List a, final List b) => listEquals(a, b),
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          SignInRequiredException() =>
            'You were signed out. Sign in again from the Events page, then '
                'try again.',
          McpException(:final message) => message,
          _ => '$e',
        };
      });
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

  @override
  Widget build(BuildContext context) {
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
              _topRow(context),
              if (_editing == _Field.priority) _priorityEditor(context),
              _summary(context),
              _timeLine(context),
              if (widget.series) _repeatLine(context),
              if (widget.openSeries case final open?) _seriesChip(open),
              const SizedBox(height: 8),
              _textRow(
                context,
                field: _Field.location,
                key: 'location',
                icon: Icons.place_outlined,
                hint: 'Add location',
              ),
              _textRow(
                context,
                field: _Field.description,
                key: 'description',
                icon: Icons.notes,
                hint: 'Add description',
                multiline: true,
              ),
              _actionsRow(context),
              if (widget.facets) _factsRow(context),
            ],
          ),
        ),
      ),
      actions: widget.creating
          ? [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
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
            ]
          : changed
          ? [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(SummaryDetails<T>()),
                child: const Text('Details'),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
    );
  }

  /// A dot saying [key] was changed, if it was.
  Widget? _changedDot(String key) => _changes.containsKey(key)
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

  /// The priority chip, a series' "Series", and the trash can.
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
        Tooltip(
          message: own == null && shown != null
              ? "Priority, from its actions"
              : 'Priority',
          child: InkWell(
            onTap: _editable && !_saving ? () => _open(_Field.priority) : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(padding: const EdgeInsets.all(4), child: chip),
          ),
        ),
        ?_changedDot('priority'),
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
        const Spacer(),
        if (widget.remove case final remove? when _editable)
          IconButton(
            tooltip: remove.tooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _confirmRemove(remove),
          ),
      ],
    );
  }

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
    return InkWell(
      onTap: _editable && !_saving ? () => _open(_Field.summary) : null,
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
      onTap: _editable && !_saving ? () => _open(_Field.time) : null,
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
  /// elsewhere that the app can't say is shown, but can't be changed.
  Widget _repeatLine(BuildContext context) {
    final theme = Theme.of(context);
    final repeat = _value('repeat') as Repeat?;
    final schedule = _changes.containsKey('repeat')
        ? repeat?.describe()
        : widget.values['schedule'] as String? ?? repeat?.describe();
    final editing = _editing == _Field.repeat;
    final color = editing
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final line = InkWell(
      onTap: _editable && !_saving && repeat != null
          ? () => _open(_Field.repeat)
          : null,
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
                  if (repeat == null)
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
        ],
      ),
    );
  }

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

  /// One property after its [icon], tapped to edit or toggle it.
  Widget _row(
    BuildContext context, {
    required IconData icon,
    required Widget child,
    required VoidCallback? onTap,
    bool editing = false,
    String? changedKey,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        InkWell(
          onTap: _editable && !_saving ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: editing
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(child: child),
                if (changedKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _changedDot(changedKey) ?? const SizedBox(),
                  ),
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

  List<String> get _actionIds => [
    for (final id in _value('action_ids') as List? ?? const []) '$id',
  ];

  /// Its actions, each after a diamond in the action's color, as on the
  /// timeline; picked from a list once opened.
  Widget _actionsRow(BuildContext context) {
    final theme = Theme.of(context);
    final editing = _editing == _Field.actions;
    final ids = _actionIds;
    final names = [
      if (!_changes.containsKey('action_ids'))
        for (final name in widget.values['action_names'] as List? ?? const [])
          name as String?,
    ];
    return _row(
      context,
      icon: Icons.flag_outlined,
      editing: editing,
      changedKey: 'action_ids',
      onTap: editing || widget.loadActions == null
          ? null
          : () => _open(_Field.actions),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ids.isEmpty && !editing)
            Text(
              'Add actions',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.hintColor,
              ),
            ),
          if (!editing)
            for (final (i, id) in ids.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    ActionDiamond(
                      color: switch (widget.actions[id]) {
                        final action? => parseColor(
                          action.effectiveColor ?? action.backgroundColor,
                        ),
                        null => null,
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(switch (widget.actions[id]) {
                        final action? => actionName(action),
                        null => (i < names.length ? names[i] : null) ?? id,
                      }, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          if (editing) _actionsPicker(context, ids),
        ],
      ),
    );
  }

  /// Who it was with and for, and where, in a line, and the notes on
  /// each person under it, then how many judgments the assistant made of
  /// it; tapped to edit the facts in [showFactsDialog].
  Widget _factsRow(BuildContext context) {
    final theme = Theme.of(context);
    final facts = Facts.fromJson(_value('facts'));
    final judgments = judgmentsFromJson(widget.values['judgments']);
    final empty = (facts == null || facts.isEmpty) && judgments.isEmpty;
    return _row(
      context,
      icon: Icons.auto_awesome_outlined,
      changedKey: 'facts',
      onTap: () async {
        setState(() => _editing = null);
        final edited = await showFactsDialog(
          context,
          facts,
          judgments: judgments,
          traitNames: _traitNames,
          additions: widget.additions,
        );
        if (edited == null || !mounted) return;
        final was = Facts.fromJson(widget.values['facts']) ?? const Facts();
        setState(() {
          if (edited == was) {
            _changes.remove('facts');
          } else {
            // Null removes them: see clearableFields.
            _changes['facts'] = edited.isEmpty ? null : edited.toJson();
          }
        });
      },
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
                if (facts?.describe(_personNames, _locationNames)
                    case final line? when line.isNotEmpty)
                  Text(line, style: theme.textTheme.bodyLarge),
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

  /// Its actions, searched for or picked from the tree; see [ActionsPicker].
  Widget _actionsPicker(BuildContext context, List<String> picked) =>
      FutureBuilder(
        future: _actionList,
        initialData: _actionsLoaded,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              "Couldn't load actions. ${switch (snapshot.error) {
                McpException(:final message) => message,
                final e => '$e',
              }}",
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            );
          }
          final list = snapshot.data;
          if (list == null) return const LinearProgressIndicator();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ActionsPicker(
                actions: list,
                picked: picked,
                leavesOnly: true,
                onChanged: (ids) => _set('action_ids', ids),
                marker: (action) => ActionDiamond(
                  color: parseColor(
                    action.effectiveColor ?? action.backgroundColor,
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => setState(() => _editing = null),
                  child: const Text('Done'),
                ),
              ),
            ],
          );
        },
      );
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
