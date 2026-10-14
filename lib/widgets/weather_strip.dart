import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/weather.dart';
import '../services/app_settings.dart';
import '../services/weather.dart';
import 'weather_style.dart';

/// The weather for the day shown, above its timeline: its sky's icon,
/// its high and low, and its chance of rain -- today's from now -- and,
/// today, whether rain's coming in the next few hours. Under that, the
/// week's days, each with its icon and chance of rain: tapping one goes
/// to it ([onDay]). [collapsed], just the first line. Nothing for a day
/// that's past: only what's to come.
///
/// Before there's a forecast, it says why not: being fetched, failed (to
/// try again), or the app not let know where the device is.
class WeatherStrip extends StatelessWidget {
  const WeatherStrip({
    super.key,
    required this.weather,
    required this.day,
    required this.now,
    required this.collapsed,
    required this.onCollapsed,
    this.onDay,
  });

  final Weather weather;

  /// Midnight at the start of the day shown.
  final DateTime day;
  final DateTime now;
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;
  final ValueChanged<DateTime>? onDay;

  /// The open-meteo.com page its data's credited to.
  static final creditUrl = Uri.parse('https://open-meteo.com/');

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    if (day.isBefore(today)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final forecast = weather.forecast;
    final Widget body;
    if (forecast == null) {
      body = _status(context, muted);
    } else {
      final settings = AppSettings.of(context);
      final span = forecast.dayOf(day);
      final isToday = day == today;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (span != null) ...[
                Icon(
                  skyIcon(span.sky),
                  size: 20,
                  color: skyIconColor(span.sky),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  span == null
                      ? 'No forecast this far ahead'
                      : _describe(span, settings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              // Folded, its credit's here; open, after the days.
              if (collapsed) _credit(context, forecast, muted),
              _toggle(),
            ],
          ),
          if (!collapsed) ...[
            if (isToday && forecast.quarterHours.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  nowcast(
                    forecast.quarterHours,
                    now: now,
                    timeLabel: (t) =>
                        MaterialLocalizations.of(context)
                            .formatTimeOfDay(TimeOfDay.fromDateTime(t)),
                  ),
                  style: muted,
                ),
              ),
            _days(context, forecast, _credit(context, forecast, muted)),
          ],
        ],
      );
    }
    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: collapsed && forecast != null ? () => onCollapsed(false) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: body,
        ),
      ),
    );
  }

  Widget _toggle() => IconButton(
    visualDensity: VisualDensity.compact,
    tooltip: collapsed ? 'Show the week’s weather' : 'Hide the week’s weather',
    icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
    onPressed: () => onCollapsed(!collapsed),
  );

  /// "Data: Open-Meteo", opening its site, as its license asks; and how
  /// old the forecast is, if one couldn't be had since.
  Widget _credit(BuildContext context, Forecast forecast, TextStyle? style) {
    final stale = now.difference(forecast.fetchedAt) > const Duration(hours: 1);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(forecast.fetchedAt));
    return InkWell(
      onTap: () => launchUrl(creditUrl, mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          stale ? 'As of $time · ${forecast.source}' : forecast.source,
          style: style?.copyWith(fontSize: 11),
        ),
      ),
    );
  }

  /// Why there's no forecast yet, and what to do about it.
  Widget _status(BuildContext context, TextStyle? style) {
    final (text, action) = switch (weather) {
      Weather(loading: true) => ('Getting the forecast…', null),
      Weather(access: final access?) when access != LocationAccess.granted => (
        access == LocationAccess.serviceOff
            ? "The device's location is off: the weather needs it."
            : 'The weather needs to know roughly where the device is.',
        TextButton(
          onPressed: access == LocationAccess.denied
              ? weather.enable
              : weather.location.openSettings,
          child: Text(access == LocationAccess.denied ? 'Allow' : 'Settings'),
        ),
      ),
      Weather(error: _?) => (
        "Couldn't get the forecast.",
        TextButton(
          onPressed: () => weather.refresh(force: true),
          child: const Text('Try again'),
        ),
      ),
      _ => ('No forecast yet.', null),
    };
    return Row(
      children: [
        Icon(Icons.cloud_off, size: 20, color: style?.color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
        ?action,
        const SizedBox(height: 40),
      ],
    );
  }

  /// The week's days, each to go to, then the [credit].
  Widget _days(BuildContext context, Forecast forecast, Widget credit) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(
        children: [
          for (final span in forecast.days)
            if (DateTime(span.start.year, span.start.month, span.start.day)
                case final d)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _DayChip(
                  label: d == DateTime(now.year, now.month, now.day)
                      ? 'Today'
                      : _weekday(d),
                  span: span,
                  selected: d == day,
                  onTap: onDay == null ? null : () => onDay!(d),
                  style: theme.textTheme.labelMedium,
                ),
              ),
          credit,
        ],
      ),
    );
  }

  static String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

  /// [span]'s day said in a line: its sky, high and low, and its chance
  /// of rain and how much, if any's likely -- today's, from now.
  static String _describe(WeatherSpan span, AppSettings settings) {
    final temperature = settings.temperatureUnit;
    return [
      span.sky.label,
      if (span case WeatherSpan(:final high?, :final low?))
        '${temperature.format(high)} / ${temperature.format(low)}',
      if (span.rainChance case final chance? when chance >= 10) '$chance% rain',
      if (span.precipitation case final mm?
          when mm >= 0.25 && (span.rainChance ?? 100) >= 30)
        settings.precipitationUnit.format(mm),
    ].join(' · ');
  }
}

/// Whether it's likely to rain in the next few hours, in a sentence, from
/// [quarters] -- each quarter hour's chance of rain, and how much -- from
/// [now].
String nowcast(
  List<WeatherSpan> quarters, {
  required DateTime now,
  required String Function(DateTime) timeLabel,
}) {
  final ahead = [
    for (final q in quarters)
      if (q.end.isAfter(now)) q,
  ];
  if (ahead.isEmpty) return '';
  bool wet(WeatherSpan q) =>
      (q.rainChance ?? 0) >= 50 || (q.precipitation ?? 0) >= 0.1;
  final hours = (ahead.last.end.difference(now).inMinutes / 60).round();
  final over = hours <= 1 ? 'the next hour' : 'the next $hours hours';
  if (wet(ahead.first)) {
    final dry = ahead.where((q) => !wet(q)).firstOrNull;
    return dry == null
        ? 'Rain likely for $over.'
        : 'Rain likely now, easing about ${timeLabel(dry.start)}.';
  }
  if (ahead.where(wet).firstOrNull case final first?) {
    final chance = first.rainChance;
    return 'Rain likely from about ${timeLabel(first.start)}'
        '${chance == null ? '' : ' ($chance%)'}.';
  }
  final most = ahead
      .map((q) => q.rainChance ?? 0)
      .reduce((a, b) => a > b ? a : b);
  return most >= 20
      ? 'Rain unlikely in $over (at most $most%).'
      : 'No rain expected in $over.';
}

/// A day of the week's weather: its name, its sky's icon, and its chance
/// of rain if there's much.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.span,
    required this.selected,
    required this.style,
    this.onTap,
  });

  final String label;
  final WeatherSpan span;
  final bool selected;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chance = span.rainChance;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label:
          '$label, ${span.sky.label}'
          '${chance == null ? '' : ', $chance% chance of rain'}',
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? colors.secondary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: style),
                const SizedBox(width: 4),
                Icon(
                  skyIcon(span.sky),
                  size: 16,
                  color: skyIconColor(span.sky),
                ),
                if (chance != null && chance >= 20) ...[
                  const SizedBox(width: 2),
                  Text('$chance%', style: style?.copyWith(color: rainColor)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
