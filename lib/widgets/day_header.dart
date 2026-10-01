import 'package:flutter/material.dart';

bool sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "Today", "Yesterday", or [day]'s date.
String dayLabel(BuildContext context, DateTime day, DateTime today) {
  final local = day.toLocal();
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  return sameDay(local, today)
      ? 'Today'
      : sameDay(local, yesterday)
      ? 'Yesterday'
      : MaterialLocalizations.of(context).formatMediumDate(local);
}

/// [dayLabel], above that day's notes.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        dayLabel(context, day, today),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
