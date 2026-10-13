import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/server_url.dart';

void main() {
  final page = Uri.parse('https://tracker.corp.example/app/?x=1#/events');

  test('a full URL is the endpoint, on any platform', () {
    for (final web in [true, false]) {
      expect(
        serverEndpoint(
          'https://my-service.onrender.com/mcp',
          web: web,
          page: page,
        ),
        Uri.parse('https://my-service.onrender.com/mcp'),
      );
    }
  });

  test("on the web, a relative one is on the page's own origin, as a link "
      'would be', () {
    expect(
      serverEndpoint('/mcp', web: true, page: page),
      Uri.parse('https://tracker.corp.example/mcp'),
    );
    // From the app's own path, without its query or route.
    expect(
      serverEndpoint('mcp', web: true, page: page),
      Uri.parse('https://tracker.corp.example/app/mcp'),
    );
    expect(
      serverEndpoint(' /mcp ', web: true, page: page).host,
      'tracker.corp.example',
    );
  });

  test('elsewhere, a relative one is refused, saying why', () {
    expect(
      () => serverEndpoint('/mcp', web: false),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('only the web app can use'),
        ),
      ),
    );
  });
}
