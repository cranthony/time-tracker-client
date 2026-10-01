import 'package:flutter/material.dart';

/// Shows each of [properties] under [title]: its key, then its value as
/// [format] gives it, or "(none)" for null.
Future<void> showPropertiesDialog(
  BuildContext context, {
  required String title,
  required Map<String, Object?> properties,
  String Function(BuildContext context, String key, Object value)? format,
}) => showDialog(
  context: context,
  builder: (context) =>
      _PropertiesDialog(title: title, properties: properties, format: format),
);

class _PropertiesDialog extends StatelessWidget {
  const _PropertiesDialog({
    required this.title,
    required this.properties,
    this.format,
  });

  final String title;
  final Map<String, Object?> properties;
  final String Function(BuildContext context, String key, Object value)? format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(:key, :value) in properties.entries)
              PropertyRow(
                name: key,
                child: value == null
                    ? Text('(none)', style: TextStyle(color: theme.hintColor))
                    : SelectableText(
                        format?.call(context, key, value) ?? '$value',
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// One property in a properties dialog: its [name] in small primary-colored
/// type, any [marker] after it, then [child], its value.
class PropertyRow extends StatelessWidget {
  const PropertyRow({
    super.key,
    required this.name,
    required this.child,
    this.marker,
  });

  final String name;
  final Widget child;
  final Widget? marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (marker case final marker?) ...[
                const SizedBox(width: 6),
                marker,
              ],
            ],
          ),
          child,
        ],
      ),
    );
  }
}
