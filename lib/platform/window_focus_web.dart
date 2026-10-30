import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Whether the browser window has focus: false already while a text
/// field's losing it to another window or tab -- unlike a click
/// elsewhere on the page.
bool? windowFocused() => web.document.hasFocus();

/// Calls [back] each time the browser window gets focus again; what it
/// gives back stops that.
void Function() onWindowFocus(void Function() back) {
  final listener = ((web.Event _) => back()).toJS;
  web.window.addEventListener('focus', listener);
  return () => web.window.removeEventListener('focus', listener);
}
