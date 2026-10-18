import 'package:flutter/foundation.dart';

/// What the server last said, in a handshake's or a tool result's
/// `_meta`, of changes made behind its back -- the metadata spreadsheet
/// edited by hand (and put back), events changed outside it -- in the last
/// 7 days; null when it said there were none. Each result says it, so a
/// change shows ([SheetWarningsBanner]) without connecting again.
final serverSheetWarnings = ValueNotifier<SheetWarningsFlag?>(null);

/// The flag the server sets in the handshake's and each tool result's
/// `_meta` while it has warned of such changes in the last 7 days (its
/// mcp::SHEET_WARNINGS_META_KEY).
const sheetWarningsMetaKey = 'time-tracking/sheetWarnings';

/// The server's flag: how many warnings in the last 7 days, and when the
/// latest came. What they were is get_health's `sheet_warnings`.
@immutable
class SheetWarningsFlag {
  const SheetWarningsFlag({required this.recent, this.latest});

  final int recent;
  final DateTime? latest;

  /// The flag in [result]'s `_meta`; null when there's none, or it isn't
  /// one.
  static SheetWarningsFlag? of(Map<String, dynamic> result) =>
      switch (result['_meta']) {
        {sheetWarningsMetaKey: {'recent': final num recent} && final Map flag}
            when recent > 0 =>
          SheetWarningsFlag(
            recent: recent.toInt(),
            latest: DateTime.tryParse('${flag['latest']}'),
          ),
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is SheetWarningsFlag &&
      other.recent == recent &&
      other.latest == latest;

  @override
  int get hashCode => Object.hash(recent, latest);

  @override
  String toString() => 'SheetWarningsFlag($recent, $latest)';
}
