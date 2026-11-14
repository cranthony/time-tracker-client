import 'package:xml/xml.dart';

import 'facts.dart' show judgmentsFromJson;
import 'person.dart' show selfPersonId;
import 'trait.dart';

/// The longest a trait's icon can be, in characters, as the server allows.
const traitIconMaxLength = 8192;

/// The paints an icon's fills and strokes can have: it's drawn in one
/// colour, the one it's shown in.
const _paints = {'currentcolor', 'none'};

/// Elements an icon can't have, as the server refuses them: scripts,
/// other documents, pictures, styles, links and animations.
const _forbidden = {
  'script',
  'foreignobject',
  'image',
  'style',
  'a',
  'animate',
  'animatemotion',
  'animatetransform',
  'animatecolor',
  'set',
  'discard',
};

bool _isPaint(String value) => _paints.contains(
  value.trim().replaceFirst(RegExp(r'!important$'), '').trim().toLowerCase(),
);

/// The first `url(...)` in [value] that doesn't point within the icon
/// (`url(#...)`), if there's one.
String? _outsideUrl(String value) =>
    RegExp(r'''url\(\s*['"]?([^)]*)\)''', caseSensitive: false)
        .allMatches(value)
        .where((m) => !m.group(1)!.startsWith('#'))
        .firstOrNull
        ?.group(0);

/// What's wrong with [svg] as a trait's icon, as the server would refuse
/// it, or null if it's fine: at most [traitIconMaxLength] characters, an
/// `<svg>` root with a `viewBox`, every fill and stroke `currentColor` or
/// `none`, and nothing that could run or load anything -- no scripts,
/// styles, pictures, links or animations, no event handlers, and no
/// links or `url()`s outside itself.
String? traitIconProblem(String svg) {
  if (svg.length > traitIconMaxLength) {
    return 'An icon can be at most $traitIconMaxLength characters; this one '
        'is ${svg.length}.';
  }
  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlException catch (e) {
    return "That isn't SVG the app can read: ${e.message}";
  }
  final root = document.rootElement;
  if (root.name.local != 'svg') {
    return 'An icon must be an <svg> element, not <${root.name.local}>.';
  }
  if (root.getAttribute('viewBox') == null) {
    return 'An icon needs a viewBox on its <svg>, to scale it.';
  }
  for (final element in [root, ...root.descendantElements]) {
    final name = element.name.local;
    if (_forbidden.contains(name.toLowerCase())) {
      return "An icon can't have <$name>: no scripts, foreign objects, "
          'images, styles, links or animations.';
    }
    for (final attribute in element.attributes) {
      final (property, value) = (attribute.name.local, attribute.value);
      if (property.toLowerCase().startsWith('on')) {
        return "An icon can't have the event handler $property (on <$name>).";
      }
      if (property == 'href' && !value.trimLeft().startsWith('#')) {
        return "An icon can only link within itself: <$name>'s href is "
            '"$value".';
      }
      if (_outsideUrl(value) case final url?) {
        return "An icon can only use url(#...), within itself: <$name>'s "
            '$property has "$url".';
      }
    }
    for (final (property, value) in _paintsOf(element)) {
      if (!_isPaint(value)) {
        return "An icon is drawn in one colour: its <$name>'s $property "
            'is "$value", not currentColor or none.';
      }
    }
  }
  return null;
}

/// [svg] made fit to be a trait's icon, where it can be: without its XML
/// declaration, doctype and comments, or anything that could run or load
/// anything ([traitIconProblem]), and with each fill and stroke in a
/// colour drawn in `currentColor` instead -- one colour, the one it's
/// shown in. Whether it's then fine is for [traitIconProblem] to say; if
/// it can't be read, it's returned as it was.
String asTraitIcon(String svg) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } on XmlException {
    return svg;
  }
  for (final node in [...document.children]) {
    if (node is XmlDeclaration ||
        node is XmlDoctype ||
        node is XmlComment ||
        node is XmlProcessing) {
      node.remove();
    }
  }
  for (final comment in [...document.descendants.whereType<XmlComment>()]) {
    comment.remove();
  }
  final root = document.rootElement;
  for (final element in [...root.descendantElements]) {
    if (_forbidden.contains(element.name.local.toLowerCase())) {
      element.remove();
    }
  }
  for (final element in [root, ...root.descendantElements]) {
    element.attributes.removeWhere(
      (a) =>
          a.name.local.toLowerCase().startsWith('on') ||
          (a.name.local == 'href' && !a.value.trimLeft().startsWith('#')),
    );
    for (final property in const ['fill', 'stroke']) {
      if (element.getAttribute(property) case final value?
          when !_isPaint(value)) {
        element.setAttribute(property, 'currentColor');
      }
    }
    if (element.getAttribute('style') case final style?) {
      element.setAttribute('style', _recolouredStyle(style));
    }
    element.attributes.removeWhere((a) => _outsideUrl(a.value) != null);
  }
  return document.rootElement.toXmlString().trim();
}

/// Each fill and stroke [element] sets, as attributes and in its style:
/// (property, value).
Iterable<(String, String)> _paintsOf(XmlElement element) sync* {
  for (final property in const ['fill', 'stroke']) {
    if (element.getAttribute(property) case final value?) {
      yield (property, value);
    }
  }
  if (element.getAttribute('style') case final style?) {
    for (final (property, value) in _declarations(style)) {
      if (property == 'fill' || property == 'stroke') yield (property, value);
    }
  }
}

/// A style attribute's declarations: (property, value), the property in
/// lowercase.
Iterable<(String, String)> _declarations(String style) sync* {
  for (final declaration in style.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon < 0) continue;
    yield (
      declaration.substring(0, colon).trim().toLowerCase(),
      declaration.substring(colon + 1).trim(),
    );
  }
}

String _recolouredStyle(String style) => [
  for (final (property, value) in _declarations(style))
    (property == 'fill' || property == 'stroke') && !_isPaint(value)
        ? '$property:currentColor'
        : '$property:$value',
].join(';');

/// Whether [svg] can be drawn as an icon: it reads as XML, its root an
/// `<svg>`. Asked often, of the same few icons, so the answers are kept.
bool traitIconDrawable(String svg) => _drawable[svg] ??= () {
  if (_drawable.length > 200) _drawable.clear();
  try {
    return XmlDocument.parse(svg).rootElement.name.local == 'svg';
  } on XmlException {
    return false;
  }
}();

final _drawable = <String, bool>{};

/// The traits an event marks, by id, in [traits]' order: each that a
/// judgment of the user on it gave its top rating -- the highest its
/// scale allowed, on any of its parts -- from the event's [judgments]
/// (as it keeps them), and each a story of it is linked to the event by
/// ([storyTraitIds]). Only those with an icon to show are worth marking,
/// so only those in [traits] are listed.
List<Trait> markedTraits(
  List<Trait> traits, {
  Object? judgments,
  Iterable<String> storyTraitIds = const [],
}) {
  final marked = {
    ...storyTraitIds,
    for (final j in judgmentsFromJson(judgments))
      if (j.personId == selfPersonId &&
          (j.scale ?? 0) > 0 &&
          j.rating >= j.scale!)
        j.traitId,
  };
  if (marked.isEmpty) return const [];
  return [
    for (final t in traits)
      if (marked.contains(t.id)) t,
  ];
}
