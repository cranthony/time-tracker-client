import 'package:flutter/material.dart';

import '../auth/sign_in_mode.dart';
import '../platform/calendar_widget.dart';
import '../screens/background_updates_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/settings_screen.dart';
import '../services/app_settings.dart';
import '../services/background_refresh.dart';
import '../services/diagnostics_repository.dart';
import 'hotkeys.dart';
import 'status_bar.dart';

/// The app bar's menu: Settings, Background updates, Changes waiting to
/// save and Diagnostics, when the app has them (a [BackgroundRefreshScope],
/// a [StatusScope] or a [DiagnosticsScope] above), Hotkeys, on the web
/// or once a keyboard's been used ([hotkeysOffered]), About, and Sign
/// out when [onSignOut] is set. Ctrl held, it shows "?", for the list of
/// hotkeys. Builds for the emulator test offer to add
/// the home screen calendar too ([CalendarWidget.pinOffered]).
class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.serverLabel,
    this.version,
    this.onSignOut,
  });

  /// Which server this build talks to, or that it's the offline demo.
  final String serverLabel;

  /// The app's version; null until it's known.
  final String? version;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final refresh = BackgroundRefresh.of(context);
    final status = StatusScope.of(context);
    final diagnostics = DiagnosticsScope.of(context);
    final settings = AppSettings.of(context);
    return HotkeyHint(
      Hotkey.help,
      child: _menu(context, refresh, status, diagnostics, settings),
    );
  }

  Widget _menu(
    BuildContext context,
    BackgroundRefresh? refresh,
    StatusScope? status,
    DiagnosticsScope? diagnostics,
    AppSettings settings,
  ) {
    return PopupMenuButton<_MenuItem>(
      onSelected: (item) => switch (item) {
        _MenuItem.settings => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(settings: settings),
          ),
        ),
        _MenuItem.updates => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BackgroundUpdatesScreen(refresh: refresh!),
          ),
        ),
        _MenuItem.outbox => status!.show(context),
        _MenuItem.diagnostics => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiagnosticsScreen(
              repository: diagnostics!.repository,
              client: diagnostics.client,
            ),
          ),
        ),
        _MenuItem.about => showAboutDialog(
          context: context,
          applicationName: 'Time Tracker',
          applicationVersion: version,
          children: [
            Text('Server: $serverLabel'),
            if (serverSignInOff.value)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Sign-in is off on the server (built with AUTH_DISABLED): '
                  'it trusts every request, relying on the network in front '
                  'of it to sign people in, so the app never signs in.',
                ),
              ),
          ],
        ),
        _MenuItem.signOut => onSignOut!(),
        _MenuItem.pinCalendar => CalendarWidget.pin(),
        _MenuItem.hotkeys => showHotkeysDialog(context),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _MenuItem.settings, child: Text('Settings')),
        if (refresh != null)
          const PopupMenuItem(
            value: _MenuItem.updates,
            child: Text('Background updates'),
          ),
        if (status != null && status.sources.isNotEmpty)
          PopupMenuItem(
            value: _MenuItem.outbox,
            child: Text(switch (status.count) {
              0 => 'Changes waiting to save',
              final n => 'Changes waiting to save ($n)',
            }),
          ),
        if (diagnostics != null)
          const PopupMenuItem(
            value: _MenuItem.diagnostics,
            child: Text('Diagnostics'),
          ),
        if (CalendarWidget.pinOffered)
          const PopupMenuItem(
            value: _MenuItem.pinCalendar,
            child: Text('Add calendar to home screen'),
          ),
        if (hotkeysOffered(context))
          const PopupMenuItem(value: _MenuItem.hotkeys, child: Text('Hotkeys')),
        const PopupMenuItem(value: _MenuItem.about, child: Text('About')),
        // Nothing to sign out of, from a server that skips sign-in.
        if (onSignOut != null && !serverSignInOff.value)
          const PopupMenuItem(
            value: _MenuItem.signOut,
            child: Text('Sign out'),
          ),
      ],
    );
  }
}

enum _MenuItem {
  settings,
  updates,
  outbox,
  diagnostics,
  pinCalendar,
  hotkeys,
  about,
  signOut,
}
