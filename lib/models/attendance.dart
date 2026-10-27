import 'event.dart';
import 'facts.dart';
import 'named.dart';
import 'person.dart';
import 'share.dart';

/// Who an event is with or for, or a goal, once the circles its facts
/// name are stood for -- as the server stands for them (its
/// attendees.rs): a person is themself; a plain circle is its current
/// members, as [circles] list them, but those its except leaves out, and
/// never the user ([selfPersonId]); a community is itself, its members
/// never assumed. One of these answers for everything that derives a
/// person's events from facts: scoring, their history, their time
/// together.
class Attendance {
  Attendance({Iterable<Circle> circles = const []})
    : _circles = {for (final c in circles) c.id: c};

  /// No circles known: everyone named is a person.
  static final none = Attendance();

  final Map<String, Circle> _circles;

  /// The circle [id] names, if it's one.
  Circle? circle(String id) => _circles[id];

  /// Whether [id] is a plain circle's: one that stands for its members.
  bool isPlainCircle(String id) => switch (_circles[id]) {
    final c? => !c.isCommunity,
    null => false,
  };

  /// The ids of the plain circles [personId] is in: those that stand for
  /// them.
  List<String> plainCirclesOf(String personId) => [
    for (final c in _circles.values)
      if (!c.isCommunity && c.memberIds.contains(personId)) c.id,
  ];

  /// Whom [named] stands for: a person, themself; a plain circle, its
  /// members but its except and the user; a community, itself.
  Iterable<String> standsFor(Named named) sync* {
    final circle = _circles[named.id];
    if (circle == null || circle.isCommunity) {
      yield named.id;
      return;
    }
    for (final id in circle.memberIds) {
      if (id != selfPersonId && !named.except.contains(id)) yield id;
    }
  }

  /// Everyone [named] stand for, each once, in order: people and
  /// communities by id.
  List<String> peopleOf(Iterable<Named> named) =>
      {for (final n in named) ...standsFor(n)}.toList();

  /// Whether [named] stand for [id]: a person or circle named itself, or
  /// a person by a plain circle they're in that doesn't leave them out.
  bool includes(Iterable<Named> named, String id) =>
      named.any((n) => n.id == id || standsFor(n).contains(id));

  /// Who [facts] say was there with the user, stood for: never the user.
  List<String> withAt(Facts? facts) => peopleOf(facts?.withWhom ?? const []);

  /// Who [facts] say it was done for, stood for.
  List<String> forAt(Facts? facts) => peopleOf(facts?.forWhom ?? const []);

  /// Whether [facts] name [id] with or for, once circles are stood for.
  bool involves(Facts? facts, String id) =>
      facts != null &&
      (includes(facts.withWhom, id) || includes(facts.forWhom, id));

  /// Whether [facts] say [id] was there, once circles are stood for.
  bool isWith(Facts? facts, String id) =>
      facts != null && includes(facts.withWhom, id);

  /// Whether [facts] say it was done for [id], once circles are stood for.
  bool isFor(Facts? facts, String id) =>
      facts != null && includes(facts.forWhom, id);

  /// The fraction of an event [length] long each of [shares] takes, by
  /// id, as [shareFractions] has it -- each person a plain circle stands
  /// for taking the circle's part, unless they have one of their own.
  Map<String, double> fractions(List<WhoShare> shares, Duration length) {
    final byId = shareFractions(shares, length);
    final out = <String, double>{};
    for (final share in shares) {
      final fraction = byId[share.id];
      if (fraction == null) continue;
      for (final id in standsFor(share.named)) {
        // A person given their own share keeps it.
        if (byId.containsKey(id) && id != share.id) continue;
        out[id] = fraction;
      }
    }
    return out;
  }

  /// [Event.withFractions], with the circles stood for.
  Map<String, double> withFractions(Event event) => fractions(
    event.facts?.withShares ?? const [],
    event.end.difference(event.start),
  );

  /// [Event.forFractions], with the circles stood for.
  Map<String, double> forFractions(Event event) => fractions(
    event.facts?.forShares ?? const [],
    event.end.difference(event.start),
  );
}
