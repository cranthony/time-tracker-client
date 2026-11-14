import 'proposal.dart' show DecidedBy;
import 'trait_example.dart';

/// A story of a trait done well that a compaction proposal adds when it's
/// confirmed, mirroring an item of `get_proposal`'s `trait_examples`:
/// Claude's, with the user's changes over it, or the user's own. Its
/// [example]'s event, if it has one, is the proposal's: an event's id, or
/// a key of one it creates.
class ProposedStory {
  const ProposedStory({
    required this.example,
    this.traitName,
    this.personName,
    this.decidedBy = DecidedBy.claude,
  });

  /// As it'll be made; its id is how the proposal tracks it.
  final TraitExample example;

  /// Its trait's and person's names, as the server gives them.
  final String? traitName;
  final String? personName;
  final DecidedBy decidedBy;

  String get id => example.id ?? '';

  static ProposedStory? fromJson(Map<String, Object?> json) {
    if (json['id'] is! String) return null;
    return ProposedStory(
      example: TraitExample.fromJson(json),
      traitName: json['trait_name'] as String?,
      personName: json['person_name'] as String?,
      decidedBy: json['decided_by'] == 'user'
          ? DecidedBy.user
          : DecidedBy.claude,
    );
  }

  /// As `get_proposal` gives it.
  Map<String, Object?> toJson() => {
    ...example.toJson(),
    'trait_name': ?traitName,
    'person_name': ?personName,
    'decided_by': decidedBy.name,
  };
}

/// What the user can do with a proposed story in review: drop it, or
/// change it -- their fields over Claude's.
enum StoryEditUse {
  drop,
  change;

  static StoryEditUse? parse(Object? use) => switch (use) {
    'drop' => drop,
    'change' => change,
    _ => null,
  };
}

/// The user's say on one of a proposal's stories, as `amend_proposal`'s
/// `trait_examples` take it, and as `settled_trait_examples` keep it:
/// dropped, or changed -- [fields] (keyed as a trait example's) laid over
/// it, and [cleared] blanked. A change of an id the proposal doesn't have
/// adds one of the user's own, which needs every field.
class StoryEdit {
  const StoryEdit({
    required this.id,
    required this.use,
    this.fields = const {},
    this.cleared = const [],
  });

  final String id;
  final StoryEditUse use;
  final Map<String, Object?> fields;
  final List<String> cleared;

  /// [changes] ([TraitExample.changesFrom]) to the story [id], as an edit:
  /// a field changed to null is cleared.
  factory StoryEdit.change(String id, Map<String, Object?> changes) =>
      StoryEdit(
        id: id,
        use: StoryEditUse.change,
        fields: {
          for (final MapEntry(:key, :value) in changes.entries) key: ?value,
        },
        cleared: [
          for (final MapEntry(:key, :value) in changes.entries)
            if (value == null && clearableExampleFields.contains(key)) key,
        ],
      );

  static StoryEdit? fromJson(Map<String, Object?> json) {
    final use = StoryEditUse.parse(json['use']);
    if (use == null || json['id'] is! String) return null;
    return StoryEdit(
      id: json['id'] as String,
      use: use,
      fields: {for (final key in _fields) key: ?json[key]},
      cleared: [for (final c in json['clear_fields'] as List? ?? []) '$c'],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'use': use.name,
    if (use == StoryEditUse.change) ...fields,
    if (use == StoryEditUse.change && cleared.isNotEmpty)
      'clear_fields': cleared,
  };

  /// [story] as this leaves it: null if it's dropped; else its fields
  /// laid over [story]'s -- or, with none, the user's own -- as the
  /// user's. Null too for a new one missing what a story needs.
  ProposedStory? applyTo(ProposedStory? story) {
    if (use == StoryEditUse.drop) return null;
    final json = {
      ...?story?.example.toJson(),
      'id': id,
      ...fields,
      for (final c in cleared) c: null,
    };
    if (story == null &&
        traitExampleProblem(TraitExample.fromJson(json)) != null) {
      return null;
    }
    return ProposedStory(
      example: TraitExample.fromJson(json),
      // Named again, by the server, once it's saved.
      traitName: fields.containsKey('trait_id') ? null : story?.traitName,
      personName:
          fields.containsKey('person_id') || cleared.contains('person_id')
          ? null
          : story?.personName,
      decidedBy: DecidedBy.user,
    );
  }

  static const _fields = [
    'trait_id',
    'when',
    'person_id',
    'who',
    'what',
    'why',
    'event_id',
  ];
}

/// [stories] and those [settled], once [edits] settle them, as the
/// server does: one dropped leaves; one changed is the user's, its
/// fields over Claude's -- or added, for an id there isn't.
(List<ProposedStory>, List<StoryEdit>) settleStories(
  List<ProposedStory> stories,
  List<StoryEdit> settled,
  List<StoryEdit> edits,
) {
  final pending = [...stories];
  final kept = [...settled];
  for (final edit in edits) {
    final i = pending.indexWhere((s) => s.id == edit.id);
    final now = edit.applyTo(i < 0 ? null : pending[i]);
    if (i >= 0) pending.removeAt(i);
    if (now != null) pending.insert(i < 0 ? pending.length : i, now);
    kept
      ..removeWhere((s) => s.id == edit.id)
      ..add(edit);
  }
  return (pending, kept);
}
