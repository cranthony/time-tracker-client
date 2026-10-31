import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hotkeys.dart';

/// Asks for a day, from [firstDate] to [lastDate], [initialDate] picked
/// to start with, as [showDatePicker] does -- but at home on a keyboard:
/// J and K pick the next day and the one before, on across months; H
/// and L go a month back and on; T picks [currentDate], today; E types
/// it, the date selected to type over; and Enter or Ctrl+Enter goes
/// with it, as OK does. [typed] starts it typing; [helpText] says what it's for,
/// over the date. The day picked, or null if it's called off.
Future<DateTime?> showDayPicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  bool typed = false,
  String? helpText,
}) async => (await showDialog<DayAndTime>(
  context: context,
  builder: (context) => DayPickerDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    typed: typed,
    helpText: helpText,
  ),
))?.day;

/// A day picked, and the time of day on it, if one was.
typedef DayAndTime = ({DateTime day, TimeOfDay? time});

/// [showDayPicker], with a time of day it can be given too: "Add a time"
/// under the calendar, or I, asks for one -- [defaultTime] to start
/// with -- and, once it's given, it's shown there to change, or take
/// off. [initialTime] is given to start with. The day and time picked,
/// or null if it's called off.
Future<DayAndTime?> showDayTimePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? currentDate,
  TimeOfDay? initialTime,
  TimeOfDay defaultTime = const TimeOfDay(hour: 17, minute: 0),
  String? helpText,
}) => showDialog<DayAndTime>(
  context: context,
  builder: (context) => DayPickerDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    currentDate: currentDate,
    helpText: helpText,
    withTime: true,
    initialTime: initialTime,
    defaultTime: defaultTime,
  ),
);

/// The dialog of [showDayPicker] and [showDayTimePicker]: a calendar, or
/// the date typed -- and, [withTime], a time of day under it.
class DayPickerDialog extends StatefulWidget {
  const DayPickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.currentDate,
    this.typed = false,
    this.helpText,
    this.withTime = false,
    this.initialTime,
    this.defaultTime = const TimeOfDay(hour: 17, minute: 0),
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? currentDate;
  final bool typed;

  /// What it's for, over the date: "Select date", without it.
  final String? helpText;

  /// Whether a time of day can be given too: [initialTime] to start with,
  /// and [defaultTime] asked for first when one's added.
  final bool withTime;
  final TimeOfDay? initialTime;
  final TimeOfDay defaultTime;

  @override
  State<DayPickerDialog> createState() => _DayPickerDialogState();
}

class _DayPickerDialogState extends State<DayPickerDialog> {
  late DateTime _day = _within(widget.initialDate);
  late bool _typed = widget.typed;
  late TimeOfDay? _time = widget.withTime ? widget.initialTime : null;

  /// Bumped when a key picks a day, for the calendar -- which only takes
  /// the day it starts on -- to start afresh on it, its month shown.
  int _moves = 0;

  final _form = GlobalKey<FormState>();

  /// Where keys go with the calendar shown: not one of its days, whose
  /// arrows would only move the highlight, not the day picked.
  final _focus = FocusNode(debugLabel: 'Day picker');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  DateTime _within(DateTime day) {
    final date = DateUtils.dateOnly(day);
    final first = DateUtils.dateOnly(widget.firstDate);
    final last = DateUtils.dateOnly(widget.lastDate);
    return date.isBefore(first) ? first : (date.isAfter(last) ? last : date);
  }

  DateTime get _today =>
      DateUtils.dateOnly(widget.currentDate ?? DateTime.now());

  /// Picks [day], by a key: back on the calendar, if the date was being
  /// typed -- what was typed, if it's a date, kept first.
  void _move(DateTime Function(DateTime from) day) {
    if (_typed && !_readTyped()) return;
    setState(() {
      _typed = false;
      _day = _within(day(_day));
      _moves++;
    });
    _focus.requestFocus();
  }

  void _days(int days) => _move((d) => DateTime(d.year, d.month, d.day + days));

  /// [months] on, or back, to the same day of it -- or its last, for
  /// one that's shorter.
  void _months(int months) => _move((d) {
    final month = DateTime(d.year, d.month + months);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return DateTime(month.year, month.month, min(d.day, days));
  });

  /// Whether what's typed is a date, kept as the day picked if it is --
  /// saying why not, if it isn't.
  bool _readTyped() {
    final form = _form.currentState;
    if (form == null) return true;
    if (!form.validate()) return false;
    form.save();
    return true;
  }

  /// E, or the button beside the title: types the date, or goes back to
  /// the calendar.
  void _toggleTyped() {
    if (_typed) {
      if (!_readTyped()) return;
      setState(() {
        _typed = false;
        _moves++;
      });
      _focus.requestFocus();
    } else {
      setState(() => _typed = true);
    }
  }

  void _done() {
    if (_typed && !_readTyped()) return;
    Navigator.of(context).pop((day: _day, time: _time));
  }

  /// I, or the button under the calendar: asks for the time of day, the
  /// one given or [DayPickerDialog.defaultTime] to start with -- back on
  /// the calendar after, if the date was being typed.
  Future<void> _pickTime() async {
    if (_typed && !_readTyped()) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? widget.defaultTime,
    );
    if (!mounted) return;
    setState(() {
      if (_typed) _moves++;
      _typed = false;
      _time = picked ?? _time;
    });
    _focus.requestFocus();
  }

  List<HotkeyBinding> get _hotkeys => [
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyJ),
      () => _days(1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyK),
      () => _days(-1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowRight),
      () => _days(1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowLeft),
      () => _days(-1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowDown),
      () => _days(7),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowUp),
      () => _days(-7),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyH),
      () => _months(-1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyL),
      () => _months(1),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyT),
      () => _move((_) => _today),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyE),
      _toggleTyped,
    ),
    if (widget.withTime)
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyI),
        _pickTime,
      ),
    HotkeyBinding(const HotkeyTrigger.ctrl(LogicalKeyboardKey.enter), _done),
    // Enter alone too, on the calendar -- not on a button or a day that
    // Tab went to, which Enter presses.
    for (final key in const [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      HotkeyBinding(
        HotkeyTrigger.key(key),
        _done,
        when: () => FocusManager.instance.primaryFocus == _focus,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final body = _typed
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Form(
              key: _form,
              child: InputDatePickerFormField(
                initialDate: _day,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                // Its text selected, to type over.
                autofocus: true,
                onDateSaved: (day) => _day = DateUtils.dateOnly(day),
                onDateSubmitted: (day) {
                  _day = DateUtils.dateOnly(day);
                  _done();
                },
              ),
            ),
          )
        : Focus(
            focusNode: _focus,
            autofocus: true,
            child: CalendarDatePicker(
              key: ValueKey(_moves),
              initialDate: _day,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              currentDate: _today,
              onDateChanged: (day) {
                setState(() => _day = DateUtils.dateOnly(day));
                // Off the day tapped, for the keys to pick days again.
                _focus.requestFocus();
              },
            ),
          );
    return HotkeyBindings(
      bindings: _hotkeys,
      child: Dialog(
        child: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
                  child: Text(
                    widget.helpText ?? localizations.datePickerHelpText,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            localizations.formatMediumDate(_day),
                            if (_time case final time?)
                              localizations.formatTimeOfDay(time),
                          ].join(', '),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      HotkeyHint(
                        Hotkey.pickerTyped,
                        child: IconButton(
                          icon: Icon(
                            _typed ? Icons.calendar_today : Icons.edit_outlined,
                          ),
                          tooltip: _typed
                              ? localizations.calendarModeButtonLabel
                              : localizations.inputDateModeButtonLabel,
                          onPressed: _toggleTyped,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                body,
                if (widget.withTime)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        HotkeyHint(
                          Hotkey.pickerTime,
                          child: TextButton.icon(
                            icon: const Icon(Icons.schedule),
                            label: Text(switch (_time) {
                              final time? => localizations.formatTimeOfDay(
                                time,
                              ),
                              null => 'Add a time',
                            }),
                            onPressed: _pickTime,
                          ),
                        ),
                        if (_time != null)
                          IconButton(
                            tooltip: 'No time',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _time = null),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(localizations.cancelButtonLabel),
                      ),
                      const SizedBox(width: 8),
                      HotkeyHint(
                        Hotkey.pickerDone,
                        child: TextButton(
                          onPressed: _done,
                          child: Text(localizations.okButtonLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
