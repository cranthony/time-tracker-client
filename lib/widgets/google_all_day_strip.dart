import 'package:flutter/material.dart';

import '../models/google_calendar.dart';

/// The whole-day Google Calendar events on the day shown, above its
/// timeline, so they're in sight wherever it's scrolled to: a pill each,
/// or, [collapsed], one line naming them. Tapping a pill calls [onTap].
class GoogleAllDayStrip extends StatelessWidget {
  const GoogleAllDayStrip({
    super.key,
    required this.events,
    required this.collapsed,
    required this.onCollapsed,
    this.onTap,
  });

  final List<GoogleEvent> events;
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;
  final ValueChanged<GoogleEvent>? onTap;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final toggle = IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: collapsed ? 'Show all-day events' : 'Hide all-day events',
      icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
      onPressed: () => onCollapsed(!collapsed),
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: collapsed ? () => onCollapsed(false) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: collapsed
              ? Row(
                  children: [
                    for (final e in events.take(5))
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: _Dot(color: e.calendar.color),
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${events.length} all day · '
                        '${events.map((e) => e.title).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    toggle,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final e in events)
                              _Pill(
                                event: e,
                                onTap: onTap == null ? null : () => onTap!(e),
                              ),
                          ],
                        ),
                      ),
                    ),
                    toggle,
                  ],
                ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// [event] as a pill in its calendar's color, saying so if it spans more
/// days than this one.
class _Pill extends StatelessWidget {
  const _Pill({required this.event, this.onTap});

  final GoogleEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = event.calendar.color;
    final ink = dark
        ? Color.lerp(color, Colors.white, 0.55)!
        : Color.lerp(color, Colors.black, 0.45)!;
    final days = event.end.difference(event.start).inHours / 24;
    final local = MaterialLocalizations.of(context);
    final last = event.end.subtract(const Duration(days: 1));
    return Semantics(
      label: '${event.title}, all day, ${event.calendar.name}',
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: dark ? 0.3 : 0.18),
        shape: StadiumBorder(
          side: BorderSide(color: color.withValues(alpha: 0.75)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: event.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (days > 1.5)
                    TextSpan(
                      text: '  until ${local.formatShortMonthDay(last)}',
                    ),
                ],
              ),
              style: theme.textTheme.labelMedium?.copyWith(color: ink),
            ),
          ),
        ),
      ),
    );
  }
}
