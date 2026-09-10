import 'package:flutter/material.dart';
import 'agent_settings_dialog.dart';

import '../../protocol/acp_registry.dart';
import '../../storage/ai_harness_repository.dart';
import '../../storage/ai_agent_purpose.dart';

class AiHarnessesPage extends StatelessWidget {
  const AiHarnessesPage({required this.harnesses, super.key});

  final AiHarnessStore harnesses;

  Future<void> _browseRegistry(BuildContext context) async {
    final agent = await showDialog<AcpRegistryAgent>(
      context: context,
      builder: (context) => _RegistryDialog(harnesses: harnesses),
    );
    if (agent == null || !context.mounted) return;
    try {
      await harnesses.saveRegistryAgent(agent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${agent.name} is now the default ACP agent.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _edit(BuildContext context, [AiHarnessProfile? existing]) async {
    final draft = await showDialog<AiHarnessProfileDraft>(
      context: context,
      builder: (context) => _HarnessDialog(existing: existing),
    );
    if (draft == null || !context.mounted) return;
    try {
      await harnesses.saveProfile(draft);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _remove(BuildContext context, AiHarnessProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove ACP agent?'),
        content: Text('Remove ${profile.name}? Queued jobs are retained.'),
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
    if (confirmed == true) await harnesses.deleteProfile(profile.id);
  }

  Future<void> _duplicate(
    BuildContext context,
    AiHarnessProfile profile,
  ) async {
    var draftName = '${profile.name} copy';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate configuration'),
        content: TextFormField(
          initialValue: draftName,
          onChanged: (value) => draftName = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Configuration name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftName),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
    if (name == null || !context.mounted) return;
    try {
      await harnesses.duplicateProfile(profile.id, name);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 650,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACP agents',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose a subscription-backed agent from the official ACP Registry. CareerShopper is the ACP client and supplies its scoped MCP server to each session.',
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _browseRegistry(context),
                icon: const Icon(Icons.travel_explore),
                label: const Text('Browse ACP Registry'),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('Add custom ACP agent'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: _ProtocolCard(),
        ),
        Expanded(
          child: StreamBuilder<List<AiHarnessProfile>>(
            stream: harnesses.watchProfiles(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Could not load ACP agents: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final profiles = snapshot.data!;
              if (profiles.isEmpty) return const _EmptyHarnesses();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                itemCount: profiles.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Card.outlined(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Agents by purpose',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Duplicate an agent configuration, then use Agent defaults to choose its model and thinking effort. Changes apply to new tasks.',
                            ),
                            for (final purpose in AiAgentPurpose.values) ...[
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '${purpose.name}:${profiles.where((profile) => profile.isDefaultFor(purpose)).firstOrNull?.id}',
                                ),
                                initialValue:
                                    profiles
                                        .where(
                                          (profile) =>
                                              profile.isDefaultFor(purpose),
                                        )
                                        .firstOrNull
                                        ?.id ??
                                    '',
                                decoration: InputDecoration(
                                  labelText: purpose.label,
                                  helperText:
                                      purpose == AiAgentPurpose.jobMatching
                                      ? 'Search matches and listing imports'
                                      : 'Resumes, cover letters and application answers',
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text(
                                      'Use default (${profiles.where((profile) => profile.isDefault).firstOrNull?.name ?? 'not configured'})',
                                    ),
                                  ),
                                  for (final profile in profiles.where(
                                    (profile) =>
                                        profile.protocol == 'acp_stdio',
                                  ))
                                    DropdownMenuItem(
                                      value: profile.id,
                                      child: Text(profile.name),
                                    ),
                                ],
                                onChanged: (id) async {
                                  try {
                                    await harnesses.setPurposeProfile(
                                      purpose,
                                      id == '' ? null : id,
                                    );
                                  } on Object catch (error) {
                                    if (context.mounted) {
                                      _showError(context, error);
                                    }
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }
                  final profile = profiles[index - 1];
                  final legacy = profile.protocol != 'acp_stdio';
                  return Card.outlined(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        child: Icon(
                          legacy
                              ? Icons.warning_amber
                              : Icons.smart_toy_outlined,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(child: Text(profile.name)),
                          if (profile.isDefault) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('Default'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(
                              legacy ? 'Legacy command' : 'ACP stdio',
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          legacy
                              ? 'This pre-ACP profile cannot run. Remove it and select the agent from the registry.'
                              : [
                                  if (profile.registryAgentId != null)
                                    '${profile.registryAgentId} ${profile.registryVersion ?? ''}',
                                  '${profile.executable} ${profile.arguments.join(' ')}',
                                ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!profile.isDefault && !legacy)
                            TextButton(
                              onPressed: () =>
                                  harnesses.setDefaultProfile(profile.id),
                              child: const Text('Make default'),
                            ),
                          if (!legacy)
                            IconButton(
                              tooltip: 'Duplicate configuration',
                              onPressed: () => _duplicate(context, profile),
                              icon: const Icon(Icons.copy_outlined),
                            ),
                          if (!legacy)
                            IconButton(
                              tooltip: 'Agent defaults',
                              onPressed: () => showAgentSettings(
                                context,
                                harnesses,
                                profileId: profile.id,
                              ),
                              icon: const Icon(Icons.tune),
                            ),
                          if (!legacy)
                            IconButton(
                              tooltip: 'Edit ACP agent',
                              onPressed: () => _edit(context, profile),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: 'Remove ACP agent',
                            onPressed: () => _remove(context, profile),
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

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard();

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ACP + MCP', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'CareerShopper starts the selected agent over ACP stdio, negotiates protocol v1, creates a session, and passes the CareerShopper MCP executable in session/new. Codex ACP history is stored separately inside CareerShopper. File-based Codex sign-in is shared; other agents use their existing credentials.',
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistryDialog extends StatefulWidget {
  const _RegistryDialog({required this.harnesses});

  final AiHarnessStore harnesses;

  @override
  State<_RegistryDialog> createState() => _RegistryDialogState();
}

class _RegistryDialogState extends State<_RegistryDialog> {
  late Future<AcpRegistrySnapshot> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.harnesses.fetchRegistry();
  }

  void _refresh() {
    setState(() => _future = widget.harnesses.fetchRegistry(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Official ACP Registry'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search agents',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<AcpRegistrySnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load the ACP Registry.\n${snapshot.error}',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!;
                  final agents = data.agents
                      .where((agent) {
                        if (_query.isEmpty) return true;
                        return agent.name.toLowerCase().contains(_query) ||
                            agent.description.toLowerCase().contains(_query);
                      })
                      .toList(growable: false);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.fromCache
                            ? 'Showing cached registry from ${data.fetchedAt.toLocal()}'
                            : '${agents.length} agents · refreshed ${data.fetchedAt.toLocal()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: agents.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final agent = agents[index];
                            return ListTile(
                              title: Text('${agent.name} ${agent.version}'),
                              subtitle: Text(
                                agent.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: FilledButton(
                                onPressed: () => Navigator.pop(context, agent),
                                child: const Text('Use'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh registry',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmptyHarnesses extends StatelessWidget {
  const _EmptyHarnesses();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 52),
              SizedBox(height: 16),
              Text(
                'No ACP agent selected',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                'Choose Codex, Claude, Gemini, Cursor, or another compatible agent from the official registry. Pending URLs remain available until you run them.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HarnessDialog extends StatefulWidget {
  const _HarnessDialog({this.existing});

  final AiHarnessProfile? existing;

  @override
  State<_HarnessDialog> createState() => _HarnessDialogState();
}

class _HarnessDialogState extends State<_HarnessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _executable;
  late final TextEditingController _arguments;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name);
    _executable = TextEditingController(text: widget.existing?.executable);
    _arguments = TextEditingController(
      text: widget.existing?.arguments.join('\n') ?? '',
    );
    _isDefault = widget.existing?.isDefault ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _executable.dispose();
    _arguments.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      AiHarnessProfileDraft(
        id: widget.existing?.id,
        name: _name.text,
        executable: _executable.text,
        arguments: _arguments.text.split('\n'),
        isDefault: _isDefault,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add custom ACP agent' : 'Edit ACP agent',
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _executable,
                decoration: const InputDecoration(
                  labelText: 'ACP agent executable',
                  helperText: 'An executable that speaks ACP over stdio.',
                ),
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _arguments,
                minLines: 3,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'Startup arguments (one per line)',
                  helperText: 'These start the ACP server. No shell is used.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Default ACP agent'),
                subtitle: const Text(
                  'Used for chat and purposes without a specific configuration.',
                ),
                value: _isDefault,
                onChanged: (value) => setState(() => _isDefault = value),
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
        FilledButton(onPressed: _submit, child: const Text('Save ACP agent')),
      ],
    );
  }
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required.' : null;

void _showError(BuildContext context, Object error) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Could not configure ACP agent'),
      content: SelectableText(error.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
