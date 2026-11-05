/// A link's menu, opened by touching and holding the link or by clicking
/// it with the right mouse button: to open it, or to copy its address.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long a link is held for its menu: a little short of a long press,
/// so it's the link's menu that opens rather than the text being
/// selected, where it can be.
const linkHoldTimeout = Duration(milliseconds: 450);

/// A link's taps: [onTap] opens it, as a [TapGestureRecognizer]'s; held,
/// [onHold] is called instead, where it was held. A right click is
/// [onSecondaryTapUp], as a [TapGestureRecognizer]'s.
class LinkRecognizer extends TapGestureRecognizer {
  LinkRecognizer({super.debugOwner});

  /// Called where the link is held, once it's been held for
  /// [linkHoldTimeout]; letting go then doesn't tap it.
  void Function(Offset globalPosition)? onHold;

  Timer? _timer;
  var _held = false;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _stop();
    _held = false;
    if (onHold == null || event.buttons != kPrimaryButton) return;
    _timer = Timer(linkHoldTimeout, () {
      _timer = null;
      _held = true;
      // Won: the tap down is sent, if it hadn't been.
      resolve(GestureDisposition.accepted);
      onHold?.call(event.position);
    });
  }

  @override
  void rejectGesture(int pointer) {
    _stop();
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _stop();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleTapUp({
    required PointerDownEvent down,
    required PointerUpEvent up,
  }) {
    _stop();
    if (_held) {
      _held = false;
      return;
    }
    super.handleTapUp(down: down, up: up);
  }

  @override
  void handleTapCancel({
    required PointerDownEvent down,
    PointerCancelEvent? cancel,
    required String reason,
  }) {
    _stop();
    if (_held) {
      _held = false;
      return;
    }
    super.handleTapCancel(down: down, cancel: cancel, reason: reason);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

/// [url]'s menu, at [position] (global): "Open link", with [open], and
/// "Copy link address", copying [url] and saying so.
Future<void> showLinkMenu(
  BuildContext context,
  Offset position,
  String url, {
  required VoidCallback open,
}) async {
  Feedback.forLongPress(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = overlay.globalToLocal(position);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await showMenu<_LinkAction>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: const [
      PopupMenuItem(
        value: _LinkAction.open,
        child: ListTile(
          leading: Icon(Icons.open_in_new),
          title: Text('Open link'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: _LinkAction.copy,
        child: ListTile(
          leading: Icon(Icons.copy),
          title: Text('Copy link address'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
  switch (choice) {
    case _LinkAction.open:
      open();
    case _LinkAction.copy:
      await Clipboard.setData(ClipboardData(text: url));
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Link address copied')));
    case null:
      break;
  }
}

enum _LinkAction { open, copy }
