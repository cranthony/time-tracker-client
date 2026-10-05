import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/platform/add_note_shortcut.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('time_tracker/add_note_shortcut');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final launchedAt = DateTime(2026, 9, 30, 8, 15);
  final tappedAt = DateTime(2026, 9, 30, 9, 40);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Sends a call from "Android" to the Dart side.
  Future<void> fromAndroid(String method, Object? arguments) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );

  test('reports the tap that launched the app, then later taps', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeLaunchRequest');
      return launchedAt.millisecondsSinceEpoch;
    });
    final shortcut = AddNoteShortcut(channel: channel, enabled: true);
    final taps = <DateTime>[];
    await shortcut.start();
    // Buffered until something listens, as on a cold start.
    shortcut.taps.listen(taps.add);

    await fromAndroid('addNote', tappedAt.millisecondsSinceEpoch);
    await pumpEventQueue();

    expect(taps, [launchedAt, tappedAt]);
    shortcut.dispose();
  });

  test('reports nothing when launched normally', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final shortcut = AddNoteShortcut(channel: channel, enabled: true);
    final taps = <DateTime>[];
    shortcut.taps.listen(taps.add);
    await shortcut.start();
    await pumpEventQueue();

    expect(taps, isEmpty);
    shortcut.dispose();
  });

  test('tells Android when the dialog\'s field is ready', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final shortcut = AddNoteShortcut(channel: channel, enabled: true);
    await shortcut.fieldReady();
    expect(calls, ['fieldReady']);
    shortcut.dispose();
  });

  test('does nothing off Android', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    final shortcut = AddNoteShortcut(channel: channel, enabled: false);
    await shortcut.start();
    await shortcut.fieldReady();
    expect(called, isFalse);
    shortcut.dispose();
  });
}
