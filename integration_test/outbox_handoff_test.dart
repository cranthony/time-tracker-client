// On an Android emulator (or device): changes handed off between the app
// and its WorkManager background task -- each with its own outboxes, in
// its own isolate, sharing what's kept in SharedPreferences -- are each
// sent once. None lost, none twice, and changes to events in the order
// they were made.
//
// The "server" is a file both isolates append to: each note and event
// it's asked to save, and who asked. The app goes to the background and
// back as the app does (stop, schedule the background task; cancel it,
// pick up what it did, start), taking notes and making events between,
// while the task runs alongside it.
//
//     flutter test integration_test/outbox_handoff_test.dart -d emulator-5554
//
// Run by tool/emulator/handoff_test.sh, in .github/workflows/emulator.yml.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/background_sync.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

/// The background task's, as WorkManager runs it: the outboxes, sending
/// to the file.
@pragma('vm:entry-point')
void handoffDispatcher() => BackgroundSync.run(
  () => [
    NoteOutbox(
      store: PrefsOutboxStore.notes(),
      repository: _FileNotes('background'),
      sender: Outbox.backgroundSender,
    ),
    EventOutbox(
      store: PrefsOutboxStore.events(),
      events: _FileEvents('background'),
      sender: Outbox.backgroundSender,
    ),
  ],
);

Future<File> _server() async =>
    File('${(await getTemporaryDirectory()).path}/handoff_server.txt');

final _random = Random();

/// A request's time on the wire: long enough for the other sender to
/// come in meanwhile.
Future<void> _wire() =>
    Future<void>.delayed(Duration(milliseconds: 30 + _random.nextInt(250)));

/// What the file says was saved: each line's fields, split by "|".
Future<List<List<String>>> _saved() async {
  final file = await _server();
  if (!file.existsSync()) return const [];
  return [
    for (final line in await file.readAsLines())
      if (line.isNotEmpty) line.split('|'),
  ];
}

/// Notes saved to the file, as [who].
class _FileNotes extends InMemoryNotesRepository {
  _FileNotes(this.who);

  final String who;

  @override
  Future<Note> addNote(Note note) async {
    await _wire();
    await (await _server()).writeAsString(
      'note|${note.timestamp.toUtc().toIso8601String()}|${note.description}|$who\n',
      mode: FileMode.append,
      flush: true,
    );
    await _wire();
    return note;
  }

  /// Those in the file: for a sender to check a note was saved, unheard.
  @override
  Future<List<Note>> uncompactedNotes() async => [
    for (final f in await _saved())
      if (f[0] == 'note')
        Note(timestamp: DateTime.parse(f[1]).toLocal(), description: f[2]),
  ];
}

/// Events made in the file, as [who].
class _FileEvents extends InMemoryEventsRepository {
  _FileEvents(this.who) : super(const []);

  final String who;

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    await _wire();
    await (await _server()).writeAsString(
      'event|${fields['start']}|${fields['end']}|${fields['summary']}|$who\n',
      mode: FileMode.append,
      flush: true,
    );
    await _wire();
    return [
      Event.fromJson({...fields, 'id': '${fields['summary']}'}),
    ];
  }

  /// Those in the file: for a sender to check one was made, unheard.
  @override
  Future<List<Event>> events(DateTime from, DateTime to) async => [
    for (final f in await _saved())
      if (f[0] == 'event')
        Event(
          id: f[3],
          summary: f[3],
          start: DateTime.parse(f[1]),
          end: DateTime.parse(f[2]),
        ),
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'changes handed between the app and its background task are each sent '
    'once',
    (tester) async {
      final prefs = SharedPreferencesAsync();
      await prefs.remove('note_outbox');
      await prefs.remove('event_outbox');
      final server = await _server();
      if (server.existsSync()) server.deleteSync();
      await BackgroundSync.initialize(handoffDispatcher);

      final notes = NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: _FileNotes('app'),
      );
      final events = EventOutbox(
        store: PrefsOutboxStore.events(),
        events: _FileEvents('app'),
      );
      final made = <String>[];
      final day = DateTime(2026, 10, 9, 6);
      Future<void> take(int n) async {
        for (var i = 0; i < n; i++) {
          final k = made.length;
          made.add('$k');
          await notes.add(
            Note(
              timestamp: day.add(Duration(minutes: k)),
              description: 'n$k',
            ),
          );
          await events.create({
            'summary': 'e$k',
            'start': localIsoTimestamp(day.add(Duration(minutes: k * 5))),
            'end': localIsoTimestamp(day.add(Duration(minutes: k * 5 + 4))),
          });
        }
      }

      void foreground() {
        notes.start();
        events.start();
      }

      Future<void> background() async {
        notes.stop();
        events.stop();
        await BackgroundSync.schedule();
      }

      Future<void> resumed() async {
        await BackgroundSync.cancel();
        await notes.refresh();
        await events.refresh();
        foreground();
      }

      Future<int> sentBy(String who) async =>
          (await _saved()).where((f) => f.last == who).length;

      // A start, sending as the notes are taken.
      foreground();
      await take(6);
      await Future<void>.delayed(const Duration(seconds: 1));

      for (var round = 0; round < 3; round++) {
        // To the background, with changes still waiting -- one perhaps in
        // flight -- and more made meanwhile (as the home screen widget's
        // notes are), for the task to send.
        await background();
        await take(4);
        final before = await sentBy('background');
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (await sentBy('background') == before &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        // Back, while the task may still be sending.
        await resumed();
        await take(4);
        await Future<void>.delayed(
          Duration(milliseconds: 500 + _random.nextInt(1500)),
        );
      }

      // Both at once, till nothing's waiting.
      await BackgroundSync.schedule();
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (((await PrefsOutboxStore.notes().load()).isNotEmpty ||
              (await PrefsOutboxStore.events().load()).isNotEmpty) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      notes.dispose();
      events.dispose();

      final saved = await _saved();
      final savedNotes = [
        for (final f in saved)
          if (f[0] == 'note') f[2],
      ];
      final savedEvents = [
        for (final f in saved)
          if (f[0] == 'event') f[3],
      ];
      // ignore: avoid_print
      print(
        'Handoff: ${made.length} notes and events; sent by the app '
        '${await sentBy('app')}, by the background task '
        '${await sentBy('background')}.',
      );

      expect(await PrefsOutboxStore.notes().load(), isEmpty);
      expect(await PrefsOutboxStore.events().load(), isEmpty);
      // Each once: none lost, none twice.
      expect(savedNotes..sort(), [for (final k in made) 'n$k']..sort());
      // In the order made, too.
      expect(savedEvents, [for (final k in made) 'e$k']);
      // And the background task did send some: it was handed off to.
      expect(await sentBy('background'), greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
