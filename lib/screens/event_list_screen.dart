import 'package:flutter/material.dart';

/// A page of events -- all of a person's, say, or all they cancelled --
/// as [tiles] builds them, built again as [listenable] changes.
class EventListScreen extends StatelessWidget {
  const EventListScreen({
    super.key,
    required this.title,
    required this.tiles,
    this.listenable,
  });

  final String title;
  final List<Widget> Function(BuildContext) tiles;

  /// What the events are worked out from, if they may change.
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(
      listenable: listenable ?? ValueNotifier(null),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: tiles(context),
      ),
    ),
  );
}
