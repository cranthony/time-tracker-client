import 'package:flutter/material.dart';

import 'hotkeys.dart';

/// One of the Plan page's panes -- Actions, Traits, People, Locations --
/// that it swipes between: its [summary], if it has one, then a search,
/// with the pane's [actions] beside it -- or, without [onSearch], the
/// actions alone, at the end, and nothing with none -- over its [child],
/// which fills the rest. The pane
/// is kept alive while swiped away, so it keeps its search and what it
/// loaded.
class PlanPane extends StatefulWidget {
  const PlanPane({
    super.key,
    this.searchHint = 'Search',
    this.onSearch,
    this.autofocus = false,
    this.actions = const [],
    this.summary,
    required this.child,
  });

  /// Above the search: a [TimeSummary], say.
  final Widget? summary;

  /// What the search searches, e.g. "Search people".
  final String searchHint;

  /// Called with the search as it's typed; "" once it's cleared. Null
  /// for no search: a pane with too little in it to need one.
  final ValueChanged<String>? onSearch;

  /// Whether the search takes the keyboard as soon as the pane shows.
  final bool autofocus;

  /// Buttons for the pane, after the search.
  final List<Widget> actions;
  final Widget child;

  @override
  State<PlanPane> createState() => _PlanPaneState();
}

class _PlanPaneState extends State<PlanPane>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.summary,
        if (widget.onSearch != null || widget.actions.isNotEmpty)
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
              child: Row(
                children: [
                  if (widget.onSearch == null)
                    const Spacer()
                  else
                    Expanded(
                      child: SearchHotkey(
                        focus: _searchFocus,
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          autofocus: widget.autofocus,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: widget.searchHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear the search',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                      widget.onSearch?.call('');
                                    },
                                  ),
                            isDense: true,
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (text) {
                            setState(() {});
                            widget.onSearch?.call(text);
                          },
                        ),
                      ),
                    ),
                  ...widget.actions,
                ],
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Whether [texts], together, have every word of [query] in them,
/// ignoring case: an empty query matches everything.
bool matchesSearch(String query, Iterable<String?> texts) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;
  final haystack = texts.nonNulls.join('\n').toLowerCase();
  return words.every(haystack.contains);
}

/// What a pane shows when its search matches nothing.
class NoMatches extends StatelessWidget {
  const NoMatches({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      'Nothing matches “${query.trim()}”.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).hintColor),
    ),
  );
}

/// [text] as spans, the parts matching a word of [query] (ignoring case)
/// in [match]'s style, the rest in none of their own.
List<TextSpan> highlightMatches(String text, String query, TextStyle match) {
  final lower = text.toLowerCase();
  final marked = List.filled(text.length, false);
  for (final word in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    for (
      var at = lower.indexOf(word);
      at >= 0;
      at = lower.indexOf(word, at + 1)
    ) {
      marked.fillRange(at, at + word.length, true);
    }
  }
  final spans = <TextSpan>[];
  for (var i = 0; i < text.length;) {
    var j = i;
    while (j < text.length && marked[j] == marked[i]) {
      j++;
    }
    spans.add(
      TextSpan(text: text.substring(i, j), style: marked[i] ? match : null),
    );
    i = j;
  }
  return spans;
}
