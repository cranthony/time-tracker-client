import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/note.dart' show localIsoTimestamp;
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/widgets/guided_review.dart';
import 'package:time_tracker_client/widgets/proposal_review.dart';

const _steps = <ReviewStep>[
  (page: ProposalDetailPage.notes, index: 0, key: 'n1'),
  (page: ProposalDetailPage.notes, index: 1, key: 'n2'),
  (page: ProposalDetailPage.goals, index: 0, key: 'g1'),
  (page: ProposalDetailPage.claude, index: 2, key: 'c1'),
];

Proposal _proposal() => Proposal.fromJson({
  'id': 'abc123def456',
  'revision': 1,
  'state': 'awaiting_review',
  'window_start': localIsoTimestamp(DateTime(2026, 9, 30, 8)),
  'through': localIsoTimestamp(DateTime(2026, 9, 30, 12)),
  'events': const [],
});

void main() {
  test('next is the following step not seen, then the first not seen', () {
    expect(nextToReview(_steps, {})?.key, 'n1');
    expect(nextToReview(_steps, {'n1'}, current: 'n1')?.key, 'n2');
    // Skips what's been seen.
    expect(nextToReview(_steps, {'n1', 'n2'}, current: 'n1')?.key, 'g1');
    // Past the last, back to one missed.
    expect(
      nextToReview(_steps, {'n1', 'g1', 'c1'}, current: 'c1')?.key,
      'n2',
    );
    // All seen: none.
    expect(
      nextToReview(_steps, {'n1', 'n2', 'g1', 'c1'}, current: 'g1'),
      isNull,
    );
  });

  test('the step after is the following one, seen or not', () {
    expect(stepAfter(_steps, {'n1', 'n2'}, current: 'n1')?.key, 'n2');
    expect(stepAfter(_steps, {}, current: 'g1')?.key, 'c1');
    // The last: none, even with some not seen.
    expect(stepAfter(_steps, {'c1'}, current: 'c1'), isNull);
    // None shown: where review left off, or else the first.
    expect(stepAfter(_steps, {'n1'})?.key, 'n2');
    expect(stepAfter(_steps, {'n1', 'n2', 'g1', 'c1'})?.key, 'n1');
    expect(stepAfter(const [], {}), isNull);
  });

  test('previous is the step before, seen or not', () {
    expect(previousToReview(_steps, current: 'g1')?.key, 'n2');
    expect(previousToReview(_steps, current: 'n1'), isNull);
    expect(previousToReview(_steps), isNull);
  });

  test('sections are a page each, in review order, with what\'s seen', () {
    final sections = reviewSections(_steps, {'n2'});
    expect([for (final s in sections) s.page], [
      ProposalDetailPage.notes,
      ProposalDetailPage.goals,
      ProposalDetailPage.claude,
    ]);
    expect(sections.first.seen, [false, true]);
    expect(reviewPageName(ProposalDetailPage.claude), 'Unsure');
  });

  testWidgets('guided, Next is where Confirm was, and a smaller Confirm '
      'is at the other end', (tester) async {
    var next = 0;
    var confirmed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalBar(
            proposal: _proposal(),
            onConfirm: () => confirmed++,
            onNext: () => next++,
            nextTooltip: 'Next: notes 2 of 3',
            progress: ReviewProgress(sections: reviewSections(_steps, {'n1'})),
          ),
        ),
      ),
    );
    final nextButton = find.widgetWithText(FilledButton, 'Next');
    final confirm = find.widgetWithText(OutlinedButton, 'Confirm');
    expect(nextButton, findsOneWidget);
    expect(confirm, findsOneWidget);
    expect(
      tester.getCenter(confirm).dx,
      lessThan(tester.getCenter(nextButton).dx),
    );
    expect(find.byTooltip('Next: notes 2 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Notes: 1 of 2 reviewed'), findsOneWidget);
    await tester.tap(nextButton);
    await tester.tap(confirm);
    expect((next, confirmed), (1, 1));

    // All reviewed: Confirm is back where Next was.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalBar(
            proposal: _proposal(),
            onConfirm: () => confirmed++,
          ),
        ),
      ),
    );
    expect(find.text('Next'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
  });
}
