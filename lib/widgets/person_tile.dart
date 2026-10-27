import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/people_times.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import 'color_picker.dart' show contrastingColor;
import 'durations.dart';
import 'health.dart';

/// A person in the People pane, a little taller than a plain tile: their
/// name, context and [circles]; their time with the user in the
/// summary's 24 hours and 7 days, from [times], in time or, without
/// [durations], as a share of each; and the last event with them, or
/// looking on, the next. Beside them, their relationship [health] and
/// its [trend], with its [consistency] under it, and a [menu]. Self has no time with themself, so says
/// "You" instead.
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.person,
    this.circles = const [],
    this.health,
    this.trend = const [],
    this.consistency = 0,
    this.times,
    this.durations = true,
    this.onTap,
    this.menu,
  });

  final Person person;
  final List<String> circles;
  final int? health;
  final List<int?> trend;

  /// Days healthy in a row; 0 for none.
  final int consistency;
  final PeopleTimes? times;
  final bool durations;
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
        ?timeLine(
          times!.window,
          times!.day(person.id),
          times!.week(person.id),
          durations: durations,
        ),
        nearestLine(context, times!.window, times!.nearest(person.id)),
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
            HealthDot(
              rating: health,
              scale: HealthScale.relationship,
              consistency: consistency,
            ),
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
}

/// A circle in the People pane, as a [PersonTile] is: its name, how many
/// are in it, and its note; with [times], the time with any of its people
/// in the summary's 24 hours and 7 days and the last (or next) event with
/// any of them. Beside it, its relationship [health] and its [trend].
class CircleTile extends StatelessWidget {
  const CircleTile({
    super.key,
    required this.circle,
    required this.members,
    this.health,
    this.trend = const [],
    this.times,
    this.durations = true,
    this.onTap,
  });

  final Circle circle;

  /// How many people are in it.
  final int members;
  final int? health;
  final List<int?> trend;
  final PeopleTimes? times;
  final bool durations;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final more = [
      if (times case final times?) ...[
        ?timeLine(
          times.window,
          times.circleDay(circle.id),
          times.circleWeek(circle.id),
          durations: durations,
        ),
        nearestLine(context, times.window, times.circleNearest(circle.id)),
      ],
    ];
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: switch (health) {
                final h? => relationshipColor(h),
                null => theme.colorScheme.onSurfaceVariant,
              },
              child: const Icon(Icons.groups),
            ),
            title: Text(circleName(circle), overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                '$members ${members == 1 ? 'person' : 'people'}',
                ?circle.note,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trend.nonNulls.isNotEmpty) ...[
                  TrendSparkline(trend: trend, scale: HealthScale.relationship),
                  const SizedBox(width: 8),
                ],
                if (health != null)
                  HealthDot(rating: health, scale: HealthScale.relationship),
              ],
            ),
          ),
          if (more.isNotEmpty)
            Padding(
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
}

/// The time with someone, or a circle's people, in [window]'s 24 hours
/// ([day]) and 7 days ([week]): "24h 1h 30m · 7d 4h", or, without
/// [durations], as shares: "24h 6% · 7d 2%"; "–" for none. Null until
/// it's measured.
String? timeLine(
  SummaryWindow window,
  Duration? day,
  Duration? week, {
  bool durations = true,
}) {
  if (day == null || week == null) return null;
  // None, as the summary's legend says it.
  String amount(Duration time, Duration of) => time == Duration.zero
      ? '–'
      : durations
      ? formatDuration(Duration(minutes: (time.inSeconds / 60).round()))!
      : '${(100 * time.inSeconds / of.inSeconds).round()}%';
  final (dayLabel, weekLabel) = window.labels;
  return '$dayLabel ${amount(day, const Duration(hours: 24))} · '
      '$weekLabel ${amount(week, const Duration(days: 7))}';
}

/// The last [event] before [window], or looking on, the next: "Last:
/// Dinner · Thu, Oct 1, 6:30 PM", "Next: ...".
String nearestLine(BuildContext context, SummaryWindow window, Event? event) {
  final next = window.forward;
  if (event == null) return next ? 'Nothing planned' : 'Not seen lately';
  final localizations = MaterialLocalizations.of(context);
  final when =
      '${localizations.formatMediumDate(event.start)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(event.start))}';
  return '${next ? 'Next' : 'Last'}: '
      '${event.summary?.isNotEmpty ?? false ? event.summary : '(no title)'}'
      ' · $when';
}
