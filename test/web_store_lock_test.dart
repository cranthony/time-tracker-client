@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/store_lock.dart';
import 'package:time_tracker_client/outbox/web_store_lock.dart';

void main() {
  test("the browser's lock takes turns: one change at a time", () async {
    final lock = webStoreLock('test-lock');
    expect(lock, isA<WebStoreLock>());
    final order = <String>[];
    final release = Completer<void>();

    final first = lock.hold((_) async {
      order.add('first in');
      await release.future;
      order.add('first out');
    });
    final second = lock.hold((_) async => order.add('second in'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(order, ['first in']);

    release.complete();
    await Future.wait([first, second]);
    expect(order, ['first in', 'first out', 'second in']);
  });

  test("held too long elsewhere, it's given up, and not taken late", () async {
    final lock = webStoreLock('test-lock-2');
    final release = Completer<void>();
    final held = lock.hold((_) => release.future);
    var ran = false;

    await expectLater(
      lock.hold(
        (_) async => ran = true,
        wait: const Duration(milliseconds: 100),
      ),
      throwsA(isA<TimeoutException>()),
    );
    release.complete();
    await held;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ran, isFalse);
  });

  test('a store lock for a key on the web is the browser\'s', () {
    expect(IsolateStoreLock.forKey('notes'), isA<WebStoreLock>());
  });
}
