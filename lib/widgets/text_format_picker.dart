import 'package:flutter/material.dart';

import '../models/text_format.dart';

/// Picks how a text is written: plain text, Markdown or HTML.
class TextFormatPicker extends StatelessWidget {
  const TextFormatPicker({
    super.key,
    required this.format,
    required this.onChanged,
  });

  final TextFormat format;
  final ValueChanged<TextFormat> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<TextFormat>(
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    segments: [
      for (final f in TextFormat.values)
        ButtonSegment(value: f, label: Text(f.label)),
    ],
    selected: {format},
    onSelectionChanged: (picked) => onChanged(picked.single),
  );
}

/// What a field written in [format] says while it's empty.
String formatHint(TextFormat format) => switch (format) {
  TextFormat.plain => 'Plain text',
  TextFormat.markdown => 'Markdown: **bold**, *italics*, - lists, [links](…)',
  TextFormat.html => 'HTML: <b>bold</b>, <i>italics</i>, <ul> lists, <a> links',
};
