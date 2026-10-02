import 'package:flutter/material.dart';

/// [child], with a thin progress bar across its top while [refreshing]:
/// what's shown is from last time, and the server is being asked again.
/// The bar sits over [child] rather than above it, so nothing moves when
/// it goes.
class RefreshingBar extends StatelessWidget {
  const RefreshingBar({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: 'Refreshing',
            ),
          ),
      ],
    );
  }
}
