import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/circadian.dart';
import '../services/circadian_repository.dart';
import '../widgets/edit_page.dart';
import '../widgets/error_sheet.dart';

/// Opens the [CircadianScreen] for [circadian], on a page of its own.
Future<void> showCircadianRhythm(
  BuildContext context, {
  required Circadian circadian,
}) => showEditPage<void>(context, CircadianScreen(circadian: circadian));

/// The user's circadian rhythm: when they wake naturally now, and the
/// temperature minimum and windows worked out from it; a way to say when
/// they woke naturally on a day, in place of what was said of it; the
/// windows' widths, to change; and what's been said before, newest first.
class CircadianScreen extends StatefulWidget {
  const CircadianScreen({super.key, required this.circadian, this.clock});

  final Circadian circadian;

  /// Now; by default, the device's.
  final DateTime Function()? clock;

  @override
  State<CircadianScreen> createState() => _CircadianScreenState();
}

class _CircadianScreenState extends State<CircadianScreen> {
  DateTime get _now => (widget.clock ?? DateTime.now)();
  DateTime get _today => DateTime(_now.year, _now.month, _now.day);

  CircadianRhythm get _rhythm =>
      widget.circadian.rhythm ?? const CircadianRhythm();

  late DateTime _date = _today;
  late TimeOfDay _time = switch (_rhythm.revisionOn(_today)) {
    final r? => TimeOfDay(hour: r.hour, minute: r.minute),
    null => const TimeOfDay(hour: 7, minute: 0),
  };
  final _note = TextEditingController();
  bool _recording = false;

  late final _minimum = TextEditingController(
    text: '${_rhythm.windows.minimumBeforeWaking}',
  );
  late final _dim = TextEditingController(text: '${_rhythm.windows.dimBefore}');
  late final _bright = TextEditingController(
    text: '${_rhythm.windows.brightAfter}',
  );
  bool _savingWindows = false;

  @override
  void dispose() {
    for (final c in [_note, _minimum, _dim, _bright]) {
      c.dispose();
    }
    super.dispose();
  }

  String _clock(DateTime t) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(t));

  /// "Fri, Oct 30", and its year if it's not this one's.
  String _day(DateTime d) {
    final date = MaterialLocalizations.of(context).formatMediumDate(d);
    return d.year == _today.year ? date : '$date, ${d.year}';
  }

  Future<void> _record() async {
    setState(() => _recording = true);
    try {
      final note = _note.text.trim();
      await widget.circadian.setNaturalWakeTime(
        _date,
        hour: _time.hour,
        minute: _time.minute,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      _note.clear();
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Saved for ${_day(_date)}')));
    } catch (e) {
      if (!mounted) return;
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        onRetry: _record,
      );
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// The windows as typed; null if one isn't whole minutes up to a day.
  CircadianWindows? get _windows {
    int? minutes(TextEditingController c) =>
        switch (int.tryParse(c.text.trim())) {
          final m? when m >= 0 && m <= CircadianWindows.most => m,
          _ => null,
        };
    final (minimum, dim, bright) = (
      minutes(_minimum),
      minutes(_dim),
      minutes(_bright),
    );
    if (minimum == null || dim == null || bright == null) return null;
    return CircadianWindows(
      minimumBeforeWaking: minimum,
      dimBefore: dim,
      brightAfter: bright,
    );
  }

  Future<void> _saveWindows() async {
    final windows = _windows;
    if (windows == null) return;
    setState(() => _savingWindows = true);
    try {
      await widget.circadian.setWindows(windows);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Windows saved')));
    } catch (e) {
      if (!mounted) return;
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        onRetry: _saveWindows,
      );
    } finally {
      if (mounted) setState(() => _savingWindows = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(_today.year + 1, _today.month, _today.day),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Text(text, style: theme.textTheme.titleMedium),
  );

  /// When the user wakes naturally today, and what's worked out from it.
  List<Widget> _inEffect(ThemeData theme) {
    final day = _rhythm.dayOf(_today);
    if (day == null) {
      return [
        Text(
          "Not known yet: say below when you last woke naturally, without "
          'an alarm, and the Events page shades the hours either side of '
          'your temperature minimum.',
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }
    final wake = DateTime(
      _today.year,
      _today.month,
      _today.day,
      day.revision.hour,
      day.revision.minute,
    );
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.wb_twilight),
        title: Text('You wake naturally at ${_clock(wake)}'),
        subtitle: Text('Since ${_day(day.revision.date)}'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.thermostat),
        title: Text('Temperature minimum ${_clock(day.minimum)}'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.nightlight_outlined),
        title: Text('Dim ${_clock(day.dim.start)} to ${_clock(day.dim.end)}'),
        subtitle: const Text(
          'Light and exercise now shift your schedule later.',
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.wb_sunny_outlined),
        title: Text(
          'Bright ${_clock(day.bright.start)} to ${_clock(day.bright.end)}',
        ),
        subtitle: const Text(
          'Bright light and exercise now hold it, or shift it earlier.',
        ),
      ),
    ];
  }

  Widget _minutesField(
    TextEditingController controller,
    String label,
    String helper,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixText: 'minutes',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.circadian,
      builder: (context, _) {
        final windowsOk = _windows != null;
        return Scaffold(
          appBar: AppBar(title: const Text('Circadian rhythm')),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _heading(theme, 'Today'),
                    ..._inEffect(theme),
                    _heading(theme, 'Woke naturally'),
                    Text(
                      'When you woke without an alarm: from that day on, '
                      'until you say otherwise. A day said before is '
                      'replaced.',
                      style: theme.textTheme.bodySmall,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(_day(_date)),
                      subtitle: const Text('Day'),
                      onTap: _pickDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(_time.format(context)),
                      subtitle: const Text('Woke at'),
                      onTap: _pickTime,
                    ),
                    TextField(
                      controller: _note,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _recording ? null : _record,
                        child: const Text('Save wake time'),
                      ),
                    ),
                    _heading(theme, 'Windows'),
                    Text(
                      'How your temperature minimum and the windows either '
                      'side of it are worked out from when you wake.',
                      style: theme.textTheme.bodySmall,
                    ),
                    _minutesField(
                      _minimum,
                      'Minimum before waking',
                      'Your temperature minimum, this long before you wake.',
                    ),
                    _minutesField(
                      _dim,
                      'Dim window',
                      'This long before the minimum.',
                    ),
                    _minutesField(
                      _bright,
                      'Bright window',
                      'This long after the minimum.',
                    ),
                    if (!windowsOk)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Each is whole minutes, up to 1440: a day.',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _savingWindows || !windowsOk
                              ? null
                              : _saveWindows,
                          child: const Text('Save windows'),
                        ),
                      ),
                    ),
                    _heading(theme, 'History'),
                    if (_rhythm.revisions.isEmpty)
                      Text('Nothing yet.', style: theme.textTheme.bodySmall),
                    for (final r in _rhythm.revisions.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Woke at ${TimeOfDay(hour: r.hour, minute: r.minute).format(context)}',
                        ),
                        subtitle: Text([_day(r.date), ?r.note].join(' · ')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
