import 'package:flutter/material.dart';

import 'hotkeys.dart';

/// A page of its own for editing something with room to -- a person, a
/// habit -- in place of a crowded dialog: [title] in its bar, with
/// [actions] before Save, and its fields ([children]) down the page, no
/// wider than reads well. [problem], if there's one, is said under them,
/// and Save ([saveLabel]) is off while there's one, or while [saving].
/// Its close button calls it off. Ctrl+Enter saves, and Esc calls it off
/// -- but with changes made, as [changed] says (by default, always: the
/// page can't tell), the first Esc only warns ([SaveOrDiscard]); in a
/// text field, the first Esc leaves it, for its fields' letters
/// ([FieldHotkey]).
class EditPage extends StatelessWidget {
  const EditPage({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.actions = const [],
    this.problem,
    this.saving = false,
    this.saveLabel = 'Save',
    this.changed,
  });

  final ValueGetter<bool>? changed;

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final List<Widget> actions;
  final String? problem;
  final bool saving;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SaveOrDiscard(
      changed: changed ?? () => true,
      onSave: saving || problem != null ? null : onSave,
      escLeavesFields: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            ...actions,
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
              child: HotkeyHint(
                Hotkey.save,
                child: FilledButton(
                  onPressed: saving || problem != null ? null : onSave,
                  child: Text(saveLabel),
                ),
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
      ),
    );
  }
}

/// Opens [page] over everything, as a page with a close button, and
/// returns what it's closed with.
Future<T?> showEditPage<T>(BuildContext context, Widget page) => Navigator.of(
  context,
).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
