import 'package:flutter/material.dart';

import '../models/repeat.dart';

/// Edits how a series [repeat]s: every day, week, month or year, how many
/// of them apart, on which weekdays (for weeks), and when it ends. Calls
/// [onChanged] with each change. [firstStart] is when the series' first
/// event starts, whose weekday a weekly series starts on.
///
/// Parts it doesn't edit, such as "the last Friday", are kept until the
/// frequency changes, which drops them so the series repeats on its first
/// event's day.
class RepeatEditor extends StatelessWidget {
  const RepeatEditor({
    super.key,
    required this.repeat,
    required this.firstStart,
    required this.onChanged,
  });

  final Repeat repeat;
  final DateTime firstStart;
  final ValueChanged<Repeat> onChanged;

  static const _units = {
    'day': 'Day',
    'week': 'Week',
    'month': 'Month',
    'year': 'Year',
  };
  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final weekdays = repeat.weekdays ?? [Repeat.weekdayOf(firstStart)];
    final end = repeat.count != null
        ? 'count'
        : repeat.until != null
        ? 'until'
        : 'never';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final MapEntry(:key, :value) in _units.entries)
                ButtonSegment(value: key, label: Text(value)),
            ],
            selected: {repeat.every},
            onSelectionChanged: (picked) => onChanged(
              repeat.copyWith(
                every: picked.single,
                clearDays: true,
                weekdays: picked.single == 'week'
                    ? [Repeat.weekdayOf(firstStart)]
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Every', style: theme.textTheme.bodyMedium),
            IconButton(
              tooltip: 'Fewer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove),
              onPressed: repeat.interval <= 1
                  ? null
                  : () => onChanged(
                      repeat.copyWith(interval: repeat.interval - 1),
                    ),
            ),
            Text('${repeat.interval}', style: theme.textTheme.titleMedium),
            IconButton(
              tooltip: 'More',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: () =>
                  onChanged(repeat.copyWith(interval: repeat.interval + 1)),
            ),
            Text(
              repeat.interval == 1 ? repeat.every : '${repeat.every}s',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (repeat.every == 'week')
          Wrap(
            spacing: 4,
            children: [
              for (final (i, day) in Repeat.weekdayKeys.indexed)
                _DayToggle(
                  letter: _letters[i],
                  day: day,
                  on: weekdays.contains(day),
                  // A weekly series falls on at least one day.
                  onTap: weekdays.length == 1 && weekdays.contains(day)
                      ? null
                      : () => onChanged(
                          repeat.copyWith(
                            weekdays: [
                              for (final d in Repeat.weekdayKeys)
                                if ((d == day) != weekdays.contains(d)) d,
                            ],
                          ),
                        ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text('Ends', style: muted),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'never', label: Text('Never')),
              ButtonSegment(value: 'until', label: Text('On a date')),
              ButtonSegment(value: 'count', label: Text('After')),
            ],
            selected: {end},
            onSelectionChanged: (picked) => switch (picked.single) {
              'until' => _pickUntil(context),
              'count' => onChanged(repeat.copyWith(count: 10)),
              _ => onChanged(repeat.copyWith(clearEnd: true)),
            },
          ),
        ),
        if (repeat.until case final until?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ActionChip(
              avatar: const Icon(Icons.calendar_today),
              label: Text(Repeat.formatDay(DateTime.parse(until))),
              onPressed: () => _pickUntil(context),
            ),
          ),
        if (repeat.count case final count?)
          Row(
            children: [
              IconButton(
                tooltip: 'Fewer events',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove),
                onPressed: count <= 1
                    ? null
                    : () => onChanged(repeat.copyWith(count: count - 1)),
              ),
              Text('$count', style: theme.textTheme.titleMedium),
              IconButton(
                tooltip: 'More events',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add),
                onPressed: () => onChanged(repeat.copyWith(count: count + 1)),
              ),
              Text(count == 1 ? 'event' : 'events'),
            ],
          ),
      ],
    );
  }

  Future<void> _pickUntil(BuildContext context) async {
    final current = switch (repeat.until) {
      final until? => DateTime.parse(until),
      null => DateTime(firstStart.year, firstStart.month + 3, firstStart.day),
    };
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(firstStart) ? firstStart : current,
      firstDate: DateTime(firstStart.year, firstStart.month, firstStart.day),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    onChanged(
      repeat.copyWith(
        until:
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}',
      ),
    );
  }
}

/// One weekday, as a round toggle with its [letter].
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.letter,
    required this.day,
    required this.on,
    required this.onTap,
  });

  final String letter;

  /// E.g. "mon", for its tooltip.
  final String day;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: day,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? colors.primary : null,
            border: on ? null : Border.all(color: colors.outline),
          ),
          child: Text(
            letter,
            style: TextStyle(
              color: on ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
