import 'package:flutter/material.dart';

/// One of the Plan page's panes -- Actions, Traits, People, Locations --
/// that it swipes between: a search across the top, with the pane's
/// [actions] beside it, over its [child], which fills the rest. The pane
/// is kept alive while swiped away, so it keeps its search and what it
/// loaded.
class PlanPane extends StatefulWidget {
  const PlanPane({
    super.key,
    required this.searchHint,
    required this.onSearch,
    this.actions = const [],
    required this.child,
  });

  /// What the search searches, e.g. "Search people".
  final String searchHint;

  /// Called with the search as it's typed; "" once it's cleared.
  final ValueChanged<String> onSearch;

  /// Buttons for the pane, after the search.
  final List<Widget> actions;
  final Widget child;

  @override
  State<PlanPane> createState() => _PlanPaneState();
}

class _PlanPaneState extends State<PlanPane>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
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
                                widget.onSearch('');
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (text) {
                      setState(() {});
                      widget.onSearch(text);
                    },
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
