import 'package:flutter/material.dart';

import '../outbox/outbox.dart';
import '../outbox/write_queue.dart';
import 'write_conflict_dialog.dart';
import 'status_bar.dart';

/// An [Outbox]'s part of the [StatusBar], each item by [label] and the
/// lot as [things] -- "2 notes": whether they're being sent, waiting to
/// try again, waiting for a sign-in, or stopped at one the server
/// refused; and in the sheet, under [title], each with how it's going,
/// to try again or drop ([drop]). Nothing in the sheet with none waiting.
abstract class OutboxStatus<T extends OutboxItem<T>> implements StatusSource {
  OutboxStatus(this.outbox);

  final Outbox<T, Object?> outbox;

  /// What the sheet's part is headed.
  String get title;

  /// [n] of the items, as one would say it: "2 notes".
  String things(int n);

  /// [item], as one would name it: “Running”.
  String label(T item);

  /// Drops [item] without sending it; false if it's being sent.
  Future<bool> drop(T item);

  /// Sends [item] again, now, even if the server refused it.
  void retry(T item) => outbox.retryNow();

  /// What the button that [retry]s [item] says.
  String retryLabel(T item) => 'Try again';

  /// What that button does, in [context]: [retry], by default.
  Future<void> act(BuildContext context, T item) async => retry(item);

  @override
  Listenable get listenable => outbox;

  @override
  int get count => outbox.items.length;

  @override
  StatusLine? line(BuildContext context) {
    final items = outbox.items;
    if (items.isEmpty) return null;
    final them = things(items.length);
    final waiting = items.where((i) => i.nextAttemptAt != null);
    return switch (items.where((i) => i.refused).firstOrNull) {
      final refused? => StatusLine(
        icon: Icons.error_outline,
        text: "Couldn't save ${label(refused)}: tap to fix it",
        needsYou: true,
      ),
      _ when outbox.needsSignIn => StatusLine(
        icon: Icons.login,
        text: 'Sign in to save $them',
      ),
      _ when items.any(outbox.isSending) => StatusLine(
        icon: Icons.cloud_upload_outlined,
        text: 'Saving $them…',
      ),
      _ when waiting.isNotEmpty => StatusLine(
        icon: Icons.cloud_off_outlined,
        text:
            '$them waiting: trying again at '
            '${_at(context, waiting.map((i) => i.nextAttemptAt!).reduce((a, b) => a.isBefore(b) ? a : b))}',
      ),
      _ => StatusLine(
        icon: Icons.cloud_upload_outlined,
        text: '$them waiting to save',
      ),
    };
  }

  @override
  List<Widget> section(BuildContext context) {
    final items = outbox.items;
    if (items.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(title, style: theme.textTheme.titleLarge),
      ),
      for (final item in items) _tile(context, item),
    ];
  }

  Widget _tile(BuildContext context, T item) {
    final theme = Theme.of(context);
    final sending = outbox.isSending(item);
    final status = switch (item) {
      _ when sending => 'Sending, by ${outbox.sendingBy(item)}…',
      _ when item.refused =>
        "Couldn't save: ${_sentence(item.lastError ?? 'the server said no')}",
      _ when outbox.needsSignIn => 'Sign in to save it.',
      OutboxItem(:final nextAttemptAt?) =>
        "Couldn't send it${item.lastError == null ? '' : ' (${item.lastError})'}: "
            'trying again at ${_at(context, nextAttemptAt)}.',
      _ => 'Waiting to save.',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: item.refused ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: sending
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      item.refused
                          ? Icons.error_outline
                          : Icons.cloud_upload_outlined,
                    ),
              title: Text(label(item)),
              subtitle: Text(status),
            ),
            if (!sending)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (item.lastError != null && !outbox.needsSignIn)
                    TextButton(
                      onPressed: () => act(context, item),
                      child: Text(retryLabel(item)),
                    ),
                  TextButton(
                    onPressed: () async {
                      if (!await drop(item) && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "It's being sent: it can't be dropped.",
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Drop'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// [text], ending in a full stop.
String _sentence(String text) =>
    text.endsWith('.') || text.endsWith('!') || text.endsWith('?')
    ? text
    : '$text.';

String _at(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));

/// The [WriteQueue]'s part of the [StatusBar]: each write by what it
/// writes ("location “Home”"). One refused as changed elsewhere is
/// resolved field by field ([showWriteConflictDialog]).
class WriteQueueStatus extends OutboxStatus<PendingWrite> {
  WriteQueueStatus(WriteQueue super.outbox);

  WriteQueue get _writes => outbox as WriteQueue;

  @override
  String get title => 'Changes waiting to save';

  @override
  String things(int n) => n == 1 ? '1 change' : '$n changes';

  @override
  String label(PendingWrite item) {
    final what = _writes.label(item);
    return switch (item.op) {
      WriteOp.create => 'New $what',
      WriteOp.update => 'Changes to $what',
      WriteOp.delete => 'Deleting $what',
    };
  }

  @override
  String retryLabel(PendingWrite item) =>
      item.conflicted ? 'Resolve' : super.retryLabel(item);

  /// A conflict is resolved field by field ([showWriteConflictDialog]).
  @override
  Future<void> act(BuildContext context, PendingWrite item) async {
    if (!item.conflicted) return super.act(context, item);
    await showWriteConflictDialog(context, _writes, item);
  }

  @override
  Future<bool> drop(PendingWrite item) => _writes.drop(item);
}
