import 'package:flutter/material.dart';

import '../../storage/configuration_repository.dart';
import 'source_block_notice.dart';

class SourcesPage extends StatelessWidget {
  const SourcesPage({required this.configuration, super.key});

  final ConfigurationStore configuration;

  Future<void> _edit(
    BuildContext context, [
    SourceConfiguration? existing,
  ]) async {
    final draft = await showDialog<SourceConfigurationDraft>(
      context: context,
      builder: (context) => _SourceDialog(existing: existing),
    );
    if (draft == null || !context.mounted) return;
    try {
      await configuration.saveSourceConfiguration(draft);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Source added.' : 'Source updated.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _remove(BuildContext context, SourceConfiguration source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove source?'),
        content: Text(
          'Remove ${_sourceLabel(source)}? Existing jobs and history are retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await configuration.deleteSourceConfiguration(source.id);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          title: 'Sources',
          subtitle:
              'Connect public job searches and employer boards. Technical blocks disable acquisition; CareerShopper never attempts circumvention.',
          action: FilledButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('Add source'),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SourceConfiguration>>(
            stream: configuration.watchSourceConfigurations(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return _ErrorState(error: snapshot.error!);
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final sources = snapshot.data!;
              if (sources.isEmpty) {
                return _EmptyState(
                  icon: Icons.hub_outlined,
                  title: 'No sources configured',
                  message:
                      'Add Indeed, LinkedIn, or an employer ATS board, then attach it to a saved search.',
                  actionLabel: 'Add source',
                  onAction: () => _edit(context),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                itemCount: sources.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return Card.outlined(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        child: Text(
                          source.sourceFamily.characters.first.toUpperCase(),
                        ),
                      ),
                      title: Text(_sourceLabel(source)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${_displayName(source.sourceFamily)} · ${source.boardIdentifier}',
                            ),
                            if (source.healthState == 'unavailable')
                              SourceBlockNotice(
                                source: source,
                                configuration: configuration,
                              )
                            else
                              _HealthChip(source: source),
                            if ({
                              'indeed',
                              'linkedin',
                            }.contains(source.sourceFamily))
                              const Chip(
                                label: Text('Fragile public endpoint'),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (source.healthDetail != null &&
                                source.healthState != 'unavailable')
                              Text(
                                source.healthDetail!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: source.enabled,
                            onChanged: (value) =>
                                configuration.setSourceConfigurationEnabled(
                                  source.id,
                                  value,
                                ),
                          ),
                          IconButton(
                            tooltip: 'Edit source',
                            onPressed: () => _edit(context, source),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Remove source',
                            onPressed: () => _remove(context, source),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog({this.existing});

  final SourceConfiguration? existing;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _family;
  late bool _enabled;
  late final TextEditingController _employer;
  late final TextEditingController _identifier;

  BuiltInSourceType get _type =>
      builtInSourceTypes.firstWhere((item) => item.family == _family);

  @override
  void initState() {
    super.initState();
    _family = widget.existing?.sourceFamily ?? builtInSourceTypes.first.family;
    _enabled = widget.existing?.enabled ?? true;
    _employer = TextEditingController(text: widget.existing?.employerName);
    _identifier = TextEditingController(
      text:
          widget.existing?.boardIdentifier ??
          builtInSourceTypes.first.defaultIdentifier,
    );
  }

  @override
  void dispose() {
    _employer.dispose();
    _identifier.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      SourceConfigurationDraft(
        id: widget.existing?.id,
        sourceFamily: _family,
        enabled: _enabled,
        values: {
          if (_type.employerRequired) 'employer_name': _employer.text.trim(),
          if (_type.identifierKey != null)
            _type.identifierKey!: _identifier.text.trim(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add source' : 'Edit source'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _family,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  for (final type in builtInSourceTypes)
                    DropdownMenuItem(
                      value: type.family,
                      child: Text(type.displayName),
                    ),
                ],
                onChanged: widget.existing == null
                    ? (value) => setState(() {
                        _family = value!;
                        _employer.clear();
                        _identifier.text = _type.defaultIdentifier ?? '';
                      })
                    : null,
              ),
              if (_type.employerRequired) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _employer,
                  decoration: const InputDecoration(labelText: 'Employer name'),
                  autofocus: true,
                  validator: _required,
                ),
              ],
              if (_type.identifierKey != null) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: ValueKey(_family),
                  controller: _identifier,
                  decoration: InputDecoration(
                    labelText: _type.identifierLabel,
                    helperText: _type.identifierHint,
                  ),
                  validator: _required,
                ),
              ],
              if (!_type.employerRequired && _type.identifierKey == null) ...[
                const SizedBox(height: 16),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.public),
                  title: Text('Global public job search'),
                  subtitle: Text('No login or account configuration is used.'),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                subtitle: const Text(
                  'Enabled sources can be used by attached searches.',
                ),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save source')),
      ],
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.source});
  final SourceConfiguration source;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (source.healthState) {
      'healthy' => (Icons.check_circle_outline, 'Healthy', Colors.green),
      'backoff' => (Icons.schedule, 'Backing off', Colors.orange),
      'unavailable' => (Icons.block, 'Blocked', Colors.red),
      'error' => (Icons.error_outline, 'Error', Colors.red),
      _ => (Icons.help_outline, 'Not checked', Colors.grey),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _displayName(String family) =>
    builtInSourceTypes
        .where((item) => item.family == family)
        .map((item) => item.displayName)
        .firstOrNull ??
    family;

String _sourceLabel(SourceConfiguration source) => source.employerName.isEmpty
    ? _displayName(source.sourceFamily)
    : source.employerName;

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.action,
  });
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 16),
        action,
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) =>
      Center(child: SelectableText('Unable to load sources:\n$error'));
}
