import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/facts.dart';

void main() {
  test('several locations round-trip as location_ids', () {
    final facts = Facts.fromJson({
      'location_ids': ['home', 'park'],
      'with_ids': ['sam'],
    })!;
    expect(facts.locationIds, ['home', 'park']);
    expect(facts.toJson(), {
      'location_ids': ['home', 'park'],
      'with_ids': ['sam'],
    });
  });

  test('a commute round-trips, and false is left out', () {
    final facts = Facts.fromJson({'commute': true})!;
    expect(facts.commute, isTrue);
    expect(facts.isEmpty, isFalse);
    expect(facts.toJson(), {'commute': true});
    expect(facts == const Facts(), isFalse);
    // The server sends null when it's unset.
    final unset = Facts.fromJson({'commute': null})!;
    expect(unset.commute, isFalse);
    expect(unset.toJson(), isEmpty);
  });

  test('a single location_id is no longer read', () {
    expect(Facts.fromJson({'location_id': 'home'})!.locationIds, isEmpty);
  });

  test('describes each location, after who', () {
    expect(
      const Facts(
        withIds: ['sam'],
        locationIds: ['home', 'park'],
      ).describe({'sam': 'Sam'}, {'home': 'Home', 'park': 'The park'}),
      'With Sam · @ Home, The park',
    );
  });

  test('no locations, and nothing else, is empty', () {
    expect(const Facts().isEmpty, isTrue);
    expect(const Facts(locationIds: ['home']).isEmpty, isFalse);
    expect(
      const Facts(locationIds: ['home', 'park']),
      const Facts(locationIds: ['home', 'park']),
    );
    expect(
      const Facts(locationIds: ['home']) == const Facts(locationIds: ['park']),
      isFalse,
    );
  });
}
