import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/widgets/fact_prompts_dialog.dart';

const _caring = Trait(
  id: 'caring',
  name: 'Caring',
  facts: [
    TraitFact(
      id: 'worries',
      name: 'Worries',
      summaryPrompt: 'What weighs on them.',
      logPrompt: 'What new worry showed.',
    ),
  ],
);

void main() {
  group("A person's own fact prompts", () {
    test('are read and sent back as the server keeps them', () {
      final traits = PersonTraits.fromJson({
        'select': 'all',
        'facts': {
          'caring': {
            'worries': {
              'summary_prompt': {'text': 'Their health.', 'how': 'append'},
              'log_prompt': {'text': 'Who told me.'},
            },
            'joys': <String, Object?>{},
          },
          'other': {'x': 'not prompts'},
        },
      });
      final own = traits.factPrompts('caring', 'worries')!;
      expect(
        own.summaryPrompt,
        const PromptOverride('Their health.', append: true),
      );
      expect(own.logPrompt, const PromptOverride('Who told me.'));
      expect(traits.factPrompts('caring', 'joys'), isNull);
      expect(traits.isDefault, isFalse);
      expect(traits.toJson(), {
        'select': 'all',
        'facts': {
          'caring': {
            'worries': {
              'summary_prompt': {'text': 'Their health.', 'how': 'append'},
              'log_prompt': {'text': 'Who told me.', 'how': 'replace'},
            },
          },
        },
      });
      expect(
        own.summaryPrompt!.applied('What weighs on them.'),
        'What weighs on them.\n\nTheir health.',
      );
      expect(own.logPrompt!.applied('What new worry showed.'), 'Who told me.');
      expect(const PromptOverride('Mine', append: true).applied(null), 'Mine');
      // Let go of, they leave nothing behind.
      final none = traits.withFactPrompts(
        'caring',
        'worries',
        const FactPromptOverride(),
      );
      expect(none.facts, isEmpty);
      expect(none.isDefault, isTrue);
      expect(
        const PersonTraits().withFactPrompts('caring', 'worries', own).facts,
        {
          'caring': {'worries': own},
        },
      );
    });

    testWidgets('are edited: replacing starts from the trait\'s, appending '
        'shows it above', (tester) async {
      FactPromptOverride? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showFactPromptsDialog(
                context,
                trait: _caring,
                fact: _caring.facts.single,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Worries: their own prompts'), findsOneWidget);
      // Both start as the trait's, shown.
      expect(find.text('What weighs on them.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Replace').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'What weighs on them.',
      );
      await tester.enterText(find.byType(TextField), 'Their health, mostly.');
      await tester.tap(find.text('Append').last);
      await tester.pumpAndSettle();
      expect(find.text('What new worry showed.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Say who told me.');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        result,
        const FactPromptOverride(
          summaryPrompt: PromptOverride('Their health, mostly.'),
          logPrompt: PromptOverride('Say who told me.', append: true),
        ),
      );
    });
  });
}
