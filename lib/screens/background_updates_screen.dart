import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/schedule_hints.dart';
import '../services/app_settings.dart';
import '../services/background_refresh.dart';
import '../services/weather.dart';

/// How the app keeps what it shows fresh while it's closed: a fetch a
/// while after each time Claude's routines run -- their times read from
/// the server, which the routines set, and listed here, not edited --
/// again every so often while a proposal expected after one hasn't come
/// (the user says which, with each's "Expect proposal"), and
/// otherwise every [refreshFallback], said plainly; when the next is
/// due, and why; and what the last did. How long after, and how often
/// again, are set here, under a "Time Tracker" heading. Above it all,
/// under "Weather", is how often the weather's fetched, while it's on,
/// and what its last fetch did. Background fetches are Android's:
/// elsewhere -- a browser's tab -- it warns that the app checks only
/// while it's open, and has how often it does ([AppSettings.openRefresh])
/// and how long after each routine, when it checks next and when it last
/// did, in place of the background's.
class BackgroundUpdatesScreen extends StatefulWidget {
  const BackgroundUpdatesScreen({super.key, required this.refresh});

  final BackgroundRefresh refresh;

  @override
  State<BackgroundUpdatesScreen> createState() =>
      _BackgroundUpdatesScreenState();
}

class _BackgroundUpdatesScreenState extends State<BackgroundUpdatesScreen> {
  @override
  void initState() {
    super.initState();
    widget.refresh.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = MaterialLocalizations.of(context);
    String at(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    String clock(ScheduleHint h) =>
        strings.formatTimeOfDay(TimeOfDay(hour: h.hour, minute: h.minute));
    String day(DateTime t) {
      final now = widget.refresh.now;
      final today = DateTime(now.year, now.month, now.day);
      final then = DateTime(t.year, t.month, t.day);
      return switch (then.difference(today).inDays) {
        0 => 'Today',
        1 => 'Tomorrow',
        -1 => 'Yesterday',
        _ => strings.formatMediumDate(t),
      };
    }

    final fallback = refreshFallback.inHours;
    final window = retryWindow.inHours;
    return Scaffold(
      appBar: AppBar(title: const Text('Background updates')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.refresh,
          widget.refresh.settings,
          ?widget.refresh.weather,
        ]),
        builder: (context, _) {
          final refresh = widget.refresh;
          final settings = refresh.settings;
          final delay = settings.refreshDelay.inMinutes;
          final retry = settings.retryInterval?.inMinutes;
          final hints = refresh.hints;
          final next = refresh.next;
          final last = refresh.last;
          return RefreshIndicator(
            onRefresh: refresh.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
              children: [
                if (!refresh.supported)
                  _Banner(
                    icon: Icons.warning_amber_rounded,
                    text: kIsWeb
                        ? "Keep this tab open: in a browser, the app checks "
                              "for what's new only while its tab's open -- "
                              'behind other tabs, too. Once the tab is '
                              'closed, nothing runs. On Android, it updates '
                              'in the background.'
                        : "Keep the app open: here, it checks for what's "
                              "new only while it's open. On Android, it "
                              'updates in the background.',
                  ),
                if (refresh.weather != null)
                  ..._weather(theme, refresh, refresh.weather!, day, at),
                _section(theme, 'Time Tracker'),
                if (!refresh.supported)
                  ..._live(theme, refresh, day, at)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'So what the app shows is fresh when you open it, it '
                      'fetches in the background: $delay minutes after each '
                      "time Claude's routines run, and otherwise every "
                      '$fallback hours.'
                      '${switch (retry) {
                        final retry? => ' After a routine you expect a proposal from, until one through its time comes, it checks again every $retry minutes, for up to $window hours.',
                        null => '',
                      }}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (refresh.supported) ...[
                  ListTile(
                    leading: const Icon(Icons.update),
                    title: Text('Next: about ${at(next.at)}'),
                    subtitle: Text(
                      '${day(next.at)} · ${switch (next.hint) {
                        final h? when next.retry => "checking again for ${h.label ?? clock(h)}'s proposal: it hasn't come",
                        final h? => '$delay minutes after ${h.label ?? clock(h)}',
                        null => 'the $fallback-hourly update: no routine runs sooner',
                      }}\nAndroid picks the moment: it may be later while '
                      "the phone's idle.",
                    ),
                    isThreeLine: true,
                  ),
                  ListTile(
                    leading: Icon(
                      last == null || last.ok
                          ? Icons.history
                          : Icons.error_outline,
                    ),
                    title: Text(switch (last) {
                      null => 'Last: none yet',
                      final l => 'Last: ${day(l.at)}, ${at(l.at)}',
                    }),
                    subtitle: last == null
                        ? null
                        : Text(switch (last) {
                            RefreshRecord(signedOut: true) =>
                              'You were signed out: sign in for it to '
                                  'update.',
                            RefreshRecord(:final failed)
                                when failed.isNotEmpty =>
                              "Couldn't fetch ${failed.join(', ')}; "
                                  'fetched ${last.fetched.isEmpty ? 'nothing' : last.fetched.join(', ')}.',
                            _ => 'Fetched ${last.fetched.join(', ')}.',
                          }),
                  ),
                  _heading(theme, 'Timing'),
                  _refreshDelayTile(settings),
                  ListTile(
                    leading: const Icon(Icons.replay),
                    title: const Text('Until a proposal comes'),
                    subtitle: Text(
                      'How often to check again after a routine you expect '
                      "a proposal from, if it hasn't come: for up to "
                      '$window hours.',
                    ),
                    trailing: DropdownButton<Duration?>(
                      value: settings.retryInterval,
                      onChanged: settings.setRetryInterval,
                      items: [
                        for (final d in {
                          ...AppSettings.retryIntervals,
                          settings.retryInterval,
                        })
                          DropdownMenuItem(
                            value: d,
                            child: Text(
                              d == null ? "Don't" : 'Every ${d.inMinutes} min',
                            ),
                          ),
                      ],
                    ),
                  ),
                  _note(
                    theme,
                    'Android picks the moment, and may hold a fetch back '
                    "while the phone's idle or the app's little used -- "
                    'by hours, sometimes.',
                  ),
                ],
                _heading(theme, "When Claude's routines run"),
                if (refresh.unavailable && hints == null)
                  _note(
                    theme,
                    "The server doesn't give its routines' times yet, so "
                    '${refresh.supported ? 'only the $fallback-hourly updates run' : 'only the checks every so often run'}.',
                  )
                else if (hints == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  )
                else if (hints.hints.isEmpty)
                  _note(
                    theme,
                    "None yet: Claude's routines say when they run. Until "
                    'they do, ${refresh.supported ? 'only the $fallback-hourly updates run' : 'only the checks every so often run'}.',
                  )
                else
                  for (final h in hints.hints)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(clock(h)),
                      subtitle: Text(
                        [
                          ?h.label,
                          '${refresh.supported ? 'Update' : 'Check'} ≈ ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(DateTime(2000, 1, 1, h.hour, h.minute).add(settings.refreshDelay)))}',
                        ].join('\n'),
                      ),
                      trailing: !refresh.supported
                          ? null
                          : FilterChip(
                              label: const Text('Expect proposal'),
                              tooltip:
                                  'Check again until a proposal through this time '
                                  'comes',
                              selected: settings.expectsProposal(h),
                              onSelected: (expects) =>
                                  settings.setExpectsProposal(h, expects),
                            ),
                    ),
                _note(
                  theme,
                  "Set by Claude's routines, on the server; the app can't "
                  'change them.'
                  '${switch (hints?.timeZone) {
                    final zone? => ' Their times are in the calendar\'s time zone, $zone, which the app takes as the phone\'s.',
                    null => '',
                  }}',
                ),
                if (refresh.supported) _heading(theme, 'Otherwise'),
                if (refresh.supported)
                  ListTile(
                    leading: const Icon(Icons.autorenew),
                    title: Text('Every $fallback hours'),
                    subtitle: Text(
                      'When no routine runs sooner, the app updates '
                      '$fallback hours after it last planned to -- and '
                      "whenever it's opened.",
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The weather's own background fetch: how often, and what the last
  /// did.
  List<Widget> _weather(
    ThemeData theme,
    BackgroundRefresh refresh,
    Weather weather,
    String Function(DateTime) day,
    String Function(DateTime) at,
  ) {
    final settings = refresh.settings;
    final last = refresh.weatherLast;
    String every(Duration? d) => switch (d?.inMinutes) {
      null => 'Off',
      60 => 'Every hour',
      final m when m % 60 == 0 => 'Every ${m ~/ 60} hours',
      final m => 'Every $m min',
    };
    return [
      _section(theme, 'Weather'),
      ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('Forecast'),
        subtitle: Text(
          refresh.supported
              ? "Fetched this often, so it's up to date when you open the app."
              : 'Fetched every '
                    '${BackgroundRefresh.liveWeatherEvery.inMinutes} minutes '
                    'while ${kIsWeb ? "the tab's" : "the app's"} open.',
        ),
        trailing: !refresh.supported
            ? null
            : DropdownButton<Duration?>(
                value: settings.weatherRefresh,
                onChanged: settings.setWeatherRefresh,
                items: [
                  for (final d in {
                    ...AppSettings.weatherRefreshIntervals,
                    settings.weatherRefresh,
                  })
                    DropdownMenuItem(value: d, child: Text(every(d))),
                ],
              ),
      ),
      if (!weather.enabled)
        _note(theme, 'The weather is off: turn it on in Settings.')
      else ...[
        if (weather.usesDevice && refresh.supported)
          _note(
            theme,
            'For where the device was last found while the app was open: '
            "in the background, it's never asked where it is, so needs no "
            'leave to be.',
          ),
        if (settings.weatherRefresh != null && refresh.supported)
          ListTile(
            leading: Icon(
              last == null || last.ok ? Icons.history : Icons.error_outline,
            ),
            title: Text(switch (last) {
              null => 'Last: none yet',
              final l => 'Last: ${day(l.at)}, ${at(l.at)}',
            }),
            subtitle: switch (last) {
              WeatherRefreshRecord(:final problem?) => Text(problem),
              null => null,
              _ => const Text('Fetched the forecast.'),
            },
          ),
      ],
    ];
  }

  /// Where nothing runs in the background: how often the app checks
  /// while it's open, and after each routine; when it checks next, and
  /// when it last did.
  List<Widget> _live(
    ThemeData theme,
    BackgroundRefresh refresh,
    String Function(DateTime) day,
    String Function(DateTime) at,
  ) {
    final settings = refresh.settings;
    final every = settings.openRefresh?.inMinutes;
    final delay = settings.refreshDelay.inMinutes;
    final open = kIsWeb ? "the tab's" : "the app's";
    final next = refresh.liveNext;
    final last = refresh.liveLast;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'While $open open, it checks the server for what\'s new and shows '
          'it: ${every == null ? '' : 'every $every minutes, and '}$delay '
          "minutes after each time Claude's routines run. R, or pulling a "
          'page down, checks at once.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
      if (next != null)
        ListTile(
          leading: const Icon(Icons.update),
          title: Text('Next: about ${at(next)}'),
          subtitle: Text(
            "${day(next)} · if a dialog's open then, once it's closed",
          ),
        ),
      ListTile(
        leading: const Icon(Icons.history),
        title: Text(switch (last) {
          null => 'Last: none yet',
          final l => 'Last: ${day(l)}, ${at(l)}',
        }),
      ),
      _heading(theme, 'Timing'),
      ListTile(
        leading: const Icon(Icons.autorenew),
        title: const Text('Check every'),
        subtitle: Text("How often to check for what's new while $open open."),
        trailing: DropdownButton<Duration?>(
          value: settings.openRefresh,
          onChanged: settings.setOpenRefresh,
          items: [
            for (final d in {
              ...AppSettings.openRefreshIntervals,
              settings.openRefresh,
            })
              DropdownMenuItem(
                value: d,
                child: Text(d == null ? "Don't" : '${d.inMinutes} min'),
              ),
          ],
        ),
      ),
      _refreshDelayTile(settings),
    ];
  }

  /// How long after each routine to fetch.
  Widget _refreshDelayTile(AppSettings settings) => ListTile(
    leading: const Icon(Icons.timer_outlined),
    title: const Text('After each routine'),
    subtitle: const Text(
      'How long after its time to fetch what it made: it takes a while '
      'to run.',
    ),
    trailing: DropdownButton<Duration>(
      value: settings.refreshDelay,
      onChanged: (d) {
        if (d != null) settings.setRefreshDelay(d);
      },
      items: [
        for (final d in {...AppSettings.refreshDelays, settings.refreshDelay})
          DropdownMenuItem(value: d, child: Text('${d.inMinutes} min')),
      ],
    ),
  );

  /// A heading over all that's fetched for one thing: the weather, or
  /// Time Tracker's own.
  Widget _section(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  /// A heading over part of a [_section].
  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: theme.textTheme.titleMedium),
  );

  Widget _note(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
