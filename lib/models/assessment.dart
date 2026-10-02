/// One health rating of one goal for one period of its cadence, mirroring
/// the Time Tracker MCP server's `Assessment`.
class Assessment {
  const Assessment({
    required this.goalId,
    required this.period,
    this.cadence,
    this.rating,
    this.method,
    this.status = 'confirmed',
    this.explanation,
    this.rationale,
  });

  final String goalId;

  /// e.g. "2026-09-30", "week-2026-09-27", "2026-09", "2026-09..10".
  final String period;
  final String? cadence;

  /// 0-100; null for a period deliberately skipped.
  final int? rating;

  /// metric, subjective, llm or rollup.
  final String? method;

  /// proposed until a reflection confirms it.
  final String status;

  /// How a measured rating was reached, in a line.
  final String? explanation;

  /// What was said about it.
  final String? rationale;

  bool get skipped => rating == null;
  bool get confirmed => status == 'confirmed';

  factory Assessment.fromJson(Map<String, dynamic> json) => Assessment(
    goalId: json['goal_id'] as String,
    period: json['period'] as String,
    cadence: json['cadence'] as String?,
    rating: json['rating'] is int ? json['rating'] as int : null,
    method: json['method'] as String?,
    status: json['status'] as String? ?? 'proposed',
    explanation: json['explanation'] as String?,
    rationale: json['rationale'] as String?,
  );
}
