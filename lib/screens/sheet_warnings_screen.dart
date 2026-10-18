import 'package:flutter/material.dart';

import '../models/server_health.dart';
import '../services/diagnostics_repository.dart';
import '../widgets/sheet_warnings_banner.dart';
import '../widgets/status_message.dart';

/// What the server found changed behind its back, newest first -- opened
/// from [SheetWarningsBanner]: from its `get_health`, without the
/// samples.
class SheetWarningsScreen extends StatefulWidget {
  const SheetWarningsScreen({
    super.key,
    required this.repository,
    this.clock = DateTime.now,
  });

  final DiagnosticsRepository repository;
  final DateTime Function() clock;

  /// What the page says first: why the spreadsheet isn't for editing.
  static const explanation =
      'The server keeps the metadata spreadsheet, "Calendar Metadata (do '
      'not edit by hand)", as its own: it holds what the app shows, and the '
      'server works from its own copy. Every 5 minutes it compares the '
      'spreadsheet with that copy, and puts back anything edited or deleted '
      'by hand. Events changed outside the server -- in Google Calendar, '
      'say -- are taken as they are. Each time, it says so here.';

  @override
  State<SheetWarningsScreen> createState() => _SheetWarningsScreenState();
}

class _SheetWarningsScreenState extends State<SheetWarningsScreen> {
  List<SheetWarning>? _warnings;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final warnings = await widget.repository.sheetWarnings();
      if (!mounted) return;
      setState(() {
        _warnings = warnings;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warnings = _warnings;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Changes outside the server')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(SheetWarningsScreen.explanation),
            ),
            if (error != null)
              LoadError(
                what: "the server's warnings",
                error: error,
                stale: warnings != null,
                onRetry: _load,
              )
            else if (warnings == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (warnings.isEmpty)
              const StatusMessage(
                icon: Icons.check_circle_outline,
                text: 'Nothing has been changed outside the server lately.',
              ),
            if (warnings != null)
              for (final w in warnings.reversed)
                _WarningCard(warning: w, now: widget.clock()),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warning, required this.now});

  final SheetWarning warning;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final w = warning;
    final theme = Theme.of(context);
    final strings = MaterialLocalizations.of(context);
    final local = w.at.toLocal();
    final when =
        '${strings.formatMediumDate(local)}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))} '
        '(${SheetWarningsBanner.ago(now.difference(w.at))})';
    final calendar = w.kind == SheetWarningKind.calendar;
    final unit = calendar ? 'event' : 'cell';
    final count = '${w.cellCount} $unit${w.cellCount == 1 ? '' : 's'}';
    final details = [
      if (w.tab case final tab?) 'Tab "$tab"',
      if (w.kind != SheetWarningKind.deleted) count,
      if (calendar)
        'taken as changed'
      else if (w.restored)
        'put back'
      else
        'not put back',
    ].join(' · ');
    final more = w.cellCount - w.cells.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(switch (w.kind) {
                  SheetWarningKind.edited => Icons.edit_note,
                  SheetWarningKind.deleted => Icons.delete_outline,
                  SheetWarningKind.calendar => Icons.event_note,
                }, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(switch (w.kind) {
                    SheetWarningKind.edited => 'Cells edited by hand',
                    SheetWarningKind.deleted => 'Tab deleted by hand',
                    SheetWarningKind.calendar =>
                      'Events changed outside the server',
                  }, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(when, style: theme.textTheme.bodySmall),
            Text(details, style: theme.textTheme.bodySmall),
            if (w.cells.isNotEmpty) const SizedBox(height: 8),
            for (final c in w.cells)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  calendar
                      ? '${c.found} -- ${c.cell}'
                      : '${c.cell}: ${_shown(c.found)} → ${_shown(c.kept)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('and $more more', style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  /// A cell's value as shown: quoted, and "(empty)" when it's blank.
  static String _shown(String value) => value.isEmpty ? '(empty)' : '"$value"';
}
