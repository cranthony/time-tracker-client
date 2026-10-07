import 'package:flutter/material.dart';

import '../models/people_times.dart';
import '../models/person.dart';
import 'color_picker.dart' show contrastingColor;
import 'durations.dart';
import 'health.dart';

/// A person in the People pane, a little taller than a plain tile: their
/// name, context and [circles]; their time with the user in the
/// summary's 24 hours and 7 days, from [times], in time or, without
/// [durations], as a share of each; and the last event with them, or
/// looking on, the next. Beside them, their relationship [health] and
/// its [trend], and a [menu]. Self has no time with themself, so says
/// "You" instead; a [prioritized] person has a star.
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.person,
    this.circles = const [],
    this.health,
    this.trend = const [],
    this.times,
    this.durations = true,
    this.prioritized = false,
    this.onTap,
    this.menu,
  });

  final Person person;
  final List<String> circles;
  final int? health;
  final List<int?> trend;
  final PeopleTimes? times;
  final bool durations;
  final bool prioritized;
  final VoidCallback? onTap;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !person.active;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final who = _who();
    // Under the tile, the width of it: beside its health, they'd be cut
    // short.
    final more = [
      if (!person.isSelf && times != null) ...[
        ?_time(times!),
        _nearest(context, times!),
      ],
    ];
    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: switch (health) {
          final h? => relationshipColor(h),
          null => theme.colorScheme.surfaceContainerHighest,
        },
        foregroundColor: switch (health) {
          final h? => contrastingColor(relationshipColor(h)),
          null => theme.colorScheme.onSurfaceVariant,
        },
        child: person.isSelf
            ? const Icon(Icons.person)
            : Text(person.name.isEmpty ? '?' : person.name[0].toUpperCase()),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              personName(person),
              overflow: TextOverflow.ellipsis,
              style: muted ? TextStyle(color: theme.hintColor) : null,
            ),
          ),
          if (prioritized) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.star,
              size: 16,
              color: theme.colorScheme.primary,
              semanticLabel: 'Prioritized',
            ),
          ],
        ],
      ),
      subtitle: who == null
          ? null
          : Text(who, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trend.nonNulls.isNotEmpty) ...[
            TrendSparkline(trend: trend, scale: HealthScale.relationship),
            const SizedBox(width: 8),
          ],
          if (health != null)
            HealthDot(rating: health, scale: HealthScale.relationship),
          ?menu,
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile,
          if (more.isNotEmpty)
            Padding(
              // Under the name, past the avatar.
              padding: const EdgeInsetsDirectional.fromSTEB(72, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in more)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Who they are: their context and circles, or for Self, "You"; and
  /// their status, if they're put away.
  String? _who() {
    final parts = [
      if (person.isSelf) 'You',
      ?person.context,
      if (circles.isNotEmpty) circles.join(', '),
      if (!person.active) personStatuses[person.status] ?? person.status,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "24h 1h 30m · 7d 4h", or as shares: "24h 6% · 7d 2%"; "–" for none.
  String? _time(PeopleTimes times) {
    final day = times.day(person.id), week = times.week(person.id);
    if (day == null || week == null) return null;
    // None, as the summary's legend says it.
    String amount(Duration time, Duration of) => time == Duration.zero
        ? '–'
        : durations
        ? formatDuration(Duration(minutes: (time.inSeconds / 60).round()))!
        : '${(100 * time.inSeconds / of.inSeconds).round()}%';
    final (dayLabel, weekLabel) = times.window.labels;
    return '$dayLabel ${amount(day, const Duration(hours: 24))} · '
        '$weekLabel ${amount(week, const Duration(days: 7))}';
  }

  /// "Last: Dinner · Thu, Oct 1, 6:30 PM", or looking on, "Next: ...".
  String _nearest(BuildContext context, PeopleTimes times) {
    final next = times.window.forward;
    final event = times.nearest(person.id);
    if (event == null) return next ? 'Nothing planned' : 'Not seen lately';
    final localizations = MaterialLocalizations.of(context);
    final when =
        '${localizations.formatMediumDate(event.start)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(event.start))}';
    return '${next ? 'Next' : 'Last'}: '
        '${event.summary?.isNotEmpty ?? false ? event.summary : '(no title)'}'
        ' · $when';
  }
}
