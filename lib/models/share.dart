import '../widgets/durations.dart';
import 'named.dart';

/// How much of an event one of the things it's tagged with -- a goal
/// ([GoalShare]) or an action ([ActionShare]) -- takes: [minutes] (a fixed
/// share), [percent] (of what the fixed shares leave), or neither -- a
/// part of the remaining time, what the minutes and percents leave. One
/// with minutes or percent can take a part of the remaining time too
/// ([plusRemaining]; "+r" as the server keeps it).
abstract class Share {
  const Share(this.id, {this.minutes, this.percent, bool remaining = false})
    : _alsoRemaining = remaining;

  final String id;
  final int? minutes;
  final int? percent;
  final bool _alsoRemaining;

  /// Whether it has neither minutes nor percent.
  bool get whole => minutes == null && percent == null;

  /// Whether it has minutes or percent and takes the remaining time too.
  bool get plusRemaining => !whole && _alsoRemaining;

  /// Whether it takes a part of the remaining time: one with neither
  /// always does.
  bool get remaining => whole || _alsoRemaining;

  /// What it takes, briefly: "45m", "30%", "45m + the rest", or "" for
  /// neither.
  String get label => switch ((minutes, percent)) {
    (final m?, _) => '${formatMinutes(m)}${plusRemaining ? _andRest : ''}',
    (null, final p?) => '$p%${plusRemaining ? _andRest : ''}',
    _ => '',
  };

  static const _andRest = ' + the rest';

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is Share &&
      other.id == id &&
      other.minutes == minutes &&
      other.percent == percent &&
      other.plusRemaining == plusRemaining;

  @override
  int get hashCode =>
      Object.hash(runtimeType, id, minutes, percent, plusRemaining);

  @override
  String toString() => '$runtimeType($id, $label)';
}

/// How the remaining time goes to the shares that take it: [all] gives
/// each all of it (goals: an hour toward two goals is an hour toward
/// each), [even] an even part (actions: an hour of two things is half an
/// hour of each).
enum RemainingSplit { all, even }

/// What's wrong with [shares] on an event [eventMinutes] long, as the
/// server checks them, [kind] naming what they're shares of ("goal");
/// empty if nothing is.
List<String> shareProblems(
  List<Share> shares,
  int eventMinutes, {
  String kind = 'goal',
}) {
  final problems = <String>[];
  var (minutes, percent) = (0, 0);
  final seen = <String>{};
  for (final s in shares) {
    if (!seen.add(s.id)) problems.add('A $kind is given twice.');
    if (s.minutes case final m?) {
      if (m <= 0) problems.add('Minutes must be more than 0.');
      minutes += m;
    } else if (s.percent case final p?) {
      if (p < 1 || p > 100) problems.add('A percent must be 1 to 100.');
      percent += p;
    }
  }
  if (minutes > eventMinutes) {
    problems.add(
      'The ${kind}s take ${formatMinutes(minutes)}, more than the event\'s '
      '${formatMinutes(eventMinutes)}.',
    );
  }
  if (percent > 100) {
    problems.add(
      'The ${kind}s\' percents add up to $percent%, more than 100%.',
    );
  }
  return problems;
}

/// [shares] of an event [length] long, taken apart: each one's [fixed]
/// part -- its minutes first, in order (cut down to fit), then its
/// percent of what they leave -- and the [remaining] time those leave,
/// which those that take it ([takers]) have a part of.
({Map<String, Duration> fixed, Duration remaining, Set<String> takers})
shareParts(List<Share> shares, Duration length) {
  final fixed = <String, Duration>{};
  final takers = <String>{};
  final seen = <String>{};
  final kept = [
    for (final s in shares)
      if (seen.add(s.id)) s,
  ];
  var left = length;
  for (final s in kept) {
    if (s.minutes case final m?) {
      final take = Duration(minutes: m) > left ? left : Duration(minutes: m);
      fixed[s.id] = take;
      left -= take;
    }
  }
  final rest = left;
  var percentLeft = 100;
  for (final s in kept) {
    if (s.minutes == null && s.percent != null) {
      final take = s.percent!.clamp(0, percentLeft);
      percentLeft -= take;
      final part = rest * take ~/ 100;
      fixed[s.id] = part;
      left -= part;
    }
  }
  for (final s in kept) {
    if (s.remaining) takers.add(s.id);
  }
  return (
    fixed: fixed,
    remaining: left < Duration.zero ? Duration.zero : left,
    takers: takers,
  );
}

/// How much of an event [length] long each of [shares] takes, by id: its
/// fixed part ([shareParts]), and if it takes the remaining time, its part
/// of that, as [split] says.
Map<String, Duration> shareTimes(
  List<Share> shares,
  Duration length, {
  RemainingSplit split = RemainingSplit.all,
}) {
  final (:fixed, :remaining, :takers) = shareParts(shares, length);
  final each = switch (split) {
    RemainingSplit.all => remaining,
    RemainingSplit.even =>
      takers.isEmpty ? Duration.zero : remaining ~/ takers.length,
  };
  return {
    ...fixed,
    for (final id in takers) id: (fixed[id] ?? Duration.zero) + each,
  };
}

/// [shareTimes] as fractions of the event, [length] long: none if it has
/// no length.
Map<String, double> shareFractions(
  List<Share> shares,
  Duration length, {
  RemainingSplit split = RemainingSplit.all,
}) {
  if (length <= Duration.zero) return const {};
  return {
    for (final MapEntry(key: id, value: time) in shareTimes(
      shares,
      length,
      split: split,
    ).entries)
      id: time.inMicroseconds / length.inMicroseconds,
  };
}

/// [shares] read from a list the server sent, each its bare id -- as ids
/// always were -- or an object with its id under [key] and its share;
/// [make] makes each. With [circles], an object with a `circle_id` makes a
/// [CircleShare] instead, with its except.
List<S> sharesFromJson<S extends Share>(
  Object? json,
  String key,
  S Function(String id, {int? minutes, int? percent, bool remaining}) make, {
  S Function(
    String id,
    List<String> except, {
    int? minutes,
    int? percent,
    bool remaining,
  })?
  circles,
}) => [
  for (final item in json as List? ?? const [])
    if (item is Map)
      if (_circleId(item, circles != null) case final String id)
        circles!(
          id,
          [for (final e in item['except'] as List? ?? const []) '$e'],
          minutes: (item['minutes'] as num?)?.toInt(),
          percent: (item['percent'] as num?)?.toInt(),
          remaining: item['remaining'] == true,
        )
      else if (item[key] case final String id when id.isNotEmpty)
        make(
          id,
          minutes: (item['minutes'] as num?)?.toInt(),
          percent: (item['percent'] as num?)?.toInt(),
          remaining: item['remaining'] == true,
        )
      else
        ...const []
    else if (item != null)
      make('$item'),
];

/// [item]'s `circle_id`, if [circles] are read and it has one.
String? _circleId(Map item, bool circles) => switch (item['circle_id']) {
  final String id when circles && id.isNotEmpty => id,
  _ => null,
};

/// [share] as the server takes it, its id under [key]: its bare id with
/// neither minutes nor percent, so a list without shares is sent as
/// before.
Object shareToJson(Share share, String key) => share.whole
    ? share.id
    : {
        key: share.id,
        'minutes': ?share.minutes,
        'percent': ?share.percent,
        if (share.plusRemaining) 'remaining': true,
      };

/// [fractions] scaled down together if they add up to more than 1, so
/// they split an event no more than whole -- for a summary that adds up
/// to its span.
Map<String, double> scaledDown(Map<String, double> fractions) {
  final sum = fractions.values.fold(0.0, (a, b) => a + b);
  if (sum <= 1) return fractions;
  return {
    for (final MapEntry(key: id, value: f) in fractions.entries) id: f / sum,
  };
}

/// One action an event is of, and how much of the event it takes (see
/// [Share]): with neither minutes nor percent, an even part of the
/// remaining time, with the others that take it. The server sends one
/// with neither as its bare id, as it sent every action before shares.
class ActionShare extends Share {
  const ActionShare(super.id, {super.minutes, super.percent, super.remaining});

  String get actionId => id;

  static ActionShare? fromJson(Object? json) =>
      sharesFromJson([json], 'action_id', ActionShare.new).firstOrNull;

  /// As the server takes it (see [shareToJson]).
  Object toJson() => shareToJson(this, 'action_id');
}

/// Someone an event was with or for -- a person ([PersonShare]) or a
/// circle ([CircleShare]) -- and how much of it they take (see [Share]):
/// with neither minutes nor percent, the remaining time -- all of it, as
/// everyone else given neither takes it too. A plain circle's members
/// each take the circle's part, as a person.
sealed class WhoShare extends Share {
  const WhoShare(super.id, {super.minutes, super.percent, super.remaining});

  /// Whether it's sent as its bare id: a person's with neither minutes nor
  /// percent. A circle's is always an object, so the server knows it as a
  /// circle's.
  bool get bare;

  /// Whom it names: a circle's, with its except.
  Named get named;

  /// These, naming [named] -- the same person or circle, with its except
  /// as given.
  WhoShare withNamed(Named named);

  Object toJson();
}

/// A person an event was with or for, and how much of it they take (see
/// [WhoShare]). The server sends one with neither minutes nor percent as
/// its bare id, as it sent everyone before shares -- a circle's id given
/// bare reads so too.
class PersonShare extends WhoShare {
  const PersonShare(super.id, {super.minutes, super.percent, super.remaining});

  String get personId => id;

  @override
  bool get bare => whole;

  @override
  Named get named => Named(id);

  @override
  WhoShare withNamed(Named named) => named.except.isEmpty
      ? PersonShare(
          named.id,
          minutes: minutes,
          percent: percent,
          remaining: plusRemaining,
        )
      : CircleShare(
          named.id,
          except: named.except,
          minutes: minutes,
          percent: percent,
          remaining: plusRemaining,
        );

  @override
  Object toJson() => shareToJson(this, 'person_id');
}

/// A circle an event was with or for, given as one (`{circle_id, except?,
/// minutes?, percent?, remaining?}`): a plain circle's members but those
/// in [except] each take its part; a community takes it itself, and takes
/// no except.
class CircleShare extends WhoShare {
  const CircleShare(
    super.id, {
    this.except = const [],
    super.minutes,
    super.percent,
    super.remaining,
  });

  String get circleId => id;

  /// Of a plain circle's members, who weren't, by person id.
  final List<String> except;

  @override
  bool get bare => false;

  @override
  Named get named => Named(id, except: except);

  @override
  WhoShare withNamed(Named named) => CircleShare(
    named.id,
    except: named.except,
    minutes: minutes,
    percent: percent,
    remaining: plusRemaining,
  );

  @override
  Object toJson() => {
    'circle_id': id,
    if (except.isNotEmpty) 'except': except,
    'minutes': ?minutes,
    'percent': ?percent,
    if (plusRemaining) 'remaining': true,
  };

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is CircleShare &&
      other.except.length == except.length &&
      [for (var i = 0; i < except.length; i++) other.except[i] == except[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(super.hashCode, Object.hashAll(except));

  @override
  String toString() => 'CircleShare($id, except: $except, $label)';
}

/// [shares] of who an event was with or for, as the server sends them:
/// each a bare id, `{person_id, ...}` or `{circle_id, except?, ...}`.
List<WhoShare> whoSharesFromJson(Object? json) => sharesFromJson<WhoShare>(
  json,
  'person_id',
  PersonShare.new,
  circles: (id, except, {int? minutes, int? percent, bool remaining = false}) =>
      CircleShare(
        id,
        except: except,
        minutes: minutes,
        percent: percent,
        remaining: remaining,
      ),
);

/// A place an event was at, and how much of it it takes (see [Share]):
/// with neither minutes nor percent, an even part of the remaining time,
/// with the other places that take it.
class LocationShare extends Share {
  const LocationShare(
    super.id, {
    super.minutes,
    super.percent,
    super.remaining,
  });

  String get locationId => id;

  Object toJson() => shareToJson(this, 'location_id');
}
