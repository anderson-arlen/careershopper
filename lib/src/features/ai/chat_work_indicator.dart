import 'package:flutter/material.dart';

class ChatWorkIndicator extends StatelessWidget {
  const ChatWorkIndicator({
    required this.status,
    required this.onInterrupt,
    this.busy = false,
    this.onRetry,
    this.onRegenerate,
    super.key,
  });

  final String? status;
  final VoidCallback onInterrupt;
  final bool busy;
  final VoidCallback? onRetry, onRegenerate;

  @override
  Widget build(BuildContext context) {
    final running = status == 'running';
    final stopped =
        status == 'interrupted' ||
        (status == 'failed' && (onRetry != null || onRegenerate != null));
    if (!running &&
        !stopped &&
        !(status == 'completed' && onRegenerate != null)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                      : status == 'completed'
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                  size: 18,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  running
                      ? (busy
                            ? 'Interrupting current turn…'
                            : 'Agent is working…')
                      : busy
                      ? 'Starting document generation…'
                      : status == 'completed'
                      ? 'Documents generated.'
                      : onRegenerate != null
                      ? 'Work stopped. Resume saved work or generate fresh documents.'
                      : onRetry != null
                      ? 'Work stopped. Retry resumes the unfinished step.'
                      : 'Interrupted. Send a message to continue.',
                  semanticsLabel: running
                      ? 'Agent is working'
                      : status == 'failed'
                      ? 'Agent failed'
                      : status == 'completed'
                      ? 'Agent completed'
                      : 'Agent interrupted',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (stopped && onRetry != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onRetry,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume generation'),
                ),
              if (!running && onRegenerate != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : onRegenerate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate from scratch'),
                ),
              if (running)
                OutlinedButton.icon(
                  onPressed: busy ? null : onInterrupt,
                  icon: const Icon(Icons.stop),
                  label: const Text('Interrupt'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
