// A link is opened by tapping it; held, or clicked with the right mouse
// button, it opens its menu: to open it, or copy its address.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/text_format.dart';
import 'package:time_tracker_client/widgets/event_description.dart';
import 'package:time_tracker_client/widgets/link_menu.dart';

void main() {
  group('a link recognizer', () {
    late List<String> calls;
    late LinkRecognizer recognizer;
    setUp(() {
      calls = [];
      recognizer = LinkRecognizer()
        ..onTap = (() => calls.add('tap'))
        ..onHold = ((_) => calls.add('hold'))
        ..onSecondaryTapUp = ((_) => calls.add('right click'));
    });
    tearDown(() => recognizer.dispose());

    Future<void> show(WidgetTester tester, {bool scrolls = false}) {
      Widget text = Text.rich(TextSpan(text: 'a link', recognizer: recognizer));
      if (scrolls) text = ListView(children: [text]);
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: text)),
        ),
      );
    }

    testWidgets('tapped, taps; held, holds, and letting go is no tap', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('a link'));
      expect(calls, ['tap']);
      calls.clear();
      await tester.longPress(find.text('a link'));
      expect(calls, ['hold']);
    });

    testWidgets('pressed for less than a hold, is a tap', (tester) async {
      await show(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a link')),
      );
      await tester.pump(linkHoldTimeout - const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, ['tap']);
    });

    testWidgets('right clicked, is a right click, and no tap', (tester) async {
      await show(tester);
      await tester.tap(find.text('a link'), buttons: kSecondaryButton);
      expect(calls, ['right click']);
    });

    testWidgets('dragged, to scroll, is neither', (tester) async {
      await show(tester, scrolls: true);
      await tester.drag(find.text('a link'), const Offset(0, -40));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, isEmpty);
    });
  });

  group("a description's link", () {
    late List<String?> copied;
    setUp(() {
      copied = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String?);
            }
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<void> show(WidgetTester tester, {bool selectable = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EventDescription(
                'See [the doc](https://example.com/doc) first.',
                format: TextFormat.markdown,
                selectable: selectable,
              ),
            ),
          ),
        );

    /// Where the link is: its text's start, a little in.
    Offset link(WidgetTester tester) =>
        tester.getTopLeft(find.byType(RichText).first) + const Offset(60, 8);

    for (final selectable in [false, true]) {
      testWidgets('held${selectable ? ', in selectable text,' : ''} opens '
          'its menu; "Copy link address" copies it and says so', (
        tester,
      ) async {
        await show(tester, selectable: selectable);
        await tester.longPressAt(link(tester));
        await tester.pumpAndSettle();
        expect(find.text('Open link'), findsOneWidget);
        await tester.tap(find.text('Copy link address'));
        await tester.pumpAndSettle();
        expect(copied, ['https://example.com/doc']);
        expect(find.text('Link address copied'), findsOneWidget);
        expect(find.text('Open link'), findsNothing);
      });

      testWidgets('right clicked${selectable ? ', in selectable text,' : ''} '
          'opens its menu too', (tester) async {
        await show(tester, selectable: selectable);
        await tester.tapAt(link(tester), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        expect(find.text('Copy link address'), findsOneWidget);
        expect(find.text('Open link'), findsOneWidget);
      });
    }

    testWidgets('held off the link, opens no menu', (tester) async {
      await show(tester);
      await tester.longPressAt(
        tester.getTopLeft(find.byType(RichText).first) + const Offset(4, 8),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy link address'), findsNothing);
    });
  });
}
