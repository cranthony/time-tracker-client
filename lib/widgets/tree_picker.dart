import 'package:flutter/material.dart';

import 'hotkeys.dart';
import 'picker_search.dart';

/// One row a [TreePicker] can show: something to pick, or a group of them
/// (a folder), in the group [parentId], if any.
class PickerNode {
  const PickerNode({
    required this.id,
    required this.label,
    this.parentId,
    this.path,
    this.detail,
    this.group = false,
    this.faded = false,
  });

  final String id;
  final String label;
  final String? parentId;

  /// Its whole path, its groups' names before its own ("Cooking › Tofu"):
  /// what it's searched by, and shown by, out of its tree.
  final String? path;

  /// A line under it: a location's hint, say.
  final String? detail;
  final bool group;

  /// Shown faded: an action put away, say.
  final bool faded;

  /// The groups it's in, from its [path] ("Cooking" for "Cooking › Tofu");
  /// null at the top.
  String? get above {
    final path = this.path;
    if (path == null) return null;
    final cut = path.lastIndexOf(' › ');
    return cut < 0 ? null : path.substring(0, cut);
  }
}

/// What [TreePicker]'s add row adds: what it's called, its icon, and how
/// it's added, given what's typed.
typedef PickerAdd = ({String noun, IconData icon, ValueChanged<String> onAdd});

/// Picks from [nodes]: things, and the groups (folders) they're in. Those
/// [picked] show as chips on top, then a search over them all, then, while
/// the search is empty, the tree, every group open, each closed by its
/// arrow -- or, searching, what matches, best first with [PickerSearch.matchAny],
/// each with its path. Calls [onChanged] with the ids, in the order they
/// were picked.
///
/// Enter in the search moves the keyboard to the top result, to pick it
/// (or unpick it) with Enter or Space, or go on down with J.
///
/// With [single], it picks one, with no chips: tapping one picks it (a
/// radio button marks it). A group can be
/// picked only with [groupsPickable]: then tapping it picks it, and its
/// arrow opens it; otherwise tapping it opens or closes it. With [none],
/// a row by that name, over the list, picks nothing.
///
/// Its [search] can be given, to start with words typed or outlive it;
/// [autofocus] takes the keyboard at once, what's typed selected.
/// Long-pressing a row calls [onEdit]; with [add], a row under the search
/// adds one, and with [adds], one each for more kinds -- a person, and a
/// circle, say. [marker] goes before each name -- an action's diamond, say.
/// With [onChipTap], each chip can be tapped as well as removed -- to set
/// how much of an event a goal takes, say -- and [chipDetail] says, after
/// its label, what's set.
/// The list fills what room there is, or with [maxListHeight], grows to
/// that and scrolls (in a dialog, which measures what's in it).
class TreePicker extends StatefulWidget {
  const TreePicker({
    super.key,
    required this.nodes,
    required this.picked,
    required this.onChanged,
    this.single = false,
    this.groupsPickable = false,
    this.none,
    this.search,
    this.autofocus = false,
    this.searchHint = 'Search',
    this.caption,
    this.empty = 'Nothing yet.',
    this.noMatches = 'Nothing matches.',
    this.marker,
    this.chipAvatar,
    this.onEdit,
    this.add,
    this.adds = const [],
    this.maxListHeight,
    this.onChipTap,
    this.chipDetail,
  });

  final List<PickerNode> nodes;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;
  final bool single;
  final bool groupsPickable;
  final String? none;
  final PickerSearch? search;
  final bool autofocus;
  final String searchHint;

  /// What the list is of, over it.
  final String? caption;

  /// What's said when there's nothing to pick, and when nothing matches.
  final String empty;
  final String noMatches;
  final Widget Function(PickerNode node)? marker;

  /// Before each chip's label: the first's star, say, for the primary.
  final Widget? Function(int index, PickerNode? node)? chipAvatar;
  final ValueChanged<PickerNode>? onEdit;
  final PickerAdd? add;
  final List<PickerAdd> adds;
  final double? maxListHeight;

  /// Called with a chip's id as it's tapped; null, a chip only removes.
  final ValueChanged<String>? onChipTap;

  /// What follows a chip's label, by its id: "45m"; null or "" for
  /// nothing.
  final String? Function(String id)? chipDetail;

  @override
  State<TreePicker> createState() => _TreePickerState();
}

class _TreePickerState extends State<TreePicker> {
  /// Its own search, unless it was given one.
  PickerSearch? _own;
  PickerSearch get _search => widget.search ?? (_own ??= PickerSearch());

  /// The groups closed, while the search is empty: none, to start with,
  /// so everything is to hand -- even what's added while it's open.
  final Set<String> _closed = {};

  /// The top result's, to move the keyboard to from the search.
  final _top = FocusNode(debugLabel: 'Top result');

  /// The top result's id: what can be picked first, as shown -- or, with
  /// nothing to pick, the first row.
  String? _topId;

  @override
  void initState() {
    super.initState();
    _search.addListener(_searched);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.focusAll();
      });
    }
  }

  @override
  void didUpdateWidget(TreePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.search ?? _own;
    if (was != _search) {
      was?.removeListener(_searched);
      _search.addListener(_searched);
    }
  }

  void _searched() => setState(() {});

  @override
  void dispose() {
    _search.removeListener(_searched);
    _own?.dispose();
    _top.dispose();
    super.dispose();
  }

  Map<String, PickerNode> get _byId => {
    for (final node in widget.nodes) node.id: node,
  };

  /// Every group above any of [ids], so the tree opens down to them.
  Set<String> _ancestorsOf(Iterable<String> ids) {
    final byId = _byId;
    final above = <String>{};
    for (final id in ids) {
      var parent = byId[id]?.parentId;
      while (parent != null && above.add(parent)) {
        parent = byId[parent]?.parentId;
      }
    }
    return above;
  }

  bool _pickable(PickerNode node) => !node.group || widget.groupsPickable;

  /// Picks or unpicks [node]; one picked opens the tree down to it.
  void _toggle(PickerNode node, bool on) {
    if (on) _closed.removeAll(_ancestorsOf([node.id]));
    if (widget.single) {
      widget.onChanged([node.id]);
      return;
    }
    widget.onChanged([
      for (final id in widget.picked)
        if (id != node.id) id,
      if (on) node.id,
    ]);
  }

  /// What [node] is searched by: its path, and its detail.
  static String _text(PickerNode node) =>
      '${node.path ?? node.label} ${node.detail ?? ''}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _search.query;
    final shown = query.isEmpty
        ? _visible()
        : [
            for (final node in query.filter(widget.nodes, _text))
              (node: node, depth: 0, inside: 0, open: false),
          ];
    _topId =
        (shown.where((r) => _pickable(r.node)).firstOrNull ?? shown.firstOrNull)
            ?.node
            .id;
    final rows = [
      for (final r in shown)
        query.isEmpty
            ? _row(
                r.node,
                depth: r.depth,
                subtitle: r.depth == 0
                    ? r.node.above ?? r.node.detail
                    : r.node.detail,
                inside: r.inside,
                open: r.open,
              )
            : _row(r.node, subtitle: r.node.above ?? r.node.detail),
    ];
    final list = [
      if (widget.none case final none?) _noneRow(none),
      if (widget.nodes.isEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(widget.empty, style: TextStyle(color: theme.hintColor)),
        )
      else if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(widget.noMatches),
        ),
      ...rows,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.maxListHeight == null
          ? MainAxisSize.max
          : MainAxisSize.min,
      children: [
        if (widget.caption case final caption?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(caption, style: theme.textTheme.bodySmall),
          ),
        if (widget.picked.isNotEmpty && !widget.single) _chips(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: PickerSearchField(
            search: _search,
            hint: widget.searchHint,
            onSubmitted: (_) => _focusTop(),
          ),
        ),
        // Above the list, not in it: always to hand.
        for (final (:noun, :icon, :onAdd) in [?widget.add, ...widget.adds])
          PickerAddTile(noun: noun, search: _search, icon: icon, onAdd: onAdd),
        switch (widget.maxListHeight) {
          null => Expanded(
            child: HotkeyItems(child: ListView(children: list)),
          ),
          // Not a ListView: a dialog measures its content's intrinsic
          // width, which a lazy list can't give.
          final most => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: most),
            child: HotkeyItems(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: list,
                ),
              ),
            ),
          ),
        },
      ],
    );
  }

  /// The picked, as chips: ✕ unpicks.
  Widget _chips() {
    final byId = _byId;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, id) in widget.picked.indexed)
            InputChip(
              avatar: widget.chipAvatar?.call(i, byId[id]),
              label: Text(switch (widget.chipDetail?.call(id)) {
                final detail? when detail.isNotEmpty =>
                  '${byId[id]?.label ?? id} · $detail',
                _ => byId[id]?.label ?? id,
              }),
              tooltip: widget.onChipTap == null ? null : 'Set its share',
              onPressed: switch (widget.onChipTap) {
                final tap? => () => tap(id),
                null => null,
              },
              deleteButtonTooltipMessage: 'Remove',
              onDeleted: () => widget.onChanged([
                for (final other in widget.picked)
                  if (other != id) other,
              ]),
            ),
        ],
      ),
    );
  }

  /// The keyboard, to the top result -- once what's typed now is shown,
  /// which it may not have been yet -- scrolled into view.
  void _focusTop() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _top.context;
      if (!mounted || context == null) return;
      _top.requestFocus();
      Scrollable.ensureVisible(context);
    });
  }

  /// The tree's rows, each branch shown only while it's open: each node,
  /// how many groups in, how many are in it, and whether it's open. One
  /// whose group isn't among [TreePicker.nodes] sits at the top.
  List<({PickerNode node, int depth, int inside, bool open})> _visible() {
    final ids = {for (final node in widget.nodes) node.id};
    final children = <String?, List<PickerNode>>{};
    for (final node in widget.nodes) {
      final parent = ids.contains(node.parentId) ? node.parentId : null;
      children.putIfAbsent(parent, () => []).add(node);
    }
    final rows = <({PickerNode node, int depth, int inside, bool open})>[];
    void visit(PickerNode node, int depth) {
      final inside = children[node.id] ?? const <PickerNode>[];
      final open = !_closed.contains(node.id);
      rows.add((node: node, depth: depth, inside: inside.length, open: open));
      if (open) {
        for (final child in inside) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in children[null] ?? const <PickerNode>[]) {
      visit(root, 0);
    }
    return rows;
  }

  /// [node]'s row, [depth] groups in, long-pressed to edit it. With
  /// [inside] -- how many are in it -- an arrow opens or closes it.
  Widget _row(
    PickerNode node, {
    int depth = 0,
    String? subtitle,
    int inside = 0,
    bool open = false,
  }) {
    void toggleOpen() =>
        setState(() => open ? _closed.add(node.id) : _closed.remove(node.id));
    final row = _tile(
      node,
      depth: depth,
      subtitle: subtitle,
      arrow: inside == 0
          ? null
          : IconButton(
              tooltip: open ? "Hide what's inside" : 'Show $inside inside',
              icon: Icon(open ? Icons.expand_less : Icons.expand_more),
              onPressed: toggleOpen,
            ),
      onOpen: inside == 0 ? null : toggleOpen,
    );
    final edit = widget.onEdit;
    if (edit == null) return KeyedSubtree(key: ValueKey(node.id), child: row);
    return GestureDetector(
      key: ValueKey(node.id),
      onLongPress: () => edit(node),
      child: row,
    );
  }

  Widget _tile(
    PickerNode node, {
    required int depth,
    required String? subtitle,
    required Widget? arrow,
    required VoidCallback? onOpen,
  }) {
    final hint = Theme.of(context).hintColor;
    final picked = widget.picked.contains(node.id);
    final focus = node.id == _topId ? _top : null;
    final title = Row(
      children: [
        if (widget.marker case final marker?) ...[
          marker(node),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            node.label,
            style: node.faded ? TextStyle(color: hint) : null,
          ),
        ),
      ],
    );
    final under = subtitle == null || subtitle.isEmpty
        ? null
        : Text(subtitle, style: TextStyle(color: hint));
    final indent = EdgeInsetsDirectional.only(start: 16.0 * depth + 12);
    if (!_pickable(node)) {
      return ListTile(
        dense: true,
        contentPadding: indent,
        focusNode: focus,
        leading: Icon(Icons.folder_outlined, color: hint),
        trailing: arrow,
        title: title,
        subtitle: under,
        onTap: onOpen,
      );
    }
    if (widget.single) {
      return ListTile(
        dense: true,
        contentPadding: indent,
        selected: picked,
        focusNode: focus,
        leading: Icon(
          picked ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        trailing: arrow,
        title: title,
        subtitle: under,
        onTap: () => _toggle(node, true),
      );
    }
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth),
      controlAffinity: ListTileControlAffinity.leading,
      value: picked,
      focusNode: focus,
      // With the box leading, this sits at the end.
      secondary: arrow,
      title: title,
      subtitle: under,
      onChanged: (on) => _toggle(node, on == true),
    );
  }

  /// The row that picks nothing.
  Widget _noneRow(String none) => ListTile(
    dense: true,
    contentPadding: const EdgeInsetsDirectional.only(start: 12),
    selected: widget.picked.isEmpty,
    leading: Icon(
      widget.picked.isEmpty
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
    ),
    title: Text(none),
    onTap: () => widget.onChanged(const []),
  );
}
