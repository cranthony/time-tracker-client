import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/screens/today_screen.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

void main() {
  final now = DateTime(2026, 9, 28, 15, 0);

  Widget app(NotesRepository repo) => MaterialApp(
    home: TodayScreen(repository: repo, clock: () => now),
  );

  testWidgets('shows only today\'s uncompacted notes', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: DateTime(2026, 9, 28, 9, 30), description: 'Standup'),
      Note(timestamp: DateTime(2026, 9, 27, 18, 0), description: 'Yesterday'),
      Note(
        timestamp: DateTime(2026, 9, 28, 11, 0),
        description: 'Compacted',
        compactionId: 'c1',
      ),
      Note(timestamp: DateTime(2026, 9, 28, 13, 0)),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('(no description)'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Compacted'), findsNothing);
  });

  testWidgets('shows an empty state', (tester) async {
    await tester.pumpWidget(app(InMemoryNotesRepository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No notes yet today'), findsOneWidget);
  });

  testWidgets('+ adds a note', (tester) async {
    final repo = InMemoryNotesRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Writing Flutter app');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(
      (await repo.uncompactedNotes()).single.description,
      'Writing Flutter app',
    );
  });
}
