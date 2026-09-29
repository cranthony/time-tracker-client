import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/auth/redirect_receiver.dart';

void main() {
  // main() builds the receiver before runApp. Constructing it once used a
  // platform channel, which throws before the Flutter binding exists, and
  // left the Android app stuck on its launch screen. Deliberately a plain
  // test(), not testWidgets(), so no binding has been initialized here.
  test('the Android receiver can be built before Flutter is set up', () {
    expect(AndroidRedirectReceiver.new, returnsNormally);
  });
}
