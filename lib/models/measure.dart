import 'goal.dart';

/// How a goal's health is rated each period of its cadence, mirroring the
/// MCP server's measure specs (its utilities/goal_measures.py): a JSON
/// object with a "kind" and that kind's fields.
///
/// | kind         | fields                                                 |
/// | ------------ | ------------------------------------------------------ |
/// | `duration`   | `target_min`: minutes per period                       |
/// | `count`      | `target`: events per period; optional `noun`           |
/// | `wake_time`  | `target` "HH:MM"; optional `grace_min`, `zero_at_min`  |
/// | `subjective` | optional `prompt`, asked in a reflection               |
/// | `llm`        | `rubric` Claude rates the period against               |
/// | `rollup`     | optional `agg`: "min" (default) or "mean"              |
typedef Measure = Map<String, Object?>;

/// The kinds of measure, as the server names them, and as the app shows
/// them.
const measureKinds = {
  'duration': 'Time spent',
  'count': 'Number of events',
  'wake_time': 'Wake-up time',
  'subjective': 'Your rating',
  'llm': "Claude's judgement",
  'rollup': 'From sub-goals',
};

/// What each kind of measure rates, said under its picker.
const measureKindHints = {
  'duration':
      "The time spent on its events (and its sub-goals') each "
      'period, against a target.',
  'count':
      "How many of its events (and its sub-goals') there are each "
      'period, against a target.',
  'wake_time':
      'When you got up: full marks within the grace, falling to '
      'none at "zero at" minutes late. Averaged over the period.',
  'subjective': 'You rate it yourself in each reflection.',
  'llm':
      'Claude rates the period against your rubric, reading its events '
      'and notes, for you to confirm in a reflection.',
  'rollup': 'The lowest, or the average, of its sub-goals\' ratings.',
};

/// Whole numbers as ints, so 600.0 and 600 compare equal.
num _tidy(num n) => n == n.roundToDouble() ? n.round() : n;

num? _number(Object? value) => value is num ? _tidy(value) : null;

/// Its cadence's period, as in "10h per week".
String perPeriod(String? cadence) => switch (cadence) {
  'daily' => 'per day',
  'weekly' => 'per week',
  'monthly' => 'per month',
  'every_2_months' => 'per 2 months',
  _ => 'per period',
};

/// ", weekly", or nothing without a cadence.
String _rated(String? cadence) => switch (cadences[cadence]) {
  final name? => ', ${name.toLowerCase()}',
  null => '',
};

/// [minutes] as "10h", "45m" or "1h 30m".
String formatMinutes(num minutes) {
  final total = minutes.round();
  final (hours, rest) = (total ~/ 60, total % 60);
  if (hours == 0) return '${rest}m';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

/// A line saying what [measure] rates, at [cadence]: "10h per week",
/// "1 dinner per week", "Up by 07:00, daily". With [full], a wake-up
/// time's grace is said too, and a subjective measure's prompt and an llm
/// one's rubric follow on lines of their own.
String describeMeasure(Measure measure, String? cadence, {bool full = false}) {
  final kind = measure['kind'];
  switch (kind) {
    case 'duration':
      final target = _number(measure['target_min']);
      return target == null
          ? 'Time spent${_rated(cadence)}'
          : '${formatMinutes(target)} ${perPeriod(cadence)}';
    case 'count':
      final target = _number(measure['target']);
      final noun = switch (measure['noun']) {
        final String noun when noun.trim().isNotEmpty => noun.trim(),
        _ => 'events',
      };
      if (target == null) return 'Number of $noun${_rated(cadence)}';
      // "1 dinner", not "1 dinners".
      final shown = target == 1 && noun.endsWith('s') && noun.length > 1
          ? noun.substring(0, noun.length - 1)
          : noun;
      return '$target $shown ${perPeriod(cadence)}';
    case 'wake_time':
      final grace = _number(measure['grace_min']) ?? 0;
      return 'Up by ${measure['target'] ?? '?'}'
          '${full && grace > 0 ? ' ($grace min grace)' : ''}'
          '${_rated(cadence)}';
    case 'subjective':
      final prompt = measure['prompt'];
      return 'Your rating${_rated(cadence)}'
          '${full && prompt is String ? '\n“$prompt”' : ''}';
    case 'llm':
      final rubric = measure['rubric'];
      return "Claude's judgement${_rated(cadence)}"
          '${full && rubric is String ? '\n$rubric' : ''}';
    case 'rollup':
      return '${measure['agg'] == 'mean' ? 'Average' : 'Lowest'} sub-goal '
          'rating${_rated(cadence)}';
    default:
      return '$measure';
  }
}

/// What's wrong with [measure], in a sentence, or null if it's fine: the
/// checks the server makes, so the editor can say so before saving.
String? measureProblem(Measure measure) {
  bool positive(Object? n) => n is num && n > 0;
  bool text(Object? s) => s is String && s.trim().isNotEmpty;
  switch (measure['kind']) {
    case 'duration':
      if (!positive(measure['target_min'])) {
        return 'Enter a target time, like 10h or 1h 30m.';
      }
    case 'count':
      if (!positive(measure['target'])) return 'Enter a target above 0.';
      if (measure.containsKey('noun') && !text(measure['noun'])) {
        return "Leave what's counted empty, or name it.";
      }
    case 'wake_time':
      final target = measure['target'];
      if (target is! String ||
          !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(target)) {
        return 'Pick a target time.';
      }
      final grace = measure['grace_min'] ?? 0;
      if (grace is! num || grace < 0) {
        return 'The grace must be 0 minutes or more.';
      }
      final zeroAt = measure['zero_at_min'];
      if (zeroAt != null && (zeroAt is! num || zeroAt <= grace)) {
        return '"Zero at" must be more minutes late than the grace.';
      }
    case 'subjective':
      if (measure.containsKey('prompt') && !text(measure['prompt'])) {
        return 'Leave the question empty, or ask one.';
      }
    case 'llm':
      if (!text(measure['rubric'])) {
        return 'Say what Claude should rate the period against.';
      }
    case 'rollup':
      if (measure.containsKey('agg') &&
          measure['agg'] != 'min' &&
          measure['agg'] != 'mean') {
        return 'Pick lowest or average.';
      }
    default:
      return 'Pick a kind of measure.';
  }
  return null;
}
