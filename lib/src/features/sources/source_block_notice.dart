import 'package:flutter/material.dart';

import '../../storage/configuration_repository.dart';

class SourceBlockNotice extends StatelessWidget {
  const SourceBlockNotice({
    required this.source,
    required this.configuration,
    super.key,
  });

  final SourceConfiguration source;
  final ConfigurationStore configuration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = source.employerName.isNotEmpty
        ? source.employerName
        : builtInSourceTypes
                  .where((type) => type.family == source.sourceFamily)
                  .firstOrNull
                  ?.displayName ??
              source.sourceFamily;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.block, color: colors.onErrorContainer),
              Text(
                '$name: Blocked',
                style: TextStyle(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.onErrorContainer,
                ),
                onPressed: () async {
                  try {
                    final cleared = await configuration.clearSourceBlock(
                      source.id,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          cleared
                              ? 'Block cleared. No search was started.'
                              : 'This source is no longer blocked.',
                        ),
                      ),
                    );
                  } on Object catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Unable to clear block: $error')),
                    );
                  }
                },
                child: const Text('Clear block'),
              ),
            ],
          ),
          Text(
            source.healthDetail ??
                'Requests are paused after a provider block.',
            style: TextStyle(color: colors.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
