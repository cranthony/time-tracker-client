import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../platform/window_focus_stub.dart'
    if (dart.library.js_interop) '../platform/window_focus_web.dart'
    as window_focus;

/// Puts the cursor back in the text field it was in once the app has
/// focus again, after another window -- or, in a browser, another tab --
/// had it. Flutter brings back what had focus itself, but not a text
/// field the platform took it from first: as a browser does, closing the
/// field's input as its window loses focus, so the field lets go of it
/// before the app is told it's no longer in front.
///
/// A field let go of while the app was in front -- Esc, or a click
/// elsewhere -- is left alone; so is one whose page is covered by now,
/// or focus that's been put somewhere else since.
class FocusKeeper extends StatefulWidget {
  const FocusKeeper({
    super.key,
    required this.child,
    this.windowFocused = window_focus.windowFocused,
    this.onWindowFocus = window_focus.onWindowFocus,
    this.clock = DateTime.now,
  });

  final Widget child;

  /// Whether the app's window has focus, where that can be asked (a
  /// browser); null where it can't, for the app's lifecycle to say.
  final bool? Function() windowFocused;

  /// Calls what it's given whenever the window has focus again; what it
  /// gives back stops that.
  final void Function() Function(void Function() back) onWindowFocus;

  final DateTime Function() clock;

  /// Where the window can't be asked: how soon after a field's let go of
  /// the app's no longer being in front still means that's why.
  @visibleForTesting
  static const grace = Duration(milliseconds: 500);

  @override
  State<FocusKeeper> createState() => _FocusKeeperState();
}

class _FocusKeeperState extends State<FocusKeeper> {
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopListening;

  /// The text field with focus now.
  FocusNode? _field;

  /// The text field let go of as the app went out of front: the one to
  /// go back to.
  FocusNode? _left;

  /// The text field let go of last while the app looked to be in front,
  /// and when: for where the window can't be asked.
  FocusNode? _justLeft;
  DateTime? _justLeftAt;

  @override
  void initState() {
    super.initState();
    _field = _textField(FocusManager.instance.primaryFocus);
    FocusManager.instance.addListener(_focusChanged);
    _lifecycle = AppLifecycleListener(onStateChange: _stateChanged);
    _stopListening = widget.onWindowFocus(_back);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _lifecycle.dispose();
    _stopListening();
    super.dispose();
  }

  static FocusNode? _textField(FocusNode? node) {
    final context = node?.context;
    if (context == null) return null;
    final typing =
        context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
    return typing ? node : null;
  }

  /// Whether the app's out of front: its window without focus, where
  /// that can be asked, or else its lifecycle past resumed.
  bool get _away {
    final focused = widget.windowFocused();
    if (focused != null) return !focused;
    final state = SchedulerBinding.instance.lifecycleState;
    return state != null && state != AppLifecycleState.resumed;
  }

  void _focusChanged() {
    final field = _textField(FocusManager.instance.primaryFocus);
    if (field == _field) return;
    final was = _field;
    _field = field;
    // Into a field: that's where it is now.
    if (field != null) {
      _left = _justLeft = null;
      return;
    }
    if (was == null) return;
    if (_away) {
      _left ??= was;
    } else {
      _justLeft = was;
      _justLeftAt = widget.clock();
    }
  }

  void _stateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return _back();
    // Let go of a moment ago, where the window couldn't say why: the app
    // going out of front, most likely.
    final at = _justLeftAt;
    if (_left == null &&
        _justLeft != null &&
        at != null &&
        widget.windowFocused() == null &&
        widget.clock().difference(at) <= FocusKeeper.grace) {
      _left = _justLeft;
    }
    _justLeft = _justLeftAt = null;
  }

  /// Back in front: once Flutter's put back what it does, the field let
  /// go of goes back to having focus -- if it's still there, its page
  /// still on top, and nothing else has been given focus since.
  void _back() {
    final node = _left;
    if (node == null) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || _left != node) return;
        _left = null;
        final context = node.context;
        if (context == null || !node.canRequestFocus) return;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        final now = FocusManager.instance.primaryFocus;
        // Somewhere else on purpose: not just the field's own page, or
        // nothing at all.
        if (now != null &&
            !(now is FocusScopeNode && node.ancestors.contains(now))) {
          return;
        }
        node.requestFocus();
      })
      ..scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
