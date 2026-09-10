import 'package:flutter/material.dart';

class ChatWorkIndicator extends StatelessWidget {
  const ChatWorkIndicator({
    required this.status,
    required this.onInterrupt,
    this.busy = false,
    this.onRetry,
    super.key,
  });

  final String? status;
  final VoidCallback onInterrupt;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (status != 'running' &&
        status != 'interrupted' &&
        !(status == 'failed' && onRetry != null)) {
      return const SizedBox.shrink();
    }
    final running = status == 'running';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (running)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              status == 'failed'
                  ? Icons.error_outline
                  : Icons.pause_circle_outline,
              size: 18,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              running
                  ? busy
                        ? 'Interrupting current turn…'
                        : 'Agent is working…'
                  : onRetry != null
                  ? busy
                        ? 'Resuming saved work…'
                        : 'Work stopped. Retry resumes the unfinished step.'
                  : 'Interrupted. Send a message to continue.',
              semanticsLabel: running
                  ? 'Agent is working'
                  : status == 'failed'
                  ? 'Agent failed'
                  : 'Agent interrupted',
            ),
          ),
          if (!running && onRetry != null)
            OutlinedButton.icon(
              onPressed: busy ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          if (running)
            OutlinedButton.icon(
              onPressed: busy ? null : onInterrupt,
              icon: const Icon(Icons.stop),
              label: const Text('Interrupt'),
            ),
        ],
      ),
    );
  }
}
