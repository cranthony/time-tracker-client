import 'package:flutter/material.dart';

import 'cursor_modes.dart';
import 'cursor_snap.dart';

/// A cursor's settings, in a sheet: its [title] ("Anchor", "End"); what
/// it does with events -- an anchor's [anchorMode], or an end's
/// [endMode], if it has one; what it stops at besides the grid ([snap]);
/// and its time, to type ([onEditTime]). Each change is made at once.
Future<void> showCursorSheet(
  BuildContext context, {
  required String title,
  AnchorMode? anchorMode,
  EndMode? endMode,
  Set<SnapTo>? snap,
  ValueChanged<AnchorMode>? onAnchorMode,
  ValueChanged<EndMode>? onEndMode,
  ValueChanged<Set<SnapTo>>? onSnap,
  VoidCallback? onEditTime,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var anchor = anchorMode;
    var end = endMode;
    var stops = {...?snap};
    return StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
        Widget mode<T>(
          T value,
          T picked,
          String label,
          String description,
          IconData icon,
        ) => RadioListTile<T>(
          value: value,
          secondary: Icon(icon),
          title: Text(label),
          subtitle: value == picked ? Text(description) : null,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                if (anchor case final picked?) ...[
                  heading('The event it is inside of'),
                  RadioGroup<AnchorMode>(
                    groupValue: picked,
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => anchor = m);
                      onAnchorMode?.call(m);
                    },
                    child: Column(
                      children: [
                        for (final m in AnchorMode.values)
                          mode(m, picked, m.label, m.description, m.icon),
                      ],
                    ),
                  ),
                ],
                if (end case final picked?) ...[
                  heading('What it does with the events in its way'),
                  RadioGroup<EndMode>(
                    groupValue: picked,
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => end = m);
                      onEndMode?.call(m);
                    },
                    child: Column(
                      children: [
                        for (final m in EndMode.values)
                          mode(m, picked, m.label, m.description, m.icon),
                      ],
                    ),
                  ),
                ],
                if (snap != null) heading('Stops at'),
                if (snap != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      "The grid's lines, set in Settings, and:",
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final s in SnapTo.values)
                  if (snap != null)
                    CheckboxListTile(
                      value: stops.contains(s),
                      title: Text(s.label),
                      onChanged: (on) {
                        setState(
                          () => stops = {
                            for (final t in SnapTo.values)
                              if (t == s ? on ?? false : stops.contains(t)) t,
                          },
                        );
                        onSnap?.call(stops);
                      },
                    ),
                if (onEditTime != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onEditTime();
                        },
                        icon: const Icon(Icons.schedule),
                        label: const Text('Edit its time'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  },
);

/// Asks for a cursor's time, starting at [initial]: its day -- "+0" the
/// timeline's [day], or the day before or after -- its hour and its
/// minute, each with a "+" above and a "−" below, stepping it by one. A
/// minute past 59 carries into the hour, and an hour past 23 into the
/// day, either way. Never before [first], nor after [last]. Null if
/// called off.
Future<DateTime?> showEditTimeDialog(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime day,
  required DateTime first,
  required DateTime last,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) => _EditTimeDialog(
    title: title,
    initial: initial.toLocal(),
    day: DateUtils.dateOnly(day),
    first: first,
    last: last,
  ),
);

class _EditTimeDialog extends StatefulWidget {
  const _EditTimeDialog({
    required this.title,
    required this.initial,
    required this.day,
    required this.first,
    required this.last,
  });

  final String title;
  final DateTime initial;
  final DateTime day;
  final DateTime first;
  final DateTime last;

  @override
  State<_EditTimeDialog> createState() => _EditTimeDialogState();
}

class _EditTimeDialogState extends State<_EditTimeDialog> {
  late DateTime _at = DateTime(
    widget.initial.year,
    widget.initial.month,
    widget.initial.day,
    widget.initial.hour,
    widget.initial.minute,
  );

  /// How many days [time] is from the timeline's day: calendar days,
  /// whatever the clocks did.
  int _daysFrom(DateTime time) => DateTime.utc(time.year, time.month, time.day)
      .difference(
        DateTime.utc(widget.day.year, widget.day.month, widget.day.day),
      )
      .inDays;

  /// [_at] stepped: by [days], [hours] or [minutes], carrying.
  DateTime _stepped({int days = 0, int hours = 0, int minutes = 0}) => DateTime(
    _at.year,
    _at.month,
    _at.day + days,
    _at.hour + hours,
    _at.minute + minutes,
  );

  /// Whether [to] can be had: within a day of the timeline's, and from
  /// [first] to [last].
  bool _allowed(DateTime to) =>
      _daysFrom(to).abs() <= 1 &&
      !to.isBefore(widget.first) &&
      !to.isAfter(widget.last);

  @override
  Widget build(BuildContext context) {
    final strings = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final offset = _daysFrom(_at);
    Widget column(
      String label,
      String value,
      String what, {
      required DateTime up,
      required DateTime down,
    }) {
      Widget step(IconData icon, String tooltip, DateTime to) =>
          IconButton.filledTonal(
            tooltip: tooltip,
            iconSize: 24,
            onPressed: _allowed(to) ? () => setState(() => _at = to) : null,
            icon: Icon(icon),
          );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          step(Icons.add, 'One $what later', up),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(value, style: theme.textTheme.headlineSmall),
          ),
          step(Icons.remove, 'One $what earlier', down),
        ],
      );
    }

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${strings.formatMediumDate(_at)}, '
            '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(_at))}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              column(
                'Day',
                offset < 0 ? '−${-offset}' : '+$offset',
                'day',
                up: _stepped(days: 1),
                down: _stepped(days: -1),
              ),
              column(
                'Hour',
                _at.hour.toString().padLeft(2, '0'),
                'hour',
                up: _stepped(hours: 1),
                down: _stepped(hours: -1),
              ),
              column(
                'Minute',
                _at.minute.toString().padLeft(2, '0'),
                'minute',
                up: _stepped(minutes: 1),
                down: _stepped(minutes: -1),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_at),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
