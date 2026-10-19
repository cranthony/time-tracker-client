import 'package:flutter/material.dart';

import '../widgets/hotkeys.dart';

/// A page of events -- all of a person's, say, or all they cancelled --
/// as [tiles] builds them, built again as [listenable] changes.
///
/// With [loadAll], its "Load all" button asks for more of them -- all of
/// a person's over the years, say, rather than those scored -- and shows
/// what that builds instead.
class EventListScreen extends StatefulWidget {
  const EventListScreen({
    super.key,
    required this.title,
    required this.tiles,
    this.listenable,
    this.loadAll,
  });

  final String title;
  final List<Widget> Function(BuildContext) tiles;

  /// What the events are worked out from, if they may change.
  final Listenable? listenable;

  /// Asks for them all, returning what builds their tiles.
  final Future<List<Widget> Function(BuildContext)> Function()? loadAll;

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  /// What [EventListScreen.loadAll] returned, once it has.
  List<Widget> Function(BuildContext)? _all;
  bool _loading = false;

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final all = await widget.loadAll!();
      if (mounted) setState(() => _all = all);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load them all.")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (widget.loadAll != null && _all == null)
          TextButton(
            onPressed: _loading ? null : _loadAll,
            child: const Text('Load all'),
          ),
      ],
      bottom: _loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(4),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: ListenableBuilder(
      listenable: widget.listenable ?? ValueNotifier(null),
      builder: (context, _) => HotkeyItems(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: (_all ?? widget.tiles)(context),
        ),
      ),
    ),
  );
}
