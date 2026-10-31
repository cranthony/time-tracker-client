/// A link from a description into the app -- a goal's, a habit's note,
/// an event's -- to a goal, a habit, a person, a circle, an action or a
/// location, by id: `goal:ship-goals-pane`, `person:sam`. Written as any
/// link is, in Markdown (`[Sam](person:sam)`, or just `<person:sam>`) or
/// HTML (`<a href="person:sam">Sam</a>`), or bare in plain text
/// (`person:sam`). The app draws it with the icon of what it names and,
/// where its text is only the id (or there's none), its current name;
/// tapped, it opens what it names ([EntityLinks]).
library;

/// What a description can link to, by its id.
enum EntityKind {
  goal('Goal', 'goal'),
  habit('Habit', 'habit'),
  person('Person', 'person'),
  circle('Circle', 'circle'),
  action('Action', 'action'),
  location('Location', 'location');

  const EntityKind(this.label, this.noun);

  /// As a menu names it.
  final String label;

  /// As a sentence names one: "No goal ...".
  final String noun;

  static EntityKind? fromScheme(String scheme) =>
      values.where((k) => k.name == scheme.toLowerCase()).firstOrNull;
}

/// A link to [kind] [id]: `kind:id`.
class EntityLink {
  const EntityLink(this.kind, this.id);

  final EntityKind kind;
  final String id;

  /// As it's written: `goal:ship-goals-pane`.
  String get href => '${kind.name}:$id';

  /// [href] as a link into the app, or null for any other address --
  /// a web page, say. `goal://id` is read as `goal:id`.
  static EntityLink? parse(String href) {
    final colon = href.indexOf(':');
    if (colon <= 0) return null;
    final kind = EntityKind.fromScheme(href.substring(0, colon));
    if (kind == null) return null;
    var id = href.substring(colon + 1);
    if (id.startsWith('//')) id = id.substring(2);
    id = id.trim();
    return id.isEmpty ? null : EntityLink(kind, id);
  }

  /// A link written bare in plain text: its kind, a colon and an id --
  /// letters, digits, `_` and `-`, with dots inside -- at a word's
  /// start, so an address with one in its path isn't one.
  static final pattern = RegExp(
    r'\b(?:goal|habit|person|circle|action|location):'
    r'[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*',
    caseSensitive: false,
  );

  @override
  bool operator ==(Object other) =>
      other is EntityLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => href;
}
