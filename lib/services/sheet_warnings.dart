import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The warnings the user dismissed from [SheetWarningsBanner]: up to the
/// latest the server had said of when they dismissed it. Kept on this
/// device only; the server still says what it found that week. A warning
/// that comes later shows again. Listeners hear every change.
class SheetWarningsDismissal extends ChangeNotifier {
  /// Kept on the device with [persist]; otherwise only while the app
  /// runs.
  SheetWarningsDismissal({this.persist = true});

  final bool persist;
  DateTime? _upTo;
  SheetWarningsFlag? _flag;
  Future<void>? _loading;

  /// Reads what's kept on the device, once. Best effort.
  Future<void> load() => _loading ??= () async {
    if (!persist) return;
    try {
      final kept = await SharedPreferencesAsync().getString(_key);
      final upTo = kept == null ? null : DateTime.tryParse(kept);
      if (upTo == null || _upTo != null) return;
      _upTo = upTo;
      notifyListeners();
    } catch (_) {
      // Nowhere to keep it.
    }
  }();

  /// Whether [flag] says only of warnings dismissed already. One with no
  /// time said is dismissed only as it was, while the app runs.
  bool hides(SheetWarningsFlag flag) => switch ((flag.latest, _upTo)) {
    (final latest?, final upTo?) => !latest.isAfter(upTo),
    (null, _) => flag == _flag,
    _ => false,
  };

  /// Dismisses what [flag] says of.
  void dismiss(SheetWarningsFlag flag) {
    _flag = flag;
    final latest = flag.latest;
    if (latest != null && !(_upTo?.isAfter(latest) ?? false)) {
      _upTo = latest;
      if (persist) {
        try {
          SharedPreferencesAsync()
              .setString(_key, latest.toUtc().toIso8601String())
              .catchError((_) {});
        } catch (_) {
          // Nowhere to keep it: it lasts until the app closes.
        }
      }
    }
    notifyListeners();
  }

  static const _key = 'sheet_warnings_dismissed';
}

/// The app's [SheetWarningsDismissal].
final sheetWarningsDismissal = SheetWarningsDismissal();
