/// Off the web, no browser window to ask: null, for [FocusKeeper] to go
/// by the app's lifecycle alone.
bool? windowFocused() => null;

/// Off the web, nothing to listen to: the app's lifecycle says when it's
/// back.
void Function() onWindowFocus(void Function() back) => () {};
