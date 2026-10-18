import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/sheet_warnings.dart';

/// A strip across the top of every screen, above the app bar, while the
/// server says it found changes made behind its back in the last 7 days
/// ([serverSheetWarnings]): quieter than the sign-in one, and tapped to
/// see what they were ([onOpen]). It goes when a later result says there
/// were none. Otherwise, just [child].
class SheetWarningsBanner extends StatelessWidget {
  const SheetWarningsBanner({
    super.key,
    required this.child,
    this.warnings,
    this.onOpen,
    this.clock = DateTime.now,
  });

  final Widget child;

  /// What the server last said; by default [serverSheetWarnings].
  final ValueListenable<SheetWarningsFlag?>? warnings;

  /// Opens what they were; without it, the strip only says so.
  final VoidCallback? onOpen;

  final DateTime Function() clock;

  /// What the strip says of [flag], at [now].
  static String text(SheetWarningsFlag flag, DateTime now) {
    final times = flag.recent == 1 ? 'once' : '${flag.recent} times';
    final latest = flag.latest;
    return 'The metadata spreadsheet or calendar was changed outside the '
        'server $times this week'
        '${latest == null ? '' : ' (last ${ago(now.difference(latest))})'}';
  }

  /// How long ago [d] was, roughly: "just now", "5 minutes ago", ...
  static String ago(Duration d) {
    String of(int n, String unit) => '$n $unit${n == 1 ? '' : 's'} ago';
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return of(d.inMinutes, 'minute');
    if (d.inDays < 1) return of(d.inHours, 'hour');
    return of(d.inDays, 'day');
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<SheetWarningsFlag?>(
        valueListenable: warnings ?? serverSheetWarnings,
        builder: (context, flag, _) {
          if (flag == null) return child;
          final colors = Theme.of(context).colorScheme;
          final said = text(flag, clock());
          return Column(
            children: [
              Semantics(
                container: true,
                button: onOpen != null,
                label: said,
                child: Material(
                  color: colors.secondaryContainer,
                  child: InkWell(
                    onTap: onOpen,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_note,
                              size: 16,
                              color: colors.onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                said,
                                style: TextStyle(
                                  color: colors.onSecondaryContainer,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (onOpen != null)
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: colors.onSecondaryContainer,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The status bar's room taken already, by the strip.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child,
                ),
              ),
            ],
          );
        },
      );
}
