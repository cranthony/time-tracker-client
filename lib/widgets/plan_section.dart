import 'package:flutter/material.dart';

/// One of the Plan page's sections -- Traits, People, Actions -- under a
/// heading with its [annotation] ("how to be", "who", "do") and its
/// [actions] at the right. Tapping the heading folds [children] away, or
/// opens them again.
class PlanSection extends StatelessWidget {
  const PlanSection({
    super.key,
    required this.title,
    required this.annotation,
    required this.expanded,
    required this.onExpanded,
    this.actions = const [],
    this.children = const [],
  });

  final String title;
  final String annotation;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  /// Buttons for the section, shown whether or not it's folded.
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: () => onExpanded(!expanded),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 4),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0 : -0.25,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: title,
                          style: theme.textTheme.titleMedium,
                          children: [
                            TextSpan(
                              text: '  $annotation',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Not the heading's own tap.
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded) ...children,
        const Divider(height: 1),
      ],
    );
  }
}
