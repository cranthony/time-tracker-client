// Set-up for every test here but the visual tests, which have their own
// (test/visual/flutter_test_config.dart): flutter_test runs this around
// every test file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  useScoresHere();
  await testMain();
}

/// Works the traits' scores out there and then, rather than on another
/// isolate: a widget test's clock is fake, and an isolate's answer would
/// never come.
void useScoresHere() =>
    PlanMemory.runScores = (work) => SynchronousFuture(work());
