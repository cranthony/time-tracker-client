import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/status_bar.dart';

/// A source that says [line], with [section] in the sheet.
class _Source extends ChangeNotifier implements StatusSource {
  _Source({this.text, this.items = const []});

  String? text;
  bool needsYou = false;
  List<String> items;

  void say(String? text, {bool needsYou = false}) {
    this.text = text;
    this.needsYou = needsYou;
    notifyListeners();
  }

  @override
  Listenable get listenable => this;

  @override
  int get count => items.length;

  @override
  StatusLine? line(BuildContext context) => switch (text) {
    final text? => StatusLine(
      icon: Icons.info_outline,
      text: text,
      needsYou: needsYou,
    ),
    null => null,
  };

  @override
  List<Widget> section(BuildContext context) => [
    for (final item in items) Text(item),
  ];
}

void main() {
  Future<void> pump(WidgetTester tester, List<StatusSource> sources) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(bottomNavigationBar: StatusBar(sources: sources)),
        ),
      );

  testWidgets('nothing, while no source has anything to say', (tester) async {
    await pump(tester, [_Source(), _Source()]);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('says the first that needs you, else the first, as they '
      'change', (tester) async {
    final a = _Source(text: 'Saving 1 change');
    final b = _Source();
    await pump(tester, [a, b]);
    expect(find.text('Saving 1 change'), findsOneWidget);

    b.say("Couldn't save it: tap to fix it", needsYou: true);
    await tester.pump();
    expect(find.text("Couldn't save it: tap to fix it"), findsOneWidget);
    expect(find.text('Saving 1 change'), findsNothing);
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
          .first,
    );
    expect(
      material.color,
      Theme.of(tester.element(find.byType(InkWell))).colorScheme.errorContainer,
    );

    b.say(null);
    await tester.pump();
    expect(find.text('Saving 1 change'), findsOneWidget);
  });

  testWidgets('tapping it slides up every source with anything to show', (
    tester,
  ) async {
    await pump(tester, [
      _Source(text: 'Saving 2 changes', items: ['One', 'Two']),
      _Source(),
      _Source(items: ['Three']),
    ]);

    await tester.tap(find.byType(StatusBar));
    await tester.pumpAndSettle();

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('the scope counts what its sources have waiting', (tester) async {
    final scope = StatusScope(
      sources: [
        _Source(items: ['One', 'Two']),
        _Source(items: ['Three']),
      ],
      child: const SizedBox(),
    );
    expect(scope.count, 3);
  });
}
