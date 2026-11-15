import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/person.dart';
import '../models/trait.dart';
import '../models/trait_example.dart';
import '../services/server_errors.dart';
import 'day_picker.dart';
import 'hotkeys.dart';
import 'people_picker.dart';

/// An event a story can be linked to: its id, and how it's named.
typedef StoryEvent = ({String id, String label});

/// Adds a story of [trait] (with no [example]) or edits [example]: when
/// it happened, who did it -- someone in [people] (Self, a person or a
/// community), or someone else, in words -- what they did, why it
/// embodies the trait, and the event it happened at, if any, from
/// [eventsOn] that day. Saved with [save]; what the server says of one it
/// refuses is shown, and it stays open. Returns it as saved, or null if
/// it was called off.
Future<TraitExample?> showTraitExampleDialog(
  BuildContext context, {
  required Trait trait,
  TraitExample? example,
  PeopleList? people,
  Future<List<StoryEvent>> Function(DateTime day)? eventsOn,
  required Future<TraitExample> Function(TraitExample example) save,
  DateTime Function() clock = DateTime.now,
}) => showDialog<TraitExample>(
  context: context,
  builder: (_) => _StoryDialog(
    trait: trait,
    example: example,
    people: people,
    eventsOn: eventsOn,
    save: save,
    clock: clock,
  ),
);

/// Under a story's text: it's written in Markdown.
const _markdownHelp = 'Markdown: **bold**, *italics*, - lists, [links](…)';

class _StoryDialog extends StatefulWidget {
  const _StoryDialog({
    required this.trait,
    required this.example,
    required this.people,
    required this.eventsOn,
    required this.save,
    required this.clock,
  });

  final Trait trait;
  final TraitExample? example;
  final PeopleList? people;
  final Future<List<StoryEvent>> Function(DateTime day)? eventsOn;
  final Future<TraitExample> Function(TraitExample example) save;
  final DateTime Function() clock;

  @override
  State<_StoryDialog> createState() => _StoryDialogState();
}

class _StoryDialogState extends State<_StoryDialog> {
  late DateTime _when =
      DateTime.tryParse(widget.example?.when ?? '') ??
      DateUtils.dateOnly(widget.clock());

  /// Who did it, if they're in People -- a person, a community, or Self;
  /// null for no one picked, who's then said in words.
  late String? _personId = widget.example == null
      ? selfPersonId
      : widget.example!.personId;

  /// The name of whoever was picked, as the picker gave it: someone just
  /// added isn't in [_StoryDialog.people].
  String? _pickedName;
  late final _who = TextEditingController(text: widget.example?.who);
  late final _what = TextEditingController(text: widget.example?.what);
  late final _why = TextEditingController(text: widget.example?.why);
  late String? _eventId = widget.example?.eventId;
  Future<List<StoryEvent>>? _events;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    _who.dispose();
    _what.dispose();
    _why.dispose();
    super.dispose();
  }

  void _loadEvents() => _events = widget.eventsOn?.call(_when);

  /// [_personId]'s name.
  String? get _personName {
    final people = widget.people;
    return switch (_personId) {
      null => null,
      selfPersonId => people == null ? 'Me' : personName(people.self),
      final id =>
        _pickedName ??
            people?.names[id] ??
            people?.circles
                .where((c) => c.id == id)
                .map(circleName)
                .firstOrNull ??
            id,
    };
  }

  /// Picks who did it, one person or community, in the people picker.
  Future<void> _pickWho() async {
    final picked = await pickPersonOrCircle(
      context,
      title: 'Who did it',
      communitiesOnly: true,
      picked: _personId,
    );
    if (!mounted) return;
    switch (picked) {
      case final Person p:
        setState(() {
          _personId = p.id;
          _pickedName = p.isSelf ? null : personName(p);
        });
      case final Circle c:
        setState(() {
          _personId = c.id;
          _pickedName = circleName(c);
        });
    }
  }

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  TraitExample get _edited => TraitExample(
    id: widget.example?.id,
    traitId: widget.trait.id ?? '',
    when: _day(_when),
    personId: _personId,
    who: switch (_who.text.trim()) {
      '' => null,
      final who => who,
    },
    what: _what.text.trim(),
    why: _why.text.trim(),
    eventId: _eventId,
    version: widget.example?.version,
  );

  Future<void> _pickDay() async {
    final now = widget.clock();
    final picked = await showDayPicker(
      context,
      initialDate: _when,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1, 12, 31),
      currentDate: now,
      helpText: 'When it happened',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!DateUtils.isSameDay(picked, _when)) _eventId = null;
      _when = DateUtils.dateOnly(picked);
      _loadEvents();
    });
  }

  Future<void> _save() async {
    final edited = _edited;
    if (traitExampleProblem(edited) case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(edited);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeServerError(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SaveHotkey(
      onSave: _saving ? null : _save,
      child: AlertDialog(
        title: Text(
          '${widget.example == null ? 'New' : 'Edit'} story of '
          '${widget.trait.name}',
        ),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  MaterialLocalizations.of(context).formatMediumDate(_when),
                ),
                subtitle: const Text('When it happened'),
                onTap: _pickDay,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(_personName ?? 'No one picked'),
                subtitle: const Text('Who did it (optional)'),
                onTap: _pickWho,
                trailing: _personId == null
                    ? null
                    : IconButton(
                        tooltip: 'No one: say who in words',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _personId = null;
                          _pickedName = null;
                        }),
                      ),
              ),
              TextField(
                controller: _who,
                decoration: InputDecoration(
                  labelText: _personId == null
                      ? 'Who, in words'
                      : 'Who, in words (optional)',
                  hintText: 'A stranger on the train',
                ),
              ),
              TextField(
                controller: _what,
                minLines: 2,
                maxLines: 6,
                maxLength: exampleTextMaxLength,
                decoration: const InputDecoration(
                  labelText: 'What they did',
                  helperText: _markdownHelp,
                ),
              ),
              TextField(
                controller: _why,
                minLines: 2,
                maxLines: 6,
                maxLength: exampleTextMaxLength,
                decoration: InputDecoration(
                  labelText: 'Why it is ${widget.trait.name.toLowerCase()}',
                  helperText: _markdownHelp,
                ),
              ),
              if (widget.eventsOn != null)
                FutureBuilder(
                  future: _events,
                  builder: (context, snapshot) {
                    final events = snapshot.data ?? const <StoryEvent>[];
                    final linked = _eventId;
                    return DropdownButtonFormField<String?>(
                      key: ValueKey((_when, events.length)),
                      initialValue: linked,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'At an event (optional)',
                      ),
                      items: [
                        const DropdownMenuItem(child: Text('None')),
                        for (final e in events)
                          DropdownMenuItem(value: e.id, child: Text(e.label)),
                        if (linked != null &&
                            !events.any((e) => e.id == linked))
                          DropdownMenuItem(
                            value: linked,
                            child: const Text('The event linked'),
                          ),
                      ],
                      onChanged: (id) => setState(() => _eventId = id),
                    );
                  },
                ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// How [event] is named in a story's event picker: its time and summary.
StoryEvent storyEvent(BuildContext context, Event event) => (
  id: event.id ?? '',
  label:
      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(event.start))} '
      '${event.summary ?? '(no summary)'}',
);
