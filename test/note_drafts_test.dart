import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/services/note_drafts.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  final at = DateTime.utc(2026, 10, 14, 9, 30);

  test('drafts are kept on the device, for the next run of the app', () async {
    final drafts = NoteDrafts.device();
    await drafts.put(NoteDraft(id: 'd1', timestamp: at, description: 'Wal'));
    await drafts.put(
      NoteDraft(id: 'd1', timestamp: at, description: 'Walking home'),
    );
    await drafts.put(
      NoteDraft(
        id: NoteDraft.editId('n1'),
        timestamp: at,
        description: 'Standup, late',
        original: Note(timestamp: at, description: 'Standup', id: 'n1'),
      ),
    );

    final later = NoteDrafts.device();
    await later.load();
    expect(later.drafts.map((d) => d.description), [
      'Walking home',
      'Standup, late',
    ]);
    final edit = later.byId('edit:n1')!;
    expect(edit.isEdit, isTrue);
    expect(edit.original!.id, 'n1');
    expect(edit.note.id, 'n1');

    await later.remove('d1');
    await later.remove('edit:n1');
    final after = NoteDrafts.device();
    await after.load();
    expect(after.drafts, isEmpty);
  });

  test("a draft's note has its description trimmed, none if it's blank", () {
    expect(
      NoteDraft(
        id: 'd',
        timestamp: at,
        description: '  Lunch ',
      ).note.description,
      'Lunch',
    );
    expect(
      NoteDraft(id: 'd', timestamp: at, description: '  ').note.description,
      isNull,
    );
  });
}
