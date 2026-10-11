import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a [StatusSource] says at the foot of the screen.
class StatusLine {
  const StatusLine({
    required this.icon,
    required this.text,
    this.needsYou = false,
  });

  final IconData icon;
  final String text;

  /// Whether it waits for the user -- a refusal to fix, a sign-in -- and
  /// won't come right by itself: it's in the error colours, and said
  /// before anything that will.
  final bool needsYou;
}

/// Something the app keeps the user posted on, the same way wherever it
/// comes from: a line at the foot of every page ([StatusBar]) while
/// there's something to say, and its part of the sheet that slides up
/// from it ([showStatusSheet]) -- the changes waiting in an outbox, say.
abstract class StatusSource {
  /// Says when [line], [section] or [count] may have changed.
  Listenable get listenable;

  /// What the bar says of it, or null for nothing.
  StatusLine? line(BuildContext context);

  /// Its part of the sheet; none, for nothing to show.
  List<Widget> section(BuildContext context);

  /// How many things it has waiting, for the app menu to count.
  int get count;
}

/// The line at the foot of the screen for [sources]: what the first that
/// needs the user says, or else the first with anything to say. Tapping
/// it slides up all of them ([showStatusSheet]). Nothing, while none has
/// anything to say.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.sources});

  final List<StatusSource> sources;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([for (final s in sources) s.listenable]),
    builder: (context, _) {
      final lines = [for (final s in sources) ?s.line(context)];
      final line =
          lines.where((l) => l.needsYou).firstOrNull ?? lines.firstOrNull;
      if (line == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final background = line.needsYou
          ? scheme.errorContainer
          : scheme.secondaryContainer;
      final foreground = line.needsYou
          ? scheme.onErrorContainer
          : scheme.onSecondaryContainer;
      return Material(
        color: background,
        child: InkWell(
          onTap: () => showStatusSheet(context, sources),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(line.icon, size: 20, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      line.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  Icon(Icons.expand_less, color: foreground),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Makes the app's [sources] available to everything below it: the app
/// menu, to slide them up ([showStatusSheet]) with nothing to say too.
class StatusScope extends InheritedWidget {
  const StatusScope({super.key, required this.sources, required super.child});

  final List<StatusSource> sources;

  /// The nearest one, or null if there's none.
  static StatusScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StatusScope>();

  /// How many things its sources have waiting.
  int get count => sources.fold(0, (n, s) => n + s.count);

  /// Slides up its sources ([showStatusSheet]).
  Future<void> show(BuildContext context) => showStatusSheet(context, sources);

  @override
  bool updateShouldNotify(StatusScope oldWidget) =>
      !listEquals(sources, oldWidget.sources);
}

/// Slides up each of [sources]' part of the sheet, in turn, as they
/// change.
Future<void> showStatusSheet(
  BuildContext context,
  List<StatusSource> sources,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (context, controller) => ListenableBuilder(
      listenable: Listenable.merge([for (final s in sources) s.listenable]),
      builder: (context, _) {
        final sections = [
          for (final s in sources)
            if (s.section(context) case final section when section.isNotEmpty)
              section,
        ];
        return ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final (i, section) in sections.indexed) ...[
              if (i > 0) const Divider(height: 32),
              ...section,
            ],
            if (sections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Nothing waiting: everything is saved.',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
          ],
        );
      },
    ),
  ),
);
