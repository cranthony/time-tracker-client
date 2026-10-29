import 'package:flutter/material.dart';

import '../models/text_format.dart';
import 'event_description.dart';
import 'hotkeys.dart';
import 'text_format_picker.dart';

/// Edits [text], written in [format], on a page of its own: how it's
/// written (plain text, Markdown or HTML) over a large box to type it in,
/// and to its right, a swipe away, how it reads ([EventDescription]).
/// With no [format], it starts as the text looks -- plain text when
/// there's none. Swiping back to the box puts the cursor, and what was
/// selected, back as they were. Either side can save or call it off.
/// Gives what's typed ("" for nothing) and its format, or null if it's
/// called off.
Future<FormattedText?> showTextEditor(
  BuildContext context, {
  required String title,
  required String? text,
  TextFormat? format,
}) => Navigator.of(context).push<FormattedText>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => TextEditorPage(title: title, text: text, format: format),
  ),
);

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({
    super.key,
    required this.title,
    required this.text,
    this.format,
  });

  final String title;
  final String? text;
  final TextFormat? format;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final _controller = TextEditingController(text: widget.text ?? '');
  late final _initialFormat = TextFormat.of(widget.text, widget.format);
  late var _format = _initialFormat;
  final _focus = FocusNode();
  final _pages = PageController();
  var _page = 0;

  /// Where the cursor was, and what was selected, as the box was left.
  TextSelection? _left;

  bool get _changed =>
      _controller.text.trim() != (widget.text ?? '').trim() ||
      _format != _initialFormat;

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

  void _save() =>
      Navigator.of(context)
          .pop<FormattedText>((text: _controller.text.trim(), format: _format));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SaveOrDiscard(
      changed: () => _changed,
      onSave: _save,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormatPicker(
                    format: _format,
                    onChanged: (format) => setState(() => _format = format),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
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
                        fontFamily: _format == TextFormat.plain
                            ? null
                            : 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: formatHint(_format),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
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
                        format: _format,
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
