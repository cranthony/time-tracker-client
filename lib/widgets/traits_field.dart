import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import 'parts_editor.dart';

/// Which of [traits] apply -- every active one, or those picked -- each
/// with its own parts in place of the trait's, if it has any: a person's,
/// or a habit's. Starts from [value], and calls [onChanged] with them
/// after every change. A trait's tune button edits its own parts in a
/// dialog titled [partsTitle], with [partsExplanation] above them and
/// [warnings] below; [actions] names the actions and groups a part can
/// count. [own] is whose they are: "Their own", "Its own". Shows nothing
/// without [traits].
class TraitsField extends StatefulWidget {
  const TraitsField({
    super.key,
    required this.traits,
    required this.value,
    required this.onChanged,
    required this.partsTitle,
    required this.partsExplanation,
    this.own = 'Their own',
    this.actions = const {},
    this.warnings,
  });

  final List<Trait> traits;
  final PersonTraits value;
  final ValueChanged<PersonTraits> onChanged;
  final String Function(Trait trait) partsTitle;
  final String Function(Trait trait) partsExplanation;
  final String own;
  final Map<String, String> actions;
  final List<String> Function(List<Part> parts)? warnings;

  @override
  State<TraitsField> createState() => _TraitsFieldState();
}

class _TraitsFieldState extends State<TraitsField> {
  /// The traits picked; null for every active one.
  late List<String>? _select = switch (widget.value.select) {
    final ids? => [...ids],
    null => null,
  };

  /// Their own parts, by trait id, kept for a trait unpicked in case it's
  /// picked again.
  late final _parts = <String, List<Part>>{...widget.value.parts};

  void _changed(VoidCallback change) {
    setState(change);
    widget.onChanged(
      PersonTraits(
        select: _select,
        parts: {
          for (final MapEntry(:key, :value) in _parts.entries)
            if (_select?.contains(key) ?? true) key: value,
        },
      ),
    );
  }

  Future<void> _editParts(Trait trait) async {
    final edited = await showPartsDialog(
      context,
      title: widget.partsTitle(trait),
      explanation: widget.partsExplanation(trait),
      parts: _parts[trait.id] ?? trait.parts,
      actions: widget.actions,
      warnings: widget.warnings,
    );
    if (edited != null) _changed(() => _parts[trait.id!] = edited);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.traits.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final all = _select == null;
    final shown = [
      for (final t in widget.traits)
        if (t.id != null &&
            (t.status == 'active' || (_select?.contains(t.id) ?? false)))
          t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Traits', style: theme.textTheme.titleSmall),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Every active trait'),
          subtitle: const Text('Including any added later.'),
          value: all,
          onChanged: (on) => _changed(
            () => _select = on ? null : [for (final t in shown) t.id!],
          ),
        ),
        for (final trait in shown)
          if (all || _select!.contains(trait.id))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: all
                  ? null
                  : Checkbox(
                      value: true,
                      onChanged: (_) =>
                          _changed(() => _select!.remove(trait.id)),
                    ),
              title: Text(trait.name),
              subtitle: Text(switch (_parts[trait.id]) {
                final own? =>
                  '${widget.own}: '
                      '${own.map((p) => describePart(p, widget.actions)).join('; ')}',
                null => "The trait's parts",
              }),
              trailing: Wrap(
                children: [
                  if (_parts.containsKey(trait.id))
                    IconButton(
                      tooltip: "Use ${trait.name}'s parts",
                      icon: const Icon(Icons.undo),
                      onPressed: () => _changed(() => _parts.remove(trait.id)),
                    ),
                  IconButton(
                    tooltip: '${widget.own} ${trait.name} parts',
                    icon: const Icon(Icons.tune),
                    onPressed: () => _editParts(trait),
                  ),
                ],
              ),
            )
          else
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: false,
                onChanged: (_) => _changed(() => _select!.add(trait.id!)),
              ),
              title: Text(trait.name, style: TextStyle(color: theme.hintColor)),
            ),
      ],
    );
  }
}
