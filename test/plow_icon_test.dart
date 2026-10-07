import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/plow_icon.dart';

void main() {
  testWidgets("drawn at the icon theme's size, or its own", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(size: 22, color: Colors.black),
          child: Column(children: [PlowIcon(), PlowIcon(size: 40)]),
        ),
      ),
    );
    final sizes = [
      for (final e in find.byType(PlowIcon).evaluate())
        tester.getSize(
          find.descendant(
            of: find.byWidget(e.widget),
            matching: find.byType(CustomPaint),
          ),
        ),
    ];
    expect(sizes, [const Size.square(22), const Size.square(40)]);
  });
}
