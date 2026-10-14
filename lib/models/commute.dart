import 'person.dart';
import 'plan_action.dart';
import 'travel_time.dart';

/// A way of getting from one place to another that the travel times have
/// a time for: by [action], taking [minutes] ([commuteMinutes] of the
/// [time] it's given), as [travel] says.
typedef CommuteOption = ({
  PlanAction action,
  int minutes,
  TravelMode time,
  TravelTime travel,
});

/// How long a commute by [time] is taken to be: its minutes, or the middle
/// of its range, rounded up to five minutes.
int commuteMinutes(TravelMode time) => switch (time.maxMinutes) {
  final max? when max > time.minutes =>
    ((time.minutes + max) / 2 / 5).ceil() * 5,
  _ => time.minutes,
};

/// [id] -- a location or a location group -- and the groups it's in,
/// nearest first; empty if it's neither.
List<String> placesAround(
  String id,
  List<Location> locations,
  List<LocationGroup> groups,
) {
  final String? groupId;
  if (locations.where((l) => l.id == id).firstOrNull case final location?) {
    groupId = location.groupId;
  } else if (groups.where((g) => g.id == id).firstOrNull case final group?) {
    groupId = group.groupId;
  } else {
    return const [];
  }
  return [
    id,
    for (final g in enclosingGroupIds(groupId, groups))
      if (g != id) g,
  ];
}

/// [actionId] and the action groups it's in, nearest first.
List<String> modesAround(String actionId, Map<String, PlanAction> actions) {
  final out = <String>[];
  String? next = actionId;
  while (next != null && !out.contains(next)) {
    out.add(next);
    next = actions[next]?.parentId;
  }
  return out;
}

/// How long it takes from [fromId] to [toId] by one of [modeIds] (a mode
/// and the groups it's in, nearest first), as the server's
/// `estimate_travel_time` works it out: the travel time between the
/// places, or else between the groups they're in -- fewest steps out
/// first, then the most even, so it's the same either way round -- a
/// one-way one before a two-way one between the same places, and the
/// nearest mode that has a time. Null if no travel time says.
({TravelTime travel, TravelMode time})? estimateTravel({
  required String fromId,
  required String toId,
  required List<String> modeIds,
  required List<TravelTime> travelTimes,
  required List<Location> locations,
  required List<LocationGroup> groups,
}) {
  final from = placesAround(fromId, locations, groups);
  final to = placesAround(toId, locations, groups);
  final pairs = [
    for (var i = 0; i < from.length; i++)
      for (var j = 0; j < to.length; j++) (i, j),
  ];
  int order((int, int) p) => p.$1 + p.$2;
  int even((int, int) p) => p.$1 > p.$2 ? p.$1 : p.$2;
  pairs.sort(
    (a, b) => order(a) != order(b)
        ? order(a) - order(b)
        : even(a) != even(b)
        ? even(a) - even(b)
        : a.$1 - b.$1,
  );
  for (final (i, j) in pairs) {
    final (a, b) = (from[i], to[j]);
    final found = [
      for (final t in travelTimes)
        if (t.oneWay && t.fromId == a && t.toId == b) t,
      for (final t in travelTimes)
        if (!t.oneWay &&
            ((t.fromId == a && t.toId == b) || (t.fromId == b && t.toId == a)))
          t,
    ];
    for (final mode in modeIds) {
      for (final travel in found) {
        if (travel.times.where((t) => t.modeId == mode).firstOrNull
            case final time?) {
          return (travel: travel, time: time);
        }
      }
    }
  }
  return null;
}

/// Every action -- not a group, and in use -- the travel times have a
/// time for getting from [fromId] to [toId] by, quickest first.
List<CommuteOption> commuteOptions({
  required String fromId,
  required String toId,
  required List<PlanAction> actions,
  required List<TravelTime> travelTimes,
  required List<Location> locations,
  required List<LocationGroup> groups,
}) {
  if (fromId == toId || travelTimes.isEmpty) return const [];
  final byId = {for (final a in actions) ?a.id: a};
  final options = <CommuteOption>[];
  for (final action in actions) {
    if (action.id == null || action.isGroup || !action.active) continue;
    final found = estimateTravel(
      fromId: fromId,
      toId: toId,
      modeIds: modesAround(action.id!, byId),
      travelTimes: travelTimes,
      locations: locations,
      groups: groups,
    );
    if (found == null) continue;
    options.add((
      action: action,
      minutes: commuteMinutes(found.time),
      time: found.time,
      travel: found.travel,
    ));
  }
  options.sort((a, b) => a.minutes - b.minutes);
  return options;
}
