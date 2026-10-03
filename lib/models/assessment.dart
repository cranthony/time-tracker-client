/// One health rating of one goal for one day, mirroring the Time Tracker
/// MCP server's `Assessment`.
class Assessment {
  const Assessment({
    required this.goalId,
    required this.day,
    this.rating,
    this.method,
    this.status = 'confirmed',
    this.explanation,
    this.rationale,
  });

  final String goalId;

  /// The day rated, e.g. "2026-09-30".
  final String day;

  /// 0-100; null for a day deliberately skipped.
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
    // "period" from a server from before goals were only rated daily.
    day: (json['day'] ?? json['period']) as String,
    rating: json['rating'] is int ? json['rating'] as int : null,
    method: json['method'] as String?,
    status: json['status'] as String? ?? 'proposed',
    explanation: json['explanation'] as String?,
    rationale: json['rationale'] as String?,
  );
}
