import 'package:flutter/material.dart';

import 'durations.dart';

/// A length of time in hours and minutes, kept in [controller] as whole
/// minutes ("90") -- or, while what's typed isn't a length of time, as
/// typed, for whatever checks it to say so. Written as one would --
/// "1h 30m", "90m", "90" (minutes) or "1:30" -- or set with steppers: an
/// hour, or [step] minutes, at a time -- or, with [days], a length of
/// days: written "1w 2d" or "1d 3h", with steppers a week and a day at a
/// time, anything shorter typed. Calls [onChanged] after each change.
class DurationField extends StatefulWidget {
  const DurationField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.step = 15,
    this.days = false,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback? onChanged;
  final int step;
  final bool days;

  @override
  State<DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<DurationField> {
  late final _text = TextEditingController(text: _shown(_minutes, widget.days));
  final _focus = FocusNode();

  /// The minutes kept, if they're a number.
  int? get _minutes => num.tryParse(widget.controller.text.trim())?.round();

  static String _shown(int? minutes, bool days) => switch (minutes) {
    null => '',
    final m when days => formatDays(Duration(minutes: m)),
    final m => formatDuration(Duration(minutes: m))!,
  };

  /// Whether what's typed isn't a length of time.
  bool get _invalid =>
      _text.text.trim().isNotEmpty && parseDuration(_text.text) == null;

  @override
  void initState() {
    super.initState();
    // Written out tidily once it's left.
    _focus.addListener(() {
      if (!_focus.hasFocus && !_invalid) {
        setState(() => _text.text = _shown(_minutes, widget.days));
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final duration = text.trim().isEmpty ? null : parseDuration(text);
    widget.controller.text = switch (duration) {
      final d? => '${d.inMinutes}',
      null => text.trim(),
    };
    setState(() {});
    widget.onChanged?.call();
  }

  /// Moves it by [minutes], no lower than nothing.
  void _step(int minutes) {
    final next = ((_minutes ?? 0) + minutes).clamp(0, 100000);
    widget.controller.text = '$next';
    setState(() => _text.text = _shown(next, widget.days));
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _minutes ?? 0;
    const day = Duration.minutesPerDay;
    final steppers = widget.days
        ? [
            _stepper(
              theme,
              value: '${minutes ~/ (7 * day)} w',
              less: 'A week less',
              more: 'A week more',
              onLess: minutes >= 7 * day ? () => _step(-7 * day) : null,
              onMore: () => _step(7 * day),
            ),
            _stepper(
              theme,
              value: '${minutes % (7 * day) ~/ day} d',
              less: 'A day less',
              more: 'A day more',
              onLess: minutes >= day ? () => _step(-day) : null,
              onMore: () => _step(day),
            ),
          ]
        : [
            _stepper(
              theme,
              value: '${minutes ~/ 60} h',
              less: 'An hour less',
              more: 'An hour more',
              onLess: minutes >= 60 ? () => _step(-60) : null,
              onMore: () => _step(60),
            ),
            _stepper(
              theme,
              value: '${minutes % 60} m',
              less: '${widget.step} minutes less',
              more: '${widget.step} minutes more',
              onLess: minutes > 0 ? () => _step(-widget.step) : null,
              onMore: () => _step(widget.step),
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _text,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.days ? 'e.g. 1d' : 'e.g. 1h 30m',
            helperText: widget.days
                ? 'Weeks, days, hours: "1w", "2d" or "1d 3h"'
                : 'Hours and minutes: "1h 30m", "90m" or "1:30"',
            errorText: _invalid
                ? (widget.days
                      ? 'A length of time, like "1d" or "1w 2d"'
                      : 'Hours and minutes, like "1h 30m"')
                : null,
            isDense: true,
            border: const OutlineInputBorder(),
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          onChanged: _typed,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: steppers,
          ),
        ),
      ],
    );
  }

  Widget _stepper(
    ThemeData theme, {
    required String value,
    required String less,
    required String more,
    required VoidCallback? onLess,
    required VoidCallback onMore,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.outlined(
        tooltip: less,
        icon: const Icon(Icons.remove),
        onPressed: onLess,
      ),
      SizedBox(
        width: 52,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      ),
      IconButton.outlined(
        tooltip: more,
        icon: const Icon(Icons.add),
        onPressed: onMore,
      ),
    ],
  );
}
