import 'package:flutter/material.dart';

/// A page of its own for editing something with room to -- a person, a
/// habit -- in place of a crowded dialog: [title] in its bar, with
/// [actions] before Save, and its fields ([children]) down the page, no
/// wider than reads well. [problem], if there's one, is said under them,
/// and Save is off while there's one, or while [saving]. Its close button
/// calls it off.
class EditPage extends StatelessWidget {
  const EditPage({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.actions = const [],
    this.problem,
    this.saving = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final List<Widget> actions;
  final String? problem;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...actions,
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
            child: FilledButton(
              onPressed: saving || problem != null ? null : onSave,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                ...children,
                if (problem case final problem?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      problem,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [page] over everything, as a page with a close button, and
/// returns what it's closed with.
Future<T?> showEditPage<T>(BuildContext context, Widget page) => Navigator.of(
  context,
).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
