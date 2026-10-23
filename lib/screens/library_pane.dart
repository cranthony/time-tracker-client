import 'package:flutter/material.dart';

import '../widgets/hotkeys.dart';

/// The Plan page's Library pane: what grows without end -- people,
/// actions and locations: who, what and where -- one of its [sections]
/// at a time, the one titled [shown], picked by a switch at its top, each
/// with its first letter as its hotkey. [onShown] is told of the one
/// picked. Each is built once it's first shown, and kept, search and
/// all, while another is.
class LibraryPane extends StatefulWidget {
  const LibraryPane({
    super.key,
    required this.sections,
    required this.shown,
    required this.onShown,
  });

  /// Each section's title and pane.
  final List<(String, Widget)> sections;
  final String shown;
  final ValueChanged<String> onShown;

  @override
  State<LibraryPane> createState() => _LibraryPaneState();
}

class _LibraryPaneState extends State<LibraryPane>
    with AutomaticKeepAliveClientMixin {
  /// The sections shown so far, by title.
  final _built = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sections = widget.sections;
    final shown = sections.indexWhere((s) => s.$1 == widget.shown);
    final index = shown < 0 ? 0 : shown;
    _built.add(sections[index].$1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sections.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final (title, _) in sections)
                  ButtonSegment(
                    value: title,
                    label: HotkeyHint(
                      Hotkey(title[0], 'Go to $title', HotkeyPlace.plan),
                      child: Text(title),
                    ),
                  ),
              ],
              selected: {sections[index].$1},
              onSelectionChanged: (picked) => widget.onShown(picked.single),
            ),
          ),
        // Offstage, not an IndexedStack: what isn't shown isn't painted,
        // so its hotkeys -- its search's, its "+" -- don't answer.
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final (i, (title, pane)) in sections.indexed)
                Offstage(
                  offstage: i != index,
                  child: TickerMode(
                    enabled: i == index,
                    child: _built.contains(title) ? pane : const SizedBox(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
