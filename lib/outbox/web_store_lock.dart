import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'store_lock.dart';

/// The lock for a store on the web: the browser's (Web Locks), [name]d,
/// which every tab and window of the app shares -- so two windows open at
/// once take turns changing what's kept, and neither loses the other's
/// change. Where the browser has none (an old one, or a page not served
/// securely), none.
StoreLock webStoreLock(String name) {
  final navigator = web.window.navigator as JSObject;
  return navigator.has('locks') ? WebStoreLock(name) : const NoStoreLock();
}

/// A store lock held through the browser's Web Locks: one holder at a
/// time across every tab and window of the app. Released, by the browser,
/// once [hold]'s action -- and what it said to wait for -- is done, or
/// once the tab holding it is closed.
class WebStoreLock implements StoreLock {
  const WebStoreLock(this.name);

  final String name;

  @override
  Future<T> hold<T>(
    Future<T> Function(void Function(Future<void> done) keepUntil) action, {
    Duration wait = const Duration(seconds: 30),
  }) {
    final result = Completer<T>();
    // Not granted in time: asked no longer, so it isn't taken late.
    final waiting = web.AbortController();
    final timer = Timer(wait, () {
      if (result.isCompleted) return;
      waiting.abort();
      result.completeError(
        TimeoutException('The outbox store is busy in another window.'),
      );
    });

    JSPromise<JSAny?> granted(web.Lock? lock) {
      timer.cancel();
      final pending = <Future<void>>[];
      Future<void> run() async {
        try {
          result.complete(await action(pending.add));
        } catch (e, stack) {
          result.completeError(e, stack);
        }
        await Future.wait([
          for (final p in pending) p.catchError((Object _) {}),
        ]);
      }

      // Held till it's done: the browser lets go when this settles.
      return run().then((_) => null as JSAny?).toJS;
    }

    web.window.navigator.locks
        .request(name, web.LockOptions(signal: waiting.signal), granted.toJS)
        .toDart
        .catchError((Object _) => null);
    return result.future;
  }
}
