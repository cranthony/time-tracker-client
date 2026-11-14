import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/trait.dart';
import '../models/trait_icon.dart';

/// [trait]'s icon, drawn as an icon is, [size] square in [color] -- by
/// default the [IconTheme]'s: its SVG's `currentColor`, and everything it
/// paints, in that one colour. Labelled with the trait's name, and with
/// [tooltip], showing it. Nothing, if it has no icon or its icon can't be
/// drawn ([hasIcon]).
class TraitIcon extends StatelessWidget {
  const TraitIcon(
    this.trait, {
    super.key,
    this.size,
    this.color,
    this.tooltip = false,
  });

  final Trait trait;

  /// As an [Icon]'s: the [IconTheme]'s, if null.
  final double? size;
  final Color? color;
  final bool tooltip;

  /// Whether [trait] has an icon to draw.
  static bool hasIcon(Trait trait) => switch (trait.icon) {
    final svg? => traitIconDrawable(svg),
    null => false,
  };

  @override
  Widget build(BuildContext context) {
    final svg = trait.icon;
    if (svg == null || !traitIconDrawable(svg)) return const SizedBox.shrink();
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color =
        this.color ?? theme.color ?? Theme.of(context).colorScheme.onSurface;
    final Widget icon = SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: trait.name,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
    );
    return tooltip ? Tooltip(message: trait.name, child: icon) : icon;
  }
}

/// [traits]' icons, side by side [gap] apart, each [size] square in
/// [color], with a tooltip naming it: those with one ([TraitIcon.hasIcon]).
class TraitIconRow extends StatelessWidget {
  const TraitIconRow(
    this.traits, {
    super.key,
    this.size = 16,
    this.color,
    this.gap = 4,
  });

  final List<Trait> traits;
  final double size;
  final Color? color;
  final double gap;

  /// How wide [count] icons are, [size] square and [gap] apart.
  static double widthOf(int count, {double size = 16, double gap = 4}) =>
      count == 0 ? 0 : count * size + (count - 1) * gap;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final t in traits)
        if (TraitIcon.hasIcon(t)) t,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, trait) in shown.indexed) ...[
          if (i > 0) SizedBox(width: gap),
          TraitIcon(trait, size: size, color: color, tooltip: true),
        ],
      ],
    );
  }
}

/// [trait]'s name -- or [text], naming it -- in [style], after its icon
/// if it has one, in the text's colour: without one, just the text.
Widget traitTitle(Trait trait, {String? text, TextStyle? style}) =>
    TraitIcon.hasIcon(trait)
    ? _TraitTitle(trait, text: text, style: style)
    : Text(text ?? trait.name, style: style);

class _TraitTitle extends StatelessWidget {
  const _TraitTitle(this.trait, {this.text, this.style});

  final Trait trait;
  final String? text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final shown = DefaultTextStyle.of(context).style.merge(style);
    final size = (shown.fontSize ?? 14) * 1.25;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: TraitIcon(
            trait,
            size: size < 16 ? 16 : size,
            color: shown.color,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(text ?? trait.name, style: style)),
      ],
    );
  }
}
