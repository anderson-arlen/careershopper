import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../domain/chat_image.dart';

class ChatAttachmentInput extends StatefulWidget {
  const ChatAttachmentInput({
    required this.controller,
    required this.images,
    required this.onChanged,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final TextEditingController controller;
  final List<ChatImage> images;
  final ValueChanged<List<ChatImage>> onChanged;
  final Widget child;
  final bool enabled;
  @override
  State<ChatAttachmentInput> createState() => _ChatAttachmentInputState();
}

class _ChatAttachmentInputState extends State<ChatAttachmentInput> {
  bool _reading = false;
  String? _error;

  Future<void> _paste({bool imageOnly = false}) async {
    if (_reading || !widget.enabled) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final bytes = await Pasteboard.image;
      if (!mounted || !widget.enabled) return;
      if (bytes != null) {
        final images = [...widget.images, ChatImage.fromBytes(bytes)];
        validateChatImages(images);
        widget.onChanged(images);
      } else if (imageOnly) {
        setState(() => _error = 'No image on the clipboard.');
      } else {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!mounted || !widget.enabled || data?.text == null) return;
        final value = widget.controller.value;
        final selection = value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
        widget.controller.value = TextEditingValue(
          text: value.text.replaceRange(
            selection.start,
            selection.end,
            data!.text!,
          ),
          selection: TextSelection.collapsed(
            offset: selection.start + data.text!.length,
          ),
        );
        widget.onChanged(widget.images);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not paste: $error');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.images.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < widget.images.length; index++)
              SizedBox(
                width: 96,
                height: 88,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        widget.images[index].bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton.filledTonal(
                        tooltip: 'Remove image ${index + 1}',
                        onPressed: widget.enabled
                            ? () => widget.onChanged(
                                [...widget.images]..removeAt(index),
                              )
                            : null,
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Paste image',
            onPressed: widget.enabled && !_reading
                ? () => _paste(imageOnly: true)
                : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          Expanded(
            child: Actions(
              actions: {
                PasteTextIntent: CallbackAction<PasteTextIntent>(
                  onInvoke: (_) {
                    _paste();
                    return null;
                  },
                ),
              },
              child: widget.child,
            ),
          ),
        ],
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
