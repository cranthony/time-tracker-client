import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/text_format.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/event_description.dart';
import 'package:time_tracker_client/widgets/recap_markdown.dart';

/// A typical phone's screen, in logical pixels.
const _phone = Size(390, 844);

const _markdown = '''
**This week**, by day:

| Day | Focus | Hours | Note |
|:----|:------|------:|:----:|
| Mon | Deep work | 3.5 | *good* |
| Tue | Meetings | 1 | `standup` ran long, then a planning session that took most of the afternoon |
| Wed | Errands | 0.5 | — |

- [x] Kept tea
- [ ] Walked after lunch

| Column one | Column two | Column three | Column four |
|---|---|---|---|
| A table wider than the screen | scrolls across | rather than squashing | its columns |
''';

void main() {
  for (final brightness in Brightness.values) {
    for (final (name, body) in [
      (
        'markdown_description',
        const EventDescription(
          _markdown,
          format: TextFormat.markdown,
          maxLines: null,
        ),
      ),
      ('markdown_recap', const RecapMarkdown(_markdown)),
    ]) {
      testWidgets('$name, ${brightness.name}', (tester) async {
        tester.view.physicalSize = _phone * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            home: Scaffold(
              body: SafeArea(
                child: Padding(padding: const EdgeInsets.all(16), child: body),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('${name}_${brightness.name}.png'),
        );
      });
    }
  }
}
