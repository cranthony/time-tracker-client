import '../models/goal.dart';

/// A change to the goals waiting to be sent to the server, or that failed:
/// a new goal, or changes to one.
class PendingGoalSave {
  const PendingGoalSave({
    required this.id,
    required this.goalId,
    required this.isNew,
    required this.changes,
    this.error,
    this.uncertain = false,
  });

  /// Local only; the server knows nothing about it.
  final String id;

  /// The goal it's for. For a new goal, the id it's shown with until the
  /// server makes it, which the server knows nothing about.
  final String goalId;

  /// Whether it makes a new goal, rather than changing one.
  final bool isNew;

  /// For a new goal, everything it's made with, keyed as `create_goal`
  /// takes them; else its changes, keyed as `update_goal` takes them, a
  /// null clearing that property.
  final Map<String, Object?> changes;

  /// Why it failed, if it did: it isn't sent again until it's retried.
  final String? error;

  /// Whether a request for it may have reached the server without an
  /// answer coming back (the connection dropped, or the app closed), so
  /// it may be saved already.
  final bool uncertain;

  /// The new goal it makes, shown as [goalId].
  Goal get goal =>
      Goal.fromJson({'status': 'active', ...changes, 'id': goalId});

  /// Whether [goals] has the new goal it makes. A name is only used once
  /// among siblings, so the same one under the same parent is it.
  bool madeIn(GoalList goals) => goals.goals.any(
    (g) => g.parentId == changes['parent_id'] && g.name == changes['name'],
  );

  PendingGoalSave copyWith({
    Map<String, Object?>? changes,
    String? Function()? error,
    bool? uncertain,
  }) => PendingGoalSave(
    id: id,
    goalId: goalId,
    isNew: isNew,
    changes: changes ?? this.changes,
    error: error == null ? this.error : error(),
    uncertain: uncertain ?? this.uncertain,
  );

  factory PendingGoalSave.fromJson(Map<String, dynamic> json) =>
      PendingGoalSave(
        id: json['id'] as String,
        goalId: json['goal_id'] as String,
        isNew: json['is_new'] as bool? ?? false,
        changes: (json['changes'] as Map).cast<String, Object?>(),
        error: json['error'] as String?,
        uncertain: json['uncertain'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal_id': goalId,
    'is_new': isNew,
    'changes': changes,
    'error': ?error,
    'uncertain': uncertain,
  };
}
