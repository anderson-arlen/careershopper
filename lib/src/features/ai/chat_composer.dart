import 'package:flutter/material.dart';

/// Centers a fixed-size circular action beside the text field.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.field,
    required this.hasAttachments,
    required this.running,
    required this.busy,
    required this.onSend,
    required this.onInterrupt,
  });

  final TextEditingController controller;
  final Widget field;
  final bool hasAttachments, running, busy;
  final VoidCallback onSend;
  final VoidCallback? onInterrupt;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: field),
      const SizedBox(width: 12),
      SizedBox.square(
        dimension: 48,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final hasContent = value.text.trim().isNotEmpty || hasAttachments;
            final stop = running && !hasContent;
            return IconButton.filled(
              tooltip: stop
                  ? 'Stop'
                  : running
                  ? 'Send message to steer agent'
                  : 'Send',
              onPressed: busy
                  ? null
                  : stop
                  ? onInterrupt
                  : hasContent
                  ? onSend
                  : null,
              style: IconButton.styleFrom(shape: const CircleBorder()),
              icon: Icon(stop ? Icons.stop : Icons.play_arrow),
            );
          },
        ),
      ),
    ],
  );
}
