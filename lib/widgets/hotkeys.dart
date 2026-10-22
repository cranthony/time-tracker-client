import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Where a [Hotkey] works, as the list of them groups it.
enum HotkeyPlace {
  anywhere('Anywhere'),
  events('On the Events page'),
  creating('Making or moving an event'),
  event('In an event'),
  plan('On the Plan page'),
  goal("On a goal's page"),
  diagnostics('On the Diagnostics page');

  const HotkeyPlace(this.title);
  final String title;
}

/// A key the app answers, as the list of them ([showHotkeysDialog])
/// shows it: [keys] as they're pressed, what it [does], and [where]. A
/// [HotkeyHint] shows [hint] on the button it stands for while Ctrl is
/// held -- or, for one pressed after Ctrl+B, [afterCtrlB] once Ctrl+B
/// has been.
@immutable
class Hotkey {
  const Hotkey(
    this.keys,
    this.does,
    this.where, {
    String? hint,
    this.afterCtrlB,
  }) : hint = hint ?? keys;

  final String keys;
  final String does;
  final HotkeyPlace where;
  final String hint;

  /// The letter pressed after Ctrl+B, for one that is.
  final String? afterCtrlB;

  static const newNote = Hotkey(
    'Ctrl+M / +',
    'Write a note, over whatever is open; closing it goes back there. On '
        'the Notes page, + does too',
    HotkeyPlace.anywhere,
  );
  static const newGoal = Hotkey(
    'Ctrl+;',
    'Set a goal, due by the end of a day, over whatever is open; closing '
        'it goes back there, and its More goes on in the full New goal page',
    HotkeyPlace.anywhere,
  );
  static const notes = Hotkey(
    'Ctrl+B, then N',
    'Go to Notes',
    HotkeyPlace.anywhere,
    hint: 'Ctrl+B N',
    afterCtrlB: 'N',
  );
  static const events = Hotkey(
    'Ctrl+B, then E',
    'Go to Events, at now',
    HotkeyPlace.anywhere,
    hint: 'Ctrl+B E',
    afterCtrlB: 'E',
  );
  static const plan = Hotkey(
    'Ctrl+B, then P',
    'Go to Plan',
    HotkeyPlace.anywhere,
    hint: 'Ctrl+B P',
    afterCtrlB: 'P',
  );
  static const menu = Hotkey(
    'Ctrl+B, then S',
    'Open the ⋮ menu',
    HotkeyPlace.anywhere,
    hint: 'Ctrl+B S',
    afterCtrlB: 'S',
  );
  static const save = Hotkey(
    'Ctrl+Enter',
    "Save what's being edited -- a note, an event, a description -- and "
        'close it',
    HotkeyPlace.anywhere,
  );
  static const discard = Hotkey(
    'Esc',
    'Close what was being edited; with changes made, the first Esc shakes '
        'it, saying so, and the second discards them. Elsewhere, Esc does '
        'all U does, and more: on the Events page, it leaves a mode',
    HotkeyPlace.anywhere,
  );
  static const editText = Hotkey(
    'E',
    "Edit what's being read: a description, or the goal, habit, person or "
        'trait whose page is open, as its pencil does',
    HotkeyPlace.anywhere,
  );
  static const help = Hotkey('?', 'Show this list', HotkeyPlace.anywhere);
  static const up = Hotkey(
    'U',
    'Go up a level, as the back button does: from an editor to what it '
        "edits -- with changes made, as Esc does -- or from a habit's page, "
        'say, back to the Habits pane; and close a dialog or menu',
    HotkeyPlace.anywhere,
  );
  static const newThing = Hotkey(
    '+',
    'Make a new one of what the page or pane shows, as its + does: a '
        "goal, or on a goal's page a sub-goal; an action, habit, person, "
        'location or travel time. A note or an event, too: see Ctrl+M and C',
    HotkeyPlace.anywhere,
  );
  static const signIn = Hotkey(
    'S',
    'Sign in, where a page asks you to',
    HotkeyPlace.anywhere,
  );
  static const stepAny = Hotkey(
    'J / K',
    "Elsewhere, in a menu or a list -- a goal's sub-goals, say -- "
        'highlight the next (J) or previous (K) item, from the first (J) or '
        'last (K) in view; Enter taps it. Tab and Shift+Tab go from button '
        "to button, in it and where there's no list",
    HotkeyPlace.anywhere,
  );
  static const endsAny = Hotkey(
    'Home / End',
    'Where J and K go through a list, highlight its first (Home) or last '
        '(End) item',
    HotkeyPlace.anywhere,
  );
  static const scrollAny = Hotkey(
    '↑ / ↓',
    "Scroll what's on top: a page, a dialog -- this list -- or a sheet",
    HotkeyPlace.anywhere,
  );
  static const leaveField = Hotkey(
    'Esc',
    'Leave the text field, so letters are hotkeys again -- only that, '
        'even in an editor',
    HotkeyPlace.anywhere,
  );
  static const search = Hotkey(
    '/',
    "Go to the search box shown, with what's in it selected",
    HotkeyPlace.anywhere,
  );
  static const fieldLetters = Hotkey(
    'A–Z',
    'In a dialog, sheet or editor, go to a field by its letter -- hold Ctrl '
        "to see them: a text field to type in, what's there selected; a "
        'switch or checkbox flipped; a picker opened',
    HotkeyPlace.anywhere,
  );

  static const stepEvents = Hotkey(
    'J / K',
    'Highlight the next event (J) or the one before (K), from the one '
        'happening now; past the last of the day, onto the next',
    HotkeyPlace.events,
  );
  static const endEvents = Hotkey(
    'Home / End',
    'Highlight the first (Home) or last (End) event of the day',
    HotkeyPlace.events,
  );
  static const openEvent = Hotkey(
    'Enter',
    'Open the event highlighted',
    HotkeyPlace.events,
  );
  static const days = Hotkey(
    'H / L',
    'Go to the day before (H) or after (L)',
    HotkeyPlace.events,
  );
  static const scroll = Hotkey(
    '↑ / ↓',
    'Scroll the timeline, by as much as Settings says',
    HotkeyPlace.events,
  );
  static const now = Hotkey('T', 'Go to now', HotkeyPlace.events);
  static const create = Hotkey(
    'C / +',
    'Make an event: a cursor, at the end of the event highlighted, or now',
    HotkeyPlace.events,
  );
  static const moveCursor = Hotkey(
    'J / K',
    'Move the cursor to its next stop, later (J) or earlier (K)',
    HotkeyPlace.creating,
  );
  static const setStart = Hotkey(
    'Enter',
    'Set the start, at the cursor; J and K then move the end',
    HotkeyPlace.creating,
  );
  static const setEnd = Hotkey(
    'Enter',
    'Once there are two cursors, go on, as ✓ does',
    HotkeyPlace.creating,
  );
  static const leaveMode = Hotkey(
    'Esc',
    'Leave it, as ✕ does',
    HotkeyPlace.creating,
  );

  static const who = Hotkey('W', 'Who it was with and for', HotkeyPlace.event);
  static const location = Hotkey('L', 'Where it was', HotkeyPlace.event);
  static const description = Hotkey('D', 'Its description', HotkeyPlace.event);
  static const actions = Hotkey('A', 'Its actions', HotkeyPlace.event);
  static const summary = Hotkey(
    'S',
    'Its summary, selected, to type over',
    HotkeyPlace.event,
  );
  static const priority = Hotkey('P', 'Its priority', HotkeyPlace.event);
  static const commute = Hotkey(
    'C',
    'Whether it is part of a commute',
    HotkeyPlace.event,
  );
  static const time = Hotkey('T', 'When it is', HotkeyPlace.event);
  static const repeat = Hotkey('R', 'How it repeats', HotkeyPlace.event);
  static const eventNotes = Hotkey(
    'N',
    'What happened: its notes',
    HotkeyPlace.event,
  );
  static const deleteEvent = Hotkey(
    'Delete',
    'Cancel or delete it, as its trash can does',
    HotkeyPlace.event,
  );

  static const planItems = Hotkey(
    'J / K',
    'Go down (J) or up (K) the items of the pane shown -- a goal, say -- '
        "from the first (J) or last (K) in view; Enter opens what's "
        'highlighted, and Tab goes to the buttons in it',
    HotkeyPlace.plan,
  );
  static const planEnds = Hotkey(
    'Home / End',
    'Go to the first (Home) or last (End) item of the pane shown',
    HotkeyPlace.plan,
  );
  static const planPanes = Hotkey(
    'G / A / H / P / L',
    "Go to a pane by its title's first letter: Goals (G), Actions (A), "
        'Habits (H), People (P) or Locations (L)',
    HotkeyPlace.plan,
  );

  static const markDone = Hotkey('D', 'Mark it done', HotkeyPlace.goal);
  static const markMissed = Hotkey('M', 'Mark it missed', HotkeyPlace.goal);
  static const retry = Hotkey(
    'T',
    'Mark it missed and try again, by a day picked',
    HotkeyPlace.goal,
  );

  static const diagnosticsPanes = Hotkey(
    'H / L',
    'Go to the Server pane (H) or the App pane (L)',
    HotkeyPlace.diagnostics,
  );
  static const graphs = Hotkey(
    'J / K',
    'Highlight the next graph (J) or the one before (K)',
    HotkeyPlace.diagnostics,
  );
  static const zoom = Hotkey(
    '= / -',
    "Zoom the pane's graphs in (=) or out (-)",
    HotkeyPlace.diagnostics,
  );

  /// Every one, in the order the list shows them.
  static const all = [
    newNote,
    newGoal,
    notes,
    events,
    plan,
    menu,
    save,
    discard,
    editText,
    help,
    up,
    newThing,
    signIn,
    stepAny,
    endsAny,
    scrollAny,
    leaveField,
    search,
    fieldLetters,
    stepEvents,
    endEvents,
    openEvent,
    days,
    scroll,
    now,
    create,
    moveCursor,
    setStart,
    setEnd,
    leaveMode,
    who,
    location,
    description,
    actions,
    summary,
    priority,
    commute,
    time,
    repeat,
    eventNotes,
    deleteEvent,
    planItems,
    planEnds,
    planPanes,
    markDone,
    markMissed,
    retry,
    diagnosticsPanes,
    graphs,
    zoom,
  ];
}

/// What sets off a [HotkeyBinding]: Ctrl and a key, which works even in
/// a text field; a letter after Ctrl+B, Ctrl let go first, which does
/// too; or a key alone, which works only while no text field has focus.
@immutable
class HotkeyTrigger {
  /// Ctrl and [key].
  const HotkeyTrigger.ctrl(this.key) : _kind = _Kind.ctrl;

  /// [key], a letter, pressed alone after Ctrl+B.
  const HotkeyTrigger.afterCtrlB(this.key) : _kind = _Kind.afterCtrlB;

  /// [key] alone; held, it repeats.
  const HotkeyTrigger.key(this.key) : _kind = _Kind.key;

  final LogicalKeyboardKey key;
  final _Kind _kind;
}

enum _Kind { ctrl, afterCtrlB, key }

/// What a [HotkeyBinding] does while something -- a dialog, another
/// page -- is over the page it's on.
enum WhenCovered {
  /// Nothing: the key goes on to whatever's over it.
  ignore,

  /// Its [HotkeyBinding.onPressed] all the same.
  run,
}

/// A key ([trigger]) and what it does ([onPressed]) -- while [when]
/// says it does, if it's given: while what it's for is shown, say.
@immutable
class HotkeyBinding {
  const HotkeyBinding(
    this.trigger,
    this.onPressed, {
    this.whenCovered = WhenCovered.ignore,
    this.when,
  });

  final HotkeyTrigger trigger;
  final VoidCallback onPressed;
  final WhenCovered whenCovered;
  final ValueGetter<bool>? when;
}

/// The app's hotkeys, kept by a [HotkeyScope] over the navigator, and
/// told by it ([NavigatorObserver]) what's open: the keys pressed, the
/// [HotkeyBindings] of the pages and dialogs open, whether the hints are
/// shown ([hintsShown]: Ctrl held a moment) and whether a letter after
/// Ctrl+B is waited for ([afterCtrlB]).
class Hotkeys extends NavigatorObserver with ChangeNotifier {
  Hotkeys({this.hintDelay = const Duration(milliseconds: 300)});

  /// How long Ctrl is held alone before the hints show: not for a quick
  /// Ctrl+C.
  final Duration hintDelay;

  bool _hintsShown = false;
  bool get hintsShown => _hintsShown;

  bool _afterCtrlB = false;
  bool get afterCtrlB => _afterCtrlB;

  /// Whether a key's been pressed on a keyboard, besides one typed into a
  /// text field: so there's a keyboard to use hotkeys on.
  bool get keyboardSeen => _keyboardSeen;
  bool _keyboardSeen = false;

  final _routes = <Route<dynamic>>[];

  /// Whether a dialog, sheet or menu is open over the pages.
  bool get dialogOpen => _routes.any((r) => r is PopupRoute);

  /// Whether a page is open over the first.
  bool get pageOpen => _routes.whereType<PageRoute>().length > 1;

  final _registered = <_HotkeyBindingsState>[];
  Timer? _hintTimer;

  /// Shakes the screen, saying no: told to go elsewhere while a dialog
  /// waits to be saved or discarded.
  final shakes = ValueNotifier(0);
  void shake() => shakes.value++;

  bool _helpOpen = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) return;
    if (at < 0) {
      _routes.add(newRoute);
    } else {
      _routes[at] = newRoute;
    }
  }

  /// Leaves every page open over the first, to go to another of its own.
  void closePages() => navigator?.popUntil((r) => r.isFirst);

  void _setHints(bool shown) {
    if (_hintsShown == shown) return;
    _hintsShown = shown;
    notifyListeners();
  }

  void _setAfterCtrlB(bool waiting) {
    if (_afterCtrlB == waiting) return;
    _afterCtrlB = waiting;
    notifyListeners();
  }

  void _sawKeyboard() {
    if (_keyboardSeen) return;
    _keyboardSeen = true;
    notifyListeners();
  }

  /// Whether a text field has focus: keys alone go to it, then.
  static bool get _typing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  static bool _isCtrl(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight;

  static bool _isModifier(LogicalKeyboardKey key) =>
      _isCtrl(key) ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  /// The bindings that answer now: the newest first, each while its page
  /// or dialog is the one on top, or always if it says so.
  Iterable<HotkeyBinding> get _active sync* {
    for (final state in _registered.reversed) {
      final current = state.isCurrent;
      for (final b in state.widget.bindings) {
        if ((current || b.whenCovered == WhenCovered.run) &&
            (b.when?.call() ?? true)) {
          yield b;
        }
      }
    }
  }

  HotkeyBinding? _find(_Kind kind, LogicalKeyboardKey key) => _active
      .where((b) => b.trigger._kind == kind && b.trigger.key == key)
      .firstOrNull;

  /// Answers [event], if it's a hotkey.
  KeyEventResult handle(KeyEvent event) {
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyUpEvent) {
      if (_isCtrl(key)) {
        _hintTimer?.cancel();
        _setHints(false);
      }
      return KeyEventResult.ignored;
    }
    final down = event is KeyDownEvent;
    if (down && (keyboard.isControlPressed || !_typing)) _sawKeyboard();
    // Ctrl alone, held a moment: the hints. Anything else hides them.
    if (down && _isCtrl(key)) {
      _hintTimer?.cancel();
      _hintTimer = Timer(hintDelay, () => _setHints(true));
      return KeyEventResult.ignored;
    }
    if (!_isModifier(key)) {
      _hintTimer?.cancel();
      _setHints(false);
    }
    if (_afterCtrlB && down && !_isModifier(key)) {
      _setAfterCtrlB(false);
      if (key == LogicalKeyboardKey.escape) return KeyEventResult.handled;
      // Ctrl still held: not taken, so Ctrl+B, then Ctrl+N, doesn't go to
      // Notes while the browser opens a window.
      if (!keyboard.isControlPressed) {
        if (keyboard.isAltPressed || keyboard.isMetaPressed) {
          return KeyEventResult.handled;
        }
        _find(_Kind.afterCtrlB, key)?.onPressed();
        // Not typed into the field that has focus, whatever it was.
        return KeyEventResult.handled;
      }
    }
    final ctrl = keyboard.isControlPressed;
    final others = keyboard.isAltPressed || keyboard.isMetaPressed;
    if (ctrl && !others && !keyboard.isShiftPressed) {
      if (!down) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyB) {
        _setAfterCtrlB(true);
        return KeyEventResult.handled;
      }
      final binding = _find(_Kind.ctrl, key);
      if (binding == null) return KeyEventResult.ignored;
      binding.onPressed();
      return KeyEventResult.handled;
    }
    if (ctrl || others) return KeyEventResult.ignored;
    if (_typing) {
      if (down && key == LogicalKeyboardKey.escape) {
        FocusManager.instance.primaryFocus?.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Enter or Space on what's no longer shown -- in a pane of the Plan
    // page swiped away from, say -- presses nothing: it lets go of it.
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (focus != null &&
          context != null &&
          focus is! FocusScopeNode &&
          !isPainted(context)) {
        if (down) focus.unfocus();
        return KeyEventResult.handled;
      }
    }
    if (down && event.character == '?') {
      unawaited(_showHelp());
      return KeyEventResult.handled;
    }
    // +, shifted or not, whatever the keyboard: what makes a new one.
    if (event.character == '+' || key == LogicalKeyboardKey.numpadAdd) {
      final binding = _find(_Kind.key, LogicalKeyboardKey.add);
      if (binding == null) return KeyEventResult.ignored;
      if (down) binding.onPressed();
      return KeyEventResult.handled;
    }
    if (keyboard.isShiftPressed) return KeyEventResult.ignored;
    final binding = _find(_Kind.key, key);
    if (binding != null) {
      binding.onPressed();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyK) {
      return stepFocus(later: key == LogicalKeyboardKey.keyJ)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // Esc, where nothing else takes it -- leaving a mode on the Events
    // page, say -- does what U does.
    if (key == LogicalKeyboardKey.keyU || key == LogicalKeyboardKey.escape) {
      if (!down) return KeyEventResult.handled;
      return goUp() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      return stepFocus(later: key == LogicalKeyboardKey.end, toEnd: true)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      return scrollTop(later: key == LogicalKeyboardKey.arrowDown)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// U where nothing else -- an editor, say ([SaveOrDiscard]) -- takes
  /// it: up a level, as the back button does, closing what's on top --
  /// a page, dialog, sheet or menu -- but not the first page. Whether
  /// there was one to.
  bool goUp() {
    final route = _routes.lastOrNull;
    if (route is! ModalRoute || route.isFirst) return false;
    unawaited(route.navigator?.maybePop());
    return true;
  }

  /// J or K where nothing else takes them: highlights the next item in
  /// what's on top -- a menu's, say -- [later], or the one before
  /// ([stepItems]); Enter taps it. Whether there was one to.
  bool stepFocus({required bool later, bool toEnd = false}) {
    final route = _routes.lastOrNull;
    if (route is! ModalRoute) return false;
    final context = route.subtreeContext;
    if (context == null) return false;
    final scope = FocusScope.of(context);
    // A menu is all items; anything else, only the lists in it that say
    // they are ([HotkeyItems]) -- with none, Tab goes from button to
    // button.
    if (route is PopupRoute &&
        route is! RawDialogRoute &&
        route is! ModalBottomSheetRoute) {
      return stepItems(scope, later: later, toEnd: toEnd);
    }
    final lists = [
      for (final node in scope.descendants)
        if (node is _ItemsNode &&
            node.context != null &&
            isPainted(node.context!))
          node,
    ];
    if (lists.isEmpty) return false;
    // The one with an item highlighted, or else the first.
    final focus = FocusManager.instance.primaryFocus;
    final list = lists.firstWhere(
      (list) => focus?.ancestors.contains(list) ?? false,
      orElse: () => lists.first,
    );
    return stepItems(list, later: later, toEnd: toEnd);
  }

  /// Scrolls what's on top -- a page, a dialog or a sheet, not a menu,
  /// whose arrows go between its items -- down ([later]) or up, by a fifth
  /// of what shows: its biggest list that scrolls up and down. Whether
  /// there was one to.
  bool scrollTop({required bool later}) {
    final route = _routes.lastOrNull;
    if (route is! ModalRoute ||
        (route is PopupRoute &&
            route is! RawDialogRoute &&
            route is! ModalBottomSheetRoute)) {
      return false;
    }
    final context = route.subtreeContext;
    if (context == null) return false;
    ScrollPosition? biggest;
    void visit(Element element) {
      if (element case StatefulElement(:final ScrollableState state)) {
        final position = state.position;
        // Not a pane swiped away -- another of the Plan page's, say -- that
        // its page view keeps.
        if (!isPainted(element)) return;
        if (position.axis == Axis.vertical &&
            position.hasContentDimensions &&
            position.maxScrollExtent > position.minScrollExtent &&
            position.viewportDimension > (biggest?.viewportDimension ?? 0)) {
          biggest = position;
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    final position = biggest;
    if (position == null) return false;
    final by = position.viewportDimension / 5;
    position.animateTo(
      (position.pixels + (later ? by : -by)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
    return true;
  }

  /// What's being said at the foot of the screen, a moment ([say]).
  String? get said => _said;
  String? _said;
  Timer? _sayTimer;

  /// Says [message] at the foot of the screen, over everything, for
  /// [forAbout].
  void say(String message, {Duration forAbout = const Duration(seconds: 3)}) {
    _sayTimer?.cancel();
    _said = message;
    notifyListeners();
    _sayTimer = Timer(forAbout, () {
      _said = null;
      notifyListeners();
    });
  }

  /// Stops saying [message], if it's what's said.
  void unsay(String message) {
    if (_said != message) return;
    _sayTimer?.cancel();
    _said = null;
    notifyListeners();
  }

  Future<void> _showHelp() async {
    final navigatorContext = navigator?.overlay?.context;
    if (_helpOpen || navigatorContext == null) return;
    _helpOpen = true;
    try {
      await showHotkeysDialog(navigatorContext);
    } finally {
      _helpOpen = false;
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _sayTimer?.cancel();
    shakes.dispose();
    super.dispose();
  }
}

/// Whether [context] is painted: not in a page of a [PageView] or
/// [TabBarView] swiped away but kept, nor [Offstage].
bool isPainted(BuildContext context) {
  if (!context.mounted) return false;
  RenderObject? child = context.findRenderObject();
  if (child == null || !child.attached) return false;
  for (var parent = child.parent; parent != null; parent = parent.parent) {
    if (!parent.paintsChild(child!)) return false;
    child = parent;
  }
  return true;
}

/// Whether [node] is in view in the lists that scroll up and down around
/// it: [wholly], or at all. Null if it's in none.
bool? inScrolledView(FocusNode node, {bool wholly = true}) {
  final context = node.context;
  if (context == null || !context.mounted) return null;
  final rect = node.rect;
  bool? shown;
  for (
    var list = Scrollable.maybeOf(context);
    list != null;
    list = Scrollable.maybeOf(list.context)
  ) {
    if (list.position.axis != Axis.vertical) continue;
    final view = list.context.findRenderObject();
    if (view is! RenderBox || !view.attached || !view.hasSize) continue;
    final bounds = view.localToGlobal(Offset.zero) & view.size;
    // A little leeway, for a row a fraction of a pixel past the edge.
    final inIt = wholly
        ? rect.top >= bounds.top - 1 && rect.bottom <= bounds.bottom + 1
        : rect.bottom > bounds.top && rect.top < bounds.bottom;
    shown = (shown ?? true) && inIt;
  }
  return shown;
}

/// Scrolls [context], scrolled away, back into view: in a list that
/// builds only what's near the view, kept only because it has focus, by
/// where the list laid it out last.
void _scrollBackTo(BuildContext context) {
  final list = Scrollable.maybeOf(context);
  var box = context.findRenderObject();
  // Up to the list's own child, which knows where it was laid out.
  while (box != null && box.parent is! RenderSliver) {
    box = box.parent;
  }
  if (box?.parentData case SliverMultiBoxAdaptorParentData(:final layoutOffset?)
      when list != null) {
    final position = list.position;
    position.jumpTo(
      layoutOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  } else {
    Scrollable.ensureVisible(context);
  }
}

/// [child], a list of items -- a goal's sub-goals, say -- for J and K to
/// go down and up ([stepItems]) on a page, or in a dialog or sheet:
/// without one, they do nothing there, and Tab goes from button to
/// button.
class HotkeyItems extends StatefulWidget {
  const HotkeyItems({super.key, required this.child});

  final Widget child;

  @override
  State<HotkeyItems> createState() => _HotkeyItemsState();
}

class _HotkeyItemsState extends State<HotkeyItems> {
  final _node = _ItemsNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}

/// [HotkeyItems]'s, to find it by.
class _ItemsNode extends FocusNode {
  _ItemsNode()
    : super(debugLabel: 'Items', canRequestFocus: false, skipTraversal: true);
}

/// Whether J and K can highlight [node]: something to tap, not a text
/// field, nor [NotAnItem].
bool _isStop(FocusNode node) {
  final context = node.context;
  return node.canRequestFocus &&
      !node.skipTraversal &&
      context != null &&
      context.mounted &&
      context.widget is! EditableText &&
      context.findAncestorWidgetOfExactType<EditableText>() == null &&
      context.findAncestorWidgetOfExactType<NotAnItem>() == null;
}

/// [child], at the head of a list but not one of its items -- a link
/// over the rows, say: J and K pass it by, though Tab goes to it.
class NotAnItem extends StatelessWidget {
  const NotAnItem({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// [within]'s items, as rows of what can be tapped in each: its stops,
/// top to bottom, in the rows they make -- each row's first, its item,
/// first -- and, where some are in a list that scrolls, only those.
List<List<FocusNode>> _itemRows(FocusNode within) {
  final stops =
      [
        for (final node in within.traversalDescendants)
          if (_isStop(node)) node,
      ]..sort((a, b) {
        final ra = a.rect, rb = b.rect;
        final dy = ra.top.compareTo(rb.top);
        return dy != 0 ? dy : ra.left.compareTo(rb.left);
      });
  final listed = [
    for (final node in stops)
      if (inScrolledView(node, wholly: false) != null) node,
  ];
  // Each row's stops, the first of them -- its item -- first.
  final rows = <List<FocusNode>>[];
  for (final node in listed.isEmpty ? stops : listed) {
    final y = node.rect.center.dy;
    final lead = rows.lastOrNull?.first.rect;
    if (lead != null && lead.top <= y && y <= lead.bottom) {
      rows.last.add(node);
    } else {
      rows.add([node]);
    }
  }
  return rows;
}

/// J ([later]) or K, in [within]: highlights the next item, or the one
/// before, scrolled into view -- even from one scrolled away. An item is
/// a row, highlighted by the first of what can be tapped in it -- a goal,
/// not its edit button, which Tab goes to -- and, where some are in a
/// list that scrolls, only those: not the buttons over it. With none
/// highlighted yet, from the first in view, or the last. Not a text
/// field, which letters would go into. With [toEnd] -- Home or End --
/// the first item, or the last ([later]). Whether there was one to.
bool stepItems(FocusNode within, {required bool later, bool toEnd = false}) {
  final rows = _itemRows(within);
  if (rows.isEmpty) return false;
  if (toEnd) return _toEnd(within, rows, last: later);
  final focus = FocusManager.instance.primaryFocus;
  if (focus != null &&
      rows.any((row) => row.contains(focus)) &&
      inScrolledView(focus, wholly: false) == false) {
    // Scrolled away: the items beside it may not be built. Back to it
    // first, then on, once they are.
    _scrollBackTo(focus.context!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (within.context?.mounted ?? false) stepItems(within, later: later);
    });
    return true;
  }
  final at = rows.indexWhere((row) => row.contains(focus));
  final FocusNode next;
  if (at >= 0) {
    next = rows[(at + (later ? 1 : -1)).clamp(0, rows.length - 1)].first;
  } else {
    final shown = [
      for (final row in rows)
        if (inScrolledView(row.first) ?? false) row.first,
    ];
    next =
        (later ? shown.firstOrNull : shown.lastOrNull) ??
        (later ? rows.first : rows.last).first;
  }
  _highlight(next, later: later);
  return true;
}

/// Home or End ([last]): the first of [within]'s items, or the last --
/// once the list it's in is scrolled to its start or end, where a list
/// that builds only what's near the view hasn't built it yet.
bool _toEnd(
  FocusNode within,
  List<List<FocusNode>> rows, {
  required bool last,
}) {
  final position = Scrollable.maybeOf(rows.first.first.context!)?.position;
  if (position != null && position.axis == Axis.vertical) {
    final edge = last ? position.maxScrollExtent : position.minScrollExtent;
    if (position.pixels != edge) {
      position.jumpTo(edge);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!(within.context?.mounted ?? false)) return;
        final now = _itemRows(within);
        if (now.isEmpty) return;
        _highlight((last ? now.last : now.first).first, later: last);
      });
      return true;
    }
  }
  _highlight((last ? rows.last : rows.first).first, later: last);
  return true;
}

/// Highlights [node], scrolled into view at the end of the view
/// ([later]), or its start.
void _highlight(FocusNode node, {required bool later}) {
  node.requestFocus();
  Scrollable.ensureVisible(
    node.context!,
    alignmentPolicy: later
        ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
        : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    duration: const Duration(milliseconds: 120),
  );
}

/// [child], a search box focused by [focus]: "/" puts the cursor in it,
/// what's in it selected, while it's shown, and holding Ctrl shows "/"
/// on it.
class SearchHotkey extends StatelessWidget {
  const SearchHotkey({super.key, required this.focus, required this.child});

  final FocusNode focus;
  final Widget child;

  @override
  Widget build(BuildContext context) => HotkeyBindings(
    bindings: [
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.slash),
        () => focusField(focus),
        when: () => isPainted(context),
      ),
    ],
    child: HotkeyHint(Hotkey.search, child: child),
  );
}

/// Puts the cursor in the text field [focus] focuses, what's in it
/// selected, to type over, and scrolls it into view.
void focusField(FocusNode focus) {
  focus.requestFocus();
  final context = focus.context;
  if (context == null) return;
  Scrollable.ensureVisible(
    context,
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    duration: const Duration(milliseconds: 120),
  );
  // Once it has focus, which puts the cursor at the end.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final controller = context
        .findAncestorStateOfType<EditableTextState>()
        ?.widget
        .controller;
    if (controller == null) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  });
}

/// A field of a dialog, sheet or editor, [child], with [letter] to go to
/// it while no text field has focus: a text field, focused, what's in it
/// selected; anything else that can be tapped -- a switch, a picker --
/// tapped, as Enter would -- or, with [focusOnly], for a field of many
/// parts, only focused, for Tab and Enter to go on from; or, with
/// [onPressed], that. Holding Ctrl shows the letter on it. Only while
/// it's shown, and not while [enabled] is false.
class FieldHotkey extends StatefulWidget {
  const FieldHotkey(
    this.letter, {
    super.key,
    this.onPressed,
    this.enabled = true,
    this.focusOnly = false,
    this.hint,
    required this.child,
  }) : assert(letter == null || letter.length == 1);

  /// One letter, A to Z -- or a digit, for one of a list numbered; null
  /// for none, where they've run out.
  final String? letter;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool focusOnly;

  /// What holding Ctrl shows on it, if not just [letter]: every key that
  /// does what it does.
  final Hotkey? hint;
  final Widget child;

  @override
  State<FieldHotkey> createState() => _FieldHotkeyState();
}

class _FieldHotkeyState extends State<FieldHotkey> {
  /// Around [FieldHotkey.child], to find what in it takes focus.
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _go() {
    if (widget.onPressed case final onPressed?) return onPressed();
    final target = _node.traversalDescendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .firstOrNull;
    final context = target?.context;
    if (target == null || context == null) return;
    final editable =
        context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editable) return focusField(target);
    target.requestFocus();
    if (widget.focusOnly) {
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 120),
      );
      return;
    }
    Actions.maybeInvoke(context, const ActivateIntent());
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.letter?.toUpperCase();
    final field = Focus(focusNode: _node, child: widget.child);
    return HotkeyBindings(
      bindings: [
        if (letter != null)
          HotkeyBinding(
            HotkeyTrigger.key(
              LogicalKeyboardKey(letter.toLowerCase().codeUnitAt(0)),
            ),
            _go,
            when: () => widget.enabled && isPainted(this.context),
          ),
      ],
      child: letter == null
          ? field
          : HotkeyHint(
              widget.hint ?? Hotkey(letter, '', HotkeyPlace.anywhere),
              child: field,
            ),
    );
  }
}

/// [child], a + button that makes something new: + presses it while
/// it's shown and can be, and holding Ctrl shows [hint] on it -- + and,
/// where another key does the same, that too.
class NewHotkey extends StatelessWidget {
  const NewHotkey({
    super.key,
    this.hint = Hotkey.newThing,
    required this.child,
  });

  final Hotkey hint;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FieldHotkey('+', hint: hint, child: child);
}

/// [child], the pencil of something being read -- a goal's page, say --
/// that edits it: E presses it while it's shown, and holding Ctrl shows
/// E on it.
class EditHotkey extends StatelessWidget {
  const EditHotkey({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FieldHotkey('E', hint: Hotkey.editText, child: child);
}

/// A letter for each of [names] -- fields named by what they hold, in
/// the order they're shown -- for [FieldHotkey]s: the first of its own
/// not taken already, nor [taken], nor J or K, which go from one thing
/// to the next, nor U, which goes up a level; none if every one is.
Map<String, String> fieldLetters(
  Iterable<String> names, {
  Set<String> taken = const {},
}) {
  final used = {'J', 'K', 'U', ...taken};
  final letters = <String, String>{};
  for (final name in names) {
    for (final c in name.toUpperCase().split('')) {
      if (c.compareTo('A') < 0 || c.compareTo('Z') > 0 || used.contains(c)) {
        continue;
      }
      letters[name] = c;
      used.add(c);
      break;
    }
  }
  return letters;
}

/// The one after [current] in [options], or after the last, the first:
/// what a choice's letter picks next.
T nextOf<T>(List<T> options, T current) =>
    options[(options.indexOf(current) + 1) % options.length];

/// Answers [hotkeys] for everything under it: put over the navigator, so
/// it hears keys pressed in every page and dialog. It shakes the screen
/// when [Hotkeys.shake]n, and shows what Ctrl+B waits for.
class HotkeyScope extends StatefulWidget {
  const HotkeyScope({super.key, required this.hotkeys, required this.child});

  final Hotkeys hotkeys;
  final Widget child;

  /// The app's hotkeys, if it has them.
  static Hotkeys? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_HotkeysInherited>()?.notifier;

  @override
  State<HotkeyScope> createState() => _HotkeyScopeState();
}

class _HotkeyScopeState extends State<HotkeyScope>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// Over the navigator: keys pressed with focus anywhere under it come
  /// here first, before the app's own shortcuts -- Esc closing a dialog,
  /// say.
  final _node = FocusNode(
    debugLabel: 'Hotkeys',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    widget.hotkeys.shakes.addListener(_shakeNow);
    HardwareKeyboard.instance.addHandler(_unfocused);
    FocusManager.instance.addLateKeyEventHandler(_elsewhere);
  }

  /// With nothing focused -- as on the web after a click on nothing that
  /// takes focus -- no widget hears keys at all: so they come here.
  bool _unfocused(KeyEvent event) =>
      FocusManager.instance.primaryFocus == null &&
      widget.hotkeys.handle(event) == KeyEventResult.handled;

  /// Keys left unanswered with focus outside [_node]: the root's.
  KeyEventResult _elsewhere(KeyEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus == _node || focus.ancestors.contains(_node)) {
      return KeyEventResult.ignored;
    }
    return widget.hotkeys.handle(event);
  }

  void _shakeNow() => _shake.forward(from: 0);

  @override
  void dispose() {
    widget.hotkeys.shakes.removeListener(_shakeNow);
    HardwareKeyboard.instance.removeHandler(_unfocused);
    FocusManager.instance.removeLateKeyEventHandler(_elsewhere);
    _node.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HotkeysInherited(
    notifier: widget.hotkeys,
    child: Focus(
      focusNode: _node,
      onKeyEvent: (_, event) => widget.hotkeys.handle(event),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = sin(t * pi * 6) * 12 * (1 - t);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: widget.child,
          ),
          ListenableBuilder(
            listenable: widget.hotkeys,
            builder: (context, _) => switch (widget.hotkeys) {
              Hotkeys(afterCtrlB: true) => _Chip(_afterCtrlB),
              Hotkeys(:final said?) => _Chip(said),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    ),
  );
}

class _HotkeysInherited extends InheritedNotifier<Hotkeys> {
  const _HotkeysInherited({required super.notifier, required super.child});
}

/// What Ctrl+B waits for.
String get _afterCtrlB {
  final waiting = [
    for (final h in Hotkey.all)
      if (h.afterCtrlB case final letter?) '$letter ${h.does}',
  ];
  return 'Ctrl+B: let go of Ctrl, then  ${waiting.join('  ·  ')}';
}

/// [text] at the foot of the screen, over everything.
class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 96,
      child: Center(
        child: Material(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(text, style: TextStyle(color: scheme.onInverseSurface)),
          ),
        ),
      ),
    );
  }
}

/// The keys of something being edited, to save or discard: Ctrl+Enter
/// saves ([onSave], once it can be: null while it can't), and Esc closes
/// it ([onDiscard], or by default, pops its route) -- but with changes
/// made (as [changed] says, asked as Esc is pressed), the first Esc only shakes the screen, saying so, and
/// a second soon after discards them. In one of its text fields, Esc
/// only leaves it, as it does anywhere else.
class SaveOrDiscard extends StatefulWidget {
  const SaveOrDiscard({
    super.key,
    required this.changed,
    required this.onSave,
    this.onDiscard,
    this.more = const [],
    required this.child,
  });

  final ValueGetter<bool> changed;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;

  /// Its other hotkeys.
  final List<HotkeyBinding> more;
  final Widget child;

  /// What the first Esc says.
  static const warning = 'Press Esc again to discard your changes';

  @override
  State<SaveOrDiscard> createState() => _SaveOrDiscardState();
}

class _SaveOrDiscardState extends State<SaveOrDiscard> {
  /// While a second Esc discards: a moment after the first.
  Timer? _armed;

  static const _window = Duration(seconds: 3);

  void _escape() {
    final hotkeys = HotkeyScope.maybeOf(context);
    if (widget.changed() && !(_armed?.isActive ?? false)) {
      _armed = Timer(_window, () {});
      hotkeys?.shake();
      hotkeys?.say(SaveOrDiscard.warning, forAbout: _window);
      return;
    }
    _armed?.cancel();
    hotkeys?.unsay(SaveOrDiscard.warning);
    (widget.onDiscard ?? () => Navigator.of(context).pop())();
  }

  @override
  void dispose() {
    _armed?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HotkeyBindings(
    bindings: [
      ...widget.more,
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.escape),
        _escape,
      ),
      HotkeyBinding(const HotkeyTrigger.ctrl(LogicalKeyboardKey.enter), () {
        widget.onSave?.call();
      }),
      // Up a level, as the back button does: as Esc, outside its fields.
      HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyU), _escape),
    ],
    child: widget.child,
  );
}

/// [child], a dialog or sheet whose Save or Done button is [onSave]:
/// Ctrl+Enter presses it, even from its text fields; nothing while it's
/// null, as the button can't be pressed. For one whose Esc should warn
/// before discarding changes, see [SaveOrDiscard].
class SaveHotkey extends StatelessWidget {
  const SaveHotkey({super.key, required this.onSave, required this.child});

  final VoidCallback? onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) => HotkeyBindings(
    bindings: [
      HotkeyBinding(const HotkeyTrigger.ctrl(LogicalKeyboardKey.enter), () {
        onSave?.call();
      }),
    ],
    child: child,
  );
}

/// Puts [bindings] to work while this is in the tree: while the page or
/// dialog it's in is the one on top, or for one that says so, whatever's
/// over it ([WhenCovered.run]). Nothing, without a [HotkeyScope] above.
class HotkeyBindings extends StatefulWidget {
  const HotkeyBindings({
    super.key,
    required this.bindings,
    required this.child,
  });

  final List<HotkeyBinding> bindings;
  final Widget child;

  @override
  State<HotkeyBindings> createState() => _HotkeyBindingsState();
}

class _HotkeyBindingsState extends State<HotkeyBindings> {
  Hotkeys? _hotkeys;
  ModalRoute<dynamic>? _route;

  /// Whether its page or dialog is the one on top.
  bool get isCurrent => _route?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final hotkeys = HotkeyScope.maybeOf(context);
    if (hotkeys == _hotkeys) return;
    _hotkeys?._registered.remove(this);
    _hotkeys = hotkeys?.._registered.add(this);
  }

  @override
  void dispose() {
    _hotkeys?._registered.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// [child], with [hotkey]'s [Hotkey.hint] over its corner while Ctrl is
/// held -- or, after Ctrl+B, its letter -- while the page or dialog it's
/// in is the one on top. Just [child], without a [HotkeyScope] above.
class HotkeyHint extends StatelessWidget {
  const HotkeyHint(this.hotkey, {super.key, required this.child});

  final Hotkey hotkey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hotkeys = HotkeyScope.maybeOf(context);
    if (hotkeys == null) return child;
    return ListenableBuilder(
      listenable: hotkeys,
      builder: (context, child) {
        final label = hotkeys.afterCtrlB
            ? hotkey.afterCtrlB
            : hotkeys.hintsShown
            ? hotkey.hint
            : null;
        final current = ModalRoute.of(context)?.isCurrent ?? true;
        // A stack all the same, so what's in it -- a text field being typed
        // in -- is kept as the hint comes and goes.
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            child!,
            if (label != null && current)
              Positioned(top: -6, right: -6, child: HotkeyBadge(label)),
          ],
        );
      },
      child: child,
    );
  }
}

/// A key, or keys, in a small box, as a [HotkeyHint] shows them.
class HotkeyBadge extends StatelessWidget {
  const HotkeyBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.tertiary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Whether the app's menu offers the list of hotkeys: on the web, or once
/// a keyboard's been used.
bool hotkeysOffered(BuildContext context) =>
    kIsWeb || (HotkeyScope.maybeOf(context)?.keyboardSeen ?? false);

/// Lists every hotkey, by where it works.
Future<void> showHotkeysDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Hotkeys'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hold Ctrl to see them on the buttons they stand for. Keys '
                'without Ctrl work while no text field has focus.',
                style: theme.textTheme.bodySmall,
              ),
              for (final place in HotkeyPlace.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(place.title, style: theme.textTheme.titleSmall),
                ),
                for (final h in Hotkey.all)
                  if (h.where == place)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 132,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: HotkeyBadge(h.keys),
                            ),
                          ),
                          Expanded(child: Text(h.does)),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  },
);
