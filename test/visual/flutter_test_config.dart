// Set-up for the visual tests in this directory -- see "Visual tests" in
// README.md. flutter_test runs this around every test file here.
//
// The tests compare nothing: they load the real fonts (Roboto and Material
// Icons, which ship with the Flutter SDK) and write every screen they
// render to build/screenshots/, or to the directory in
// --dart-define=SCREENSHOTS_DIR=... CI renders a PR's screens and its base
// branch's, and tool/visual_diff.py shows what changed.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _directory = String.fromEnvironment(
  'SCREENSHOTS_DIR',
  defaultValue: 'build/screenshots',
);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadRealFonts();
  goldenFileComparator = _ScreenshotWriter(Directory(_directory));
  await testMain();
}

/// Writes every render to [directory], named after its "golden".
class _ScreenshotWriter extends GoldenFileComparator {
  _ScreenshotWriter(this.directory);

  final Directory directory;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    await update(golden, imageBytes);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final file = File('${directory.path}/${golden.pathSegments.last}');
    await file.create(recursive: true);
    await file.writeAsBytes(imageBytes);
  }
}

/// Loads Roboto (the Material font on Android, which tests emulate) and the
/// Material Icons from the Flutter SDK, so screenshots show real text.
Future<void> _loadRealFonts() async {
  final fonts = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(await File('$fonts/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    roboto.addFont(font('roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('materialicons-regular.otf'))).load();
}

/// The Flutter SDK's root: FLUTTER_ROOT, which `flutter test` sets, or
/// found from the test runner's own path inside the SDK.
String _flutterRoot() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return root;
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/bin/cache/artifacts').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError("Can't find the Flutter SDK; set FLUTTER_ROOT");
    }
    dir = dir.parent;
  }
  return dir.path;
}
