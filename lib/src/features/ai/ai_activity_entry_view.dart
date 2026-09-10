import 'package:flutter/material.dart';
import '../../storage/ai_harness_repository.dart';

class AiActivityEntryView extends StatelessWidget {
  const AiActivityEntryView({required this.entry, super.key});

  final AiActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final isMessage = entry.role == 'user' || entry.role == 'assistant';
    if (!isMessage) {
      final error = entry.kind == 'error';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.build_circle_outlined,
              size: 18,
              color: error ? Theme.of(context).colorScheme.error : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                _plainActivityText(entry.text),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: error ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final user = entry.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.text.isNotEmpty)
              SelectableText(
                user ? entry.text : _plainActivityText(entry.text),
              ),
            for (final image in entry.images)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 320,
                    maxWidth: 480,
                  ),
                  child: Image.memory(
                    image.bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('Image could not be displayed.'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _plainActivityText(String value) => value
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (match) => '${match.group(1)} — ${match.group(2)}',
    )
    .replaceAll('**', '')
    .replaceAll('`', '')
    .trim();
