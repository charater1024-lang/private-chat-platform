import 'package:flutter/material.dart';

import 'chat_ui_copy.dart';

/// A lightweight, image-free avatar that renders consistently on older devices.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    required this.label,
    required this.backgroundColor,
    this.radius = 24,
    this.isOnline = false,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final double radius;
  final bool isOnline;

  String get _initials {
    final words = label.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final copy = ChatUiCopy.of(context);
    final foreground =
        ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF14211E);

    return Semantics(
      excludeSemantics: true,
      label: copy.avatar(label, isOnline: isOnline),
      child: SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: backgroundColor,
              child: Text(
                _initials,
                style: TextStyle(
                  color: foreground,
                  fontSize: radius * .7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: radius * .55,
                  height: radius * .55,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22A06B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
