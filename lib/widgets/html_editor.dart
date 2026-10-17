import 'package:flutter/material.dart';

import 'event_description.dart';
import 'hotkeys.dart';

/// Edits [text], HTML, on a page of its own: a large box to type it in,
/// and to its right, a swipe away, how it reads ([EventDescription]).
/// Swiping back to the box puts the cursor, and what was selected, back
/// as they were. Either side can save or call it off. Gives what's typed
/// ("" for nothing), or null if it's called off.
Future<String?> showHtmlEditor(
  BuildContext context, {
  required String title,
  required String? text,
  String hint = 'HTML, or plain text',
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => HtmlEditorPage(title: title, text: text, hint: hint),
  ),
);

class HtmlEditorPage extends StatefulWidget {
  const HtmlEditorPage({
    super.key,
    required this.title,
    required this.text,
    this.hint = 'HTML, or plain text',
  });

  final String title;
  final String? text;
  final String hint;

  @override
  State<HtmlEditorPage> createState() => _HtmlEditorPageState();
}

class _HtmlEditorPageState extends State<HtmlEditorPage> {
  late final _controller = TextEditingController(text: widget.text ?? '');
  final _focus = FocusNode();
  final _pages = PageController();
  var _page = 0;

  /// Where the cursor was, and what was selected, as the box was left.
  TextSelection? _left;

  bool get _changed => _controller.text.trim() != (widget.text ?? '').trim();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _turned(int page) {
    if (page == _page) return;
    if (page == 1) {
      _left = _controller.selection;
      _focus.unfocus();
    } else {
      // Back to the box: as it was left.
      if (_left case final selection? when selection.isValid) {
        _controller.selection = selection;
      }
      _focus.requestFocus();
    }
    setState(() => _page = page);
  }

  void _show(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SaveOrDiscard(
      changed: () => _changed,
      onSave: _save,
      escLeavesFields: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(widget.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.code),
                    label: Text('Edit'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.visibility_outlined),
                    label: Text('Preview'),
                  ),
                ],
                selected: {_page},
                onSelectionChanged: (picked) => _show(picked.single),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
              child: HotkeyHint(
                Hotkey.save,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ),
          ],
        ),
        body: PageView(
          controller: _pages,
          onPageChanged: _turned,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _controller.text.trim().isEmpty
                    ? Text(
                        'Nothing yet.',
                        style: TextStyle(color: theme.hintColor),
                      )
                    : EventDescription(
                        _controller.text,
                        maxLines: null,
                        selectable: true,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
