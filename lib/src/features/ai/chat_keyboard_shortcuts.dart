import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatKeyboardShortcuts extends StatelessWidget {
  const ChatKeyboardShortcuts({
    required this.controller,
    required this.onSend,
    required this.child,
    this.hasAttachments = false,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback? onSend;
  final Widget child;
  final bool hasAttachments;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      final keyboard = HardwareKeyboard.instance;
      if (event.logicalKey != LogicalKeyboardKey.enter &&
          event.logicalKey != LogicalKeyboardKey.numpadEnter) {
        return KeyEventResult.ignored;
      }
      // Leave newline entry and composition confirmation to the text input.
      if (keyboard.isShiftPressed ||
          keyboard.isControlPressed ||
          keyboard.isAltPressed ||
          keyboard.isMetaPressed ||
          !controller.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent &&
          (controller.text.trim().isNotEmpty || hasAttachments)) {
        onSend?.call();
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}
