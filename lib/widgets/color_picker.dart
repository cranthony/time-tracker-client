import 'package:flutter/material.dart';

/// A color from "#rrggbb", or null if [hex] isn't one.
Color? parseColor(String? hex) {
  if (hex == null) return null;
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match[1]!, radix: 16));
}

/// [color] as "#rrggbb", as the server stores label colors.
String colorToHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Black or white, whichever reads better on [color].
Color contrastingColor(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// The priority an event or action with none, anywhere up its tree, is
/// treated as, and colored as.
const defaultPriority = 2;

/// The priorities with a color of their own: any past these takes the
/// nearest one's.
const priorities = [0, 1, 2, 3];

/// Each priority's color until the server says otherwise: the server's
/// own defaults.
const defaultPriorityColors = {
  0: Color(0xFFE1E1E1),
  1: Color(0xFFFBD75B),
  2: Color(0xFFA4BDFC),
  3: Color(0xFF7AE7BF),
};

/// Each priority's color, as the server colors events and labels: its
/// priority label's (`get_priority_colors`). Set by [applyPriorityColors].
final priorityPalette = ValueNotifier<Map<int, Color>>(defaultPriorityColors);

/// Sets [priorityPalette] from what `get_priority_colors` answered: a list
/// of {priority, color}. Leaves the colors as they are if [result] isn't
/// one, and keeps a priority's if it's missing or not a color.
void applyPriorityColors(Object? result) {
  if (result is! List) return;
  final colors = {...priorityPalette.value};
  for (final entry in result) {
    if (entry is! Map) continue;
    final priority = entry['priority'];
    final color = parseColor(entry['color'] as String?);
    if (priority is int && color != null) colors[priority] = color;
  }
  priorityPalette.value = colors;
}

/// The color of [priority], or of [defaultPriority] if null.
Color priorityColor(int? priority) {
  final p = (priority ?? defaultPriority).clamp(0, 3);
  return priorityPalette.value[p] ?? defaultPriorityColors[p]!;
}

/// Google Calendar's calendar colors, by hue then shade.
const calendarColors = [
  Color(0xFFAC725E),
  Color(0xFFD06B64),
  Color(0xFFF83A22),
  Color(0xFFFA573C),
  Color(0xFFFF7537),
  Color(0xFFFFAD46),
  Color(0xFFFAD165),
  Color(0xFFFBE983),
  Color(0xFFB3DC6C),
  Color(0xFF7BD148),
  Color(0xFF16A765),
  Color(0xFF42D692),
  Color(0xFF92E1C0),
  Color(0xFF9FE1E7),
  Color(0xFF9FC6E7),
  Color(0xFF4986E7),
  Color(0xFF9A9CFF),
  Color(0xFFB99AFF),
  Color(0xFFA47AE2),
  Color(0xFFCD74E6),
  Color(0xFFF691B2),
  Color(0xFFCCA6AC),
  Color(0xFFCABDBF),
  Color(0xFFC2C2C2),
];

/// A round swatch of [color], outlined so pale colors still show.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.color, this.size = 16});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}

/// Picks a color: one of [calendarColors], or any other from a
/// saturation-and-brightness square and a hue bar, or typed as hex.
/// "No color" clears it. Calls [onChanged] with every change, null for no
/// color.
class ColorPicker extends StatefulWidget {
  const ColorPicker({super.key, required this.color, required this.onChanged});

  final Color? color;
  final ValueChanged<Color?> onChanged;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color ?? calendarColors[9]);
  late final _hex = TextEditingController(
    text: widget.color == null ? '' : colorToHex(widget.color!),
  );
  String? _hexError;

  /// "No color" is picked.
  late bool _none = widget.color == null;

  /// Shows the square and hue bar; starts open for a color off the palette.
  late bool _custom =
      widget.color != null &&
      !calendarColors.map(colorToHex).contains(colorToHex(widget.color!));

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv, {bool fromHex = false}) {
    setState(() {
      _hsv = hsv;
      _none = false;
      if (!fromHex) {
        _hex.text = colorToHex(_color);
        _hexError = null;
      }
    });
    widget.onChanged(_color);
  }

  void _clear() {
    setState(() {
      _none = true;
      _hex.text = '';
      _hexError = null;
    });
    widget.onChanged(null);
  }

  void _typed(String text) {
    final t = text.trim();
    if (t.isEmpty) return _clear();
    final color = parseColor(t.startsWith('#') ? t : '#$t');
    if (color == null) {
      setState(() => _hexError = 'Use #rrggbb');
      return;
    }
    setState(() => _hexError = null);
    _set(HSVColor.fromColor(color), fromHex: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color? selected = _none ? null : _color.withAlpha(255);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: selected == null
                  ? Icon(
                      Icons.format_color_reset_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hex,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  labelText: 'Hex',
                  hintText: 'No color',
                  errorText: _hexError,
                ),
                style: const TextStyle(fontFamily: 'monospace'),
                onChanged: _typed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Swatch(color: null, selected: _none, onTap: _clear),
            for (final color in calendarColors)
              _Swatch(
                color: color,
                selected:
                    selected != null &&
                    colorToHex(color) == colorToHex(selected),
                onTap: () => _set(HSVColor.fromColor(color)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => setState(() => _custom = !_custom),
          icon: Icon(_custom ? Icons.expand_less : Icons.palette_outlined),
          label: Text(_custom ? 'Fewer colors' : 'More colors'),
        ),
        if (_custom) ...[
          _SaturationValuePad(
            key: const Key('saturation-value'),
            hsv: _hsv,
            onChanged: _set,
          ),
          const SizedBox(height: 12),
          _HueBar(hsv: _hsv, onChanged: _set),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// Null for "No color".
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: switch (color) {
        final c? => colorToHex(c),
        null => 'No color',
      },
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color ?? theme.colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: switch (color) {
            null => Icon(
              selected ? Icons.check : Icons.format_color_reset_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            final c when selected => Icon(
              Icons.check,
              size: 18,
              color: contrastingColor(c),
            ),
            _ => null,
          },
        ),
      ),
    );
  }
}

/// [p] across and down a box of [size] that a [_Thumb] moves in, each
/// from 0 to 1. The thumb stays inside, so its center can't reach the
/// edges.
(double, double) _fraction(Offset p, Size size) => (
  ((p.dx - _Thumb.radius) / (size.width - 2 * _Thumb.radius)).clamp(0.0, 1.0),
  ((p.dy - _Thumb.radius) / (size.height - 2 * _Thumb.radius)).clamp(0.0, 1.0),
);

/// Calls [onPick] with where in it a tap or drag is, as [_fraction] does.
///
/// Sizes come from the render box, not a LayoutBuilder: a dialog asks its
/// content for its intrinsic size, which a LayoutBuilder can't give.
class _Picker extends StatelessWidget {
  const _Picker({required this.onPick, required this.child});

  final void Function(double x, double y) onPick;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void pick(Offset p) {
      final (x, y) = _fraction(
        p,
        (context.findRenderObject()! as RenderBox).size,
      );
      onPick(x, y);
    }

    return GestureDetector(
      // The edges too, outside the gradient.
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => pick(d.localPosition),
      onPanStart: (d) => pick(d.localPosition),
      onPanUpdate: (d) => pick(d.localPosition),
      child: child,
    );
  }
}

/// Saturation across, brightness down, for [hsv]'s hue.
class _SaturationValuePad extends StatelessWidget {
  const _SaturationValuePad({
    super.key,
    required this.hsv,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => _Picker(
    onPick: (x, y) => onChanged(hsv.withSaturation(x).withValue(1 - y)),
    child: SizedBox(
      width: double.infinity,
      height: 140,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(_Thumb.radius / 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    Colors.white,
                    HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                  ],
                ),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment(
              hsv.saturation * 2 - 1,
              (1 - hsv.value) * 2 - 1,
            ),
            child: _Thumb(color: hsv.toColor()),
          ),
        ],
      ),
    ),
  );
}

/// The hue, around the color wheel.
class _HueBar extends StatelessWidget {
  const _HueBar({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => _Picker(
    onPick: (x, _) => onChanged(hsv.withHue(x * 359.9)),
    child: SizedBox(
      width: double.infinity,
      height: 2 * _Thumb.radius,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: _Thumb.radius / 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: LinearGradient(
                colors: [
                  for (var h = 0; h <= 360; h += 60)
                    HSVColor.fromAHSV(1, h % 360, 1, 1).toColor(),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment(hsv.hue / 359.9 * 2 - 1, 0),
            child: _Thumb(color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()),
          ),
        ],
      ),
    ),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  static const radius = 10.0;

  @override
  Widget build(BuildContext context) => Container(
    width: 2 * radius,
    height: 2 * radius,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
    ),
  );
}
