import 'package:flutter/material.dart';

import 'hotkeys.dart';

/// What's typed in a picker's search, as words to match in any order:
/// every one of them, or with [any], at least one.
class PickerQuery {
  PickerQuery(String text, {this.any = false})
    : words = [
        for (final word in text.toLowerCase().split(RegExp(r'\s+')))
          if (word.isNotEmpty) word,
      ];

  final List<String> words;
  final bool any;

  bool get isEmpty => words.isEmpty;

  /// How many of the words [text] holds; null if it doesn't match.
  int? score(String text) {
    final lower = text.toLowerCase();
    final found = words.where(lower.contains).length;
    if (any ? found == 0 : found < words.length) return null;
    return found;
  }

  /// Those of [items] that match, by their [text]: with [any], those
  /// holding the most words first, otherwise (and among ties) in order.
  List<T> filter<T>(Iterable<T> items, String Function(T item) text) {
    final scored = [
      for (final item in items)
        if (score(text(item)) case final score?) (item, score),
    ];
    if (any) {
      // List.sort isn't stable: the index keeps ties in order.
      final indexed = [for (final (i, s) in scored.indexed) (i, s)];
      indexed.sort(
        (a, b) => switch (b.$2.$2.compareTo(a.$2.$2)) {
          0 => a.$1.compareTo(b.$1),
          final order => order,
        },
      );
      return [for (final (_, (item, _)) in indexed) item];
    }
    return [for (final (item, _) in scored) item];
  }
}

/// A picker's search, kept apart from the picker so it outlives it -- a
/// page of a sheet swiped away and back keeps what was typed: its text,
/// whether to match any word rather than every one, and its focus.
class PickerSearch extends ChangeNotifier {
  PickerSearch({String text = '', bool matchAny = false})
    : controller = TextEditingController(text: text) {
    _matchAny = matchAny;
    controller.addListener(notifyListeners);
  }

  final TextEditingController controller;
  final focus = FocusNode();

  late bool _matchAny;
  bool get matchAny => _matchAny;
  set matchAny(bool any) {
    if (any == _matchAny) return;
    _matchAny = any;
    notifyListeners();
  }

  PickerQuery get query => PickerQuery(controller.text, any: _matchAny);

  /// Takes the keyboard, with everything typed selected, to type over.
  void focusAll() {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    focus.requestFocus();
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// [search]'s box, with a clear button, and beside it a toggle to match
/// any word typed rather than every one. "/" puts the cursor in it.
class PickerSearchField extends StatelessWidget {
  const PickerSearchField({
    super.key,
    required this.search,
    this.hint = 'Search',
    this.onSubmitted,
  });

  final PickerSearch search;
  final String hint;

  /// Enter, with what's typed now.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: search, builder: _field);

  Widget _field(BuildContext context, Widget? _) => Row(
    children: [
      Expanded(
        child: SearchHotkey(
          focus: search.focus,
          child: TextField(
            controller: search.controller,
            focusNode: search.focus,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              hintText: hint,
              suffixIcon: search.controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: search.controller.clear,
                    ),
            ),
            // Kept focused after Enter, ready for the next.
            onEditingComplete: () {},
            onSubmitted: onSubmitted,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: search.matchAny
            ? 'Showing what matches any word'
            : 'Showing what matches every word',
        child: FilterChip(
          label: const Text('Any'),
          selected: search.matchAny,
          onSelected: (any) => search.matchAny = any,
        ),
      ),
    ],
  );
}

/// A row that adds what was searched for: "Add [noun] “typed”…", or with
/// nothing typed, "Add [noun]…".
class PickerAddTile extends StatelessWidget {
  const PickerAddTile({
    super.key,
    required this.noun,
    required this.search,
    required this.icon,
    required this.onAdd,
  });

  final String noun;
  final PickerSearch search;
  final IconData icon;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: search.controller,
    builder: (context, _) {
      final typed = search.controller.text.trim();
      return ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(typed.isEmpty ? 'Add $noun…' : 'Add $noun “$typed”…'),
        onTap: () => onAdd(typed),
      );
    },
  );
}
