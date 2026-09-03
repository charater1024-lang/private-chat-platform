import 'package:flutter/material.dart';

import 'chat_ui_copy.dart';

/// A text message bubble with an optional delivery or policy annotation.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.text,
    required this.timeLabel,
    required this.isMine,
    this.author,
    this.annotation,
    super.key,
  });

  final String text;
  final String timeLabel;
  final bool isMine;
  final String? author;
  final String? annotation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final copy = ChatUiCopy.of(context);
    return Semantics(
      excludeSemantics: true,
      label:
          '${author ?? (isMine ? copy.ownMessage : copy.message)}: '
          '$text, $timeLabel',
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMine && author != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      author!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isMine
                        ? scheme.primary
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMine ? 18 : 5),
                      bottomRight: Radius.circular(isMine ? 5 : 18),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isMine ? scheme.onPrimary : scheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                  child: Text(
                    [?annotation, timeLabel].join('  ·  '),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
