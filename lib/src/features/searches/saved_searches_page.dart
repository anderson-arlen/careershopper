import 'dart:convert';

import 'package:flutter/material.dart';

import '../../sources/job_source_adapter.dart';
import '../sources/source_block_notice.dart';
import '../../storage/configuration_repository.dart';
import '../../storage/ai_harness_repository.dart';

class SavedSearchesPage extends StatefulWidget {
  const SavedSearchesPage({
    required this.configuration,
    required this.harnesses,
    super.key,
  });

  final ConfigurationStore configuration;
  final AiHarnessStore harnesses;

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  ConfigurationStore get configuration => widget.configuration;
  AiHarnessStore get harnesses => widget.harnesses;
  final _running = <String>{};

  void _history(BuildContext context, SavedSearchDefinition search) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Run history: ${search.name}'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: StreamBuilder<List<SearchRunRecord>>(
            stream: configuration.watchSearchRuns(savedSearchId: search.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SelectableText(
                  'Could not read history: ${snapshot.error}',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Text('No recorded runs yet.');
              }
              return ListView(
                children: [
                  for (final run in snapshot.data!)
                    _RunDetails(
                      source: run.sourceName,
                      status: run.status,
                      detail: run.detail,
                      diagnostics: run.diagnostics,
                      observations: run.observations,
                      timestamp: run.startedAt.toLocal().toString(),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    List<SourceConfiguration> sources, [
    SavedSearchDefinition? existing,
  ]) async {
    final draft = await showDialog<SavedSearchDraft>(
      context: context,
      builder: (context) =>
          _SavedSearchDialog(sources: sources, existing: existing),
    );
    if (draft == null || !context.mounted) return;
    try {
      await configuration.saveSavedSearch(draft);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Search added.' : 'Search updated.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _remove(
    BuildContext context,
    SavedSearchDefinition search,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove saved search?'),
        content: Text(
          'Remove “${search.name}”? Previously discovered jobs and run history are retained.',
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
      await configuration.deleteSavedSearch(search.id);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _run(BuildContext context, SavedSearchDefinition search) async {
    if (_running.contains(search.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run search now?'),
        content: Text(
          'CareerShopper will contact the sources attached to “${search.name}”. Your configured AI will analyze new or changed matches. Already evaluated listings are skipped. Provider backoff and blocking responses are respected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run search'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _running.add(search.id));
    try {
      if (!(await harnesses.watchProfiles().first).any(
        (profile) => profile.isJobMatchingDefault || profile.isDefault,
      )) {
        throw const NoDefaultAiHarnessException();
      }
      final result = await configuration.runSavedSearch(search.id);
      var analyzing = 0;
      String? analysisError;
      try {
        if (result.candidateJobIds.isNotEmpty) {
          analyzing = await harnesses.dispatchSearchAnalysis(
            result.candidateJobIds,
          );
        }
      } on Object catch (error) {
        analysisError = error.toString();
      }
      if (!context.mounted) return;
      setState(() => _running.remove(search.id));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Search results: ${search.name}'),
          content: SizedBox(
            width: 760,
            height: 480,
            child: ListView(
              children: [
                Text(
                  analysisError == null
                      ? '$analyzing jobs queued for AI analysis.'
                      : 'AI analysis could not start: $analysisError',
                ),
                const SizedBox(height: 12),
                for (final source in result.sources)
                  _RunDetails(
                    source: source.sourceName,
                    status: source.status,
                    detail: source.detail,
                    observations: source.observations,
                    diagnostics: source.diagnostics,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _running.remove(search.id));
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Search could not complete'),
            content: SelectableText(error.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _running.remove(search.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SourceConfiguration>>(
      stream: configuration.watchSourceConfigurations(),
      builder: (context, sourceSnapshot) {
        final sources = sourceSnapshot.data ?? const <SourceConfiguration>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              title: 'Search strategy',
              subtitle:
                  'Create searches yourself or ask your AI harness to build and refine them from your profile and preferences.',
              action: FilledButton.icon(
                onPressed: () => _edit(context, sources),
                icon: const Icon(Icons.add),
                label: const Text('Add search'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Card.filled(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('AI-assisted or manual—it is your strategy'),
                  subtitle: Text(
                    'You can edit every search here. Your AI harness can use the same searches through MCP when you ask it to add coverage or tune the results.',
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SavedSearchDefinition>>(
                stream: configuration.watchSavedSearches(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: SelectableText(
                        'Unable to load searches:\n${snapshot.error}',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final searches = snapshot.data!;
                  if (searches.isEmpty) {
                    return _EmptySearchStrategy(
                      onAdd: () => _edit(context, sources),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    itemCount: searches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final search = searches[index];
                      final attached = sources
                          .where(
                            (source) =>
                                search.sourceConfigIds.contains(source.id),
                          )
                          .toList(growable: false);
                      return _SearchCard(
                        configuration: configuration,
                        search: search,
                        sources: attached,
                        onEdit: () => _edit(context, sources, search),
                        onRemove: () => _remove(context, search),
                        onRun: _running.contains(search.id)
                            ? null
                            : () => _run(context, search),
                        onHistory: () => _history(context, search),
                        running: _running.contains(search.id),
                        onEnabledChanged: (value) async {
                          try {
                            await configuration.setSavedSearchEnabled(
                              search.id,
                              value,
                            );
                          } on Object catch (error) {
                            if (context.mounted) _showError(context, error);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.configuration,
    required this.search,
    required this.sources,
    required this.onEdit,
    required this.onRemove,
    required this.onRun,
    required this.onEnabledChanged,
    required this.onHistory,
    required this.running,
  });

  final SavedSearchDefinition search;
  final ConfigurationStore configuration;
  final List<SourceConfiguration> sources;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback? onRun;
  final VoidCallback onHistory;
  final bool running;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    search.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(label: Text('AI threshold ${search.scoreThreshold}')),
                const SizedBox(width: 8),
                Switch(value: search.enabled, onChanged: onEnabledChanged),
                IconButton(
                  tooltip: running ? 'Search running' : 'Run search now',
                  onPressed: onRun,
                  icon: running
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined),
                ),
                IconButton(
                  tooltip: 'Edit search',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove search',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sources: ${sources.isEmpty ? 'none attached' : sources.map(_sourceLabel).join(' · ')}',
            ),
            for (final source in sources.where(
              (source) => source.healthState == 'unavailable',
            ))
              SourceBlockNotice(source: source, configuration: configuration),
            const SizedBox(height: 4),
            Text(
              '${search.enabled ? 'Active' : 'Paused'} · Requested interval: ${_intervalLabel(search.pollIntervalMinutes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history),
              label: const Text('Run history & diagnostics'),
            ),
            const Divider(height: 28),
            _Terms(label: 'Target titles', values: search.query.includedTitles),
            _Terms(
              label: 'Required signals',
              values: search.query.includedKeywords,
            ),
            _Terms(label: 'Locations', values: search.query.locations),
            _Terms(label: 'Workplace', values: search.query.remoteStatuses),
            _Terms(
              label: 'Employment types',
              values: search.query.employmentTypes,
            ),
            _Terms(
              label: 'Excluded titles',
              values: search.query.excludedTitles,
              excluded: true,
            ),
            _Terms(
              label: 'Excluded signals',
              values: search.query.excludedKeywords,
              excluded: true,
            ),
            if (search.query.minimumCompensation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Compensation floor: ${search.query.currency ?? ''} ${search.query.minimumCompensation}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedSearchDialog extends StatefulWidget {
  const _SavedSearchDialog({required this.sources, this.existing});

  final List<SourceConfiguration> sources;
  final SavedSearchDefinition? existing;

  @override
  State<_SavedSearchDialog> createState() => _SavedSearchDialogState();
}

class _SavedSearchDialogState extends State<_SavedSearchDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _titles;
  late final TextEditingController _requiredKeywords;
  late final TextEditingController _locations;
  late final TextEditingController _remoteStatuses;
  late final TextEditingController _employmentTypes;
  late final TextEditingController _excludedTitles;
  late final TextEditingController _excludedKeywords;
  late final TextEditingController _minimumCompensation;
  late final TextEditingController _currency;
  late final TextEditingController _pollInterval;
  late final TextEditingController _scoreThreshold;
  late final Set<String> _sourceIds;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name);
    _titles = _listController(existing?.query.includedTitles);
    _requiredKeywords = _listController(existing?.query.includedKeywords);
    _locations = _listController(existing?.query.locations);
    _remoteStatuses = _listController(existing?.query.remoteStatuses);
    _employmentTypes = _listController(existing?.query.employmentTypes);
    _excludedTitles = _listController(existing?.query.excludedTitles);
    _excludedKeywords = _listController(existing?.query.excludedKeywords);
    _minimumCompensation = TextEditingController(
      text: existing?.query.minimumCompensation?.toString(),
    );
    _currency = TextEditingController(text: existing?.query.currency ?? 'USD');
    _pollInterval = TextEditingController(
      text: (existing?.pollIntervalMinutes ?? 360).toString(),
    );
    _scoreThreshold = TextEditingController(
      text: (existing?.scoreThreshold ?? 70).toString(),
    );
    _sourceIds = {...?existing?.sourceConfigIds};
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _titles,
      _requiredKeywords,
      _locations,
      _remoteStatuses,
      _employmentTypes,
      _excludedTitles,
      _excludedKeywords,
      _minimumCompensation,
      _currency,
      _pollInterval,
      _scoreThreshold,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final compensation = _minimumCompensation.text.trim();
    Navigator.pop(
      context,
      SavedSearchDraft(
        id: widget.existing?.id,
        name: name,
        enabled: _enabled,
        pollIntervalMinutes: int.parse(_pollInterval.text.trim()),
        scoreThreshold: int.parse(_scoreThreshold.text.trim()),
        sourceConfigIds: _sourceIds,
        query: SavedSearchQuery(
          name: name,
          includedTitles: _parseTerms(_titles.text),
          includedKeywords: _parseTerms(_requiredKeywords.text),
          locations: _parseTerms(_locations.text),
          remoteStatuses: _parseTerms(_remoteStatuses.text),
          employmentTypes: _parseTerms(_employmentTypes.text),
          excludedTitles: _parseTerms(_excludedTitles.text),
          excludedKeywords: _parseTerms(_excludedKeywords.text),
          minimumCompensation: compensation.isEmpty
              ? null
              : int.parse(compensation),
          currency: compensation.isEmpty || _currency.text.trim().isEmpty
              ? null
              : _currency.text.trim().toUpperCase(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add saved search' : 'Edit search'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Search name'),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                _TermField(
                  controller: _titles,
                  label: 'Target titles',
                  hint: 'Backend Engineer, Platform Engineer',
                ),
                const SizedBox(height: 12),
                _TermField(
                  controller: _requiredKeywords,
                  label: 'Required signals',
                  hint: 'distributed systems, Kubernetes',
                ),
                const SizedBox(height: 12),
                _TermField(
                  controller: _locations,
                  label: 'Locations',
                  hint: 'Denver, United States',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TermField(
                        controller: _remoteStatuses,
                        label: 'Workplace',
                        hint: 'remote, hybrid',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TermField(
                        controller: _employmentTypes,
                        label: 'Employment types',
                        hint: 'full-time, contract',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TermField(
                  controller: _excludedTitles,
                  label: 'Excluded titles',
                  hint: 'Manager, Sales',
                ),
                const SizedBox(height: 12),
                _TermField(
                  controller: _excludedKeywords,
                  label: 'Excluded signals',
                  hint: 'commission only, unpaid',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minimumCompensation,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minimum compensation',
                        ),
                        validator: _optionalNonNegativeInteger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _currency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          hintText: 'USD',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _scoreThreshold,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'AI threshold (0–100)',
                        ),
                        validator: (value) => _integerRange(value, 0, 100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pollInterval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Polling interval (minutes)',
                    helperText: 'Between 30 minutes and 7 days.',
                  ),
                  validator: (value) => _integerRange(value, 30, 10080),
                ),
                const SizedBox(height: 16),
                Text('Sources', style: Theme.of(context).textTheme.titleMedium),
                if (widget.sources.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No sources are configured yet. You can save this search and attach sources later.',
                    ),
                  )
                else
                  for (final source in widget.sources)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(_sourceLabel(source)),
                      subtitle: Text(
                        builtInSourceTypes
                                .where(
                                  (type) => type.family == source.sourceFamily,
                                )
                                .map((type) => type.displayName)
                                .firstOrNull ??
                            source.sourceFamily,
                      ),
                      value: _sourceIds.contains(source.id),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _sourceIds.add(source.id);
                        } else {
                          _sourceIds.remove(source.id);
                        }
                      }),
                    ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save search')),
      ],
    );
  }
}

class _TermField extends StatelessWidget {
  const _TermField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: 'Separate multiple values with commas.',
    ),
  );
}

class _Terms extends StatelessWidget {
  const _Terms({
    required this.label,
    required this.values,
    this.excluded = false,
  });

  final String label;
  final List<String> values;
  final bool excluded;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(label),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: values
                  .map(
                    (value) => Chip(
                      avatar: excluded
                          ? const Icon(Icons.block, size: 15)
                          : null,
                      label: Text(value),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearchStrategy extends StatelessWidget {
  const _EmptySearchStrategy({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.manage_search,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'No saved searches yet',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Add one manually, or ask your AI harness to review your profile and create a focused initial strategy.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add search'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

TextEditingController _listController(List<String>? values) =>
    TextEditingController(text: values?.join(', '));

List<String> _parseTerms(String value) => value
    .split(RegExp(r'[,\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList(growable: false);

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _optionalNonNegativeInteger(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final parsed = int.tryParse(value.trim());
  return parsed == null || parsed < 0 ? 'Enter a positive whole number' : null;
}

String? _integerRange(String? value, int minimum, int maximum) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed < minimum || parsed > maximum) {
    return 'Enter a whole number from $minimum to $maximum';
  }
  return null;
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

String _sourceLabel(SourceConfiguration source) {
  if (source.employerName.isNotEmpty) return source.employerName;
  return builtInSourceTypes
          .where((type) => type.family == source.sourceFamily)
          .map((type) => type.displayName)
          .firstOrNull ??
      source.sourceFamily;
}

String _intervalLabel(int minutes) {
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} day(s)';
  if (minutes % 60 == 0) return '${minutes ~/ 60} hour(s)';
  return '$minutes minutes';
}

class _RunDetails extends StatelessWidget {
  const _RunDetails({
    required this.source,
    required this.status,
    this.detail,
    required this.diagnostics,
    required this.observations,
    this.timestamp,
  });
  final String source, status;
  final String? detail, timestamp;
  final Map<String, Object?> diagnostics;
  final int observations;

  @override
  Widget build(BuildContext context) {
    final failed = status == 'failed';
    final label = switch (status) {
      'succeeded' => 'Completed',
      'failed' => 'Failed',
      'warning' =>
        (diagnostics['normalization_failures'] as int? ?? 0) > 0 &&
                (diagnostics['warnings'] as List? ?? const []).isEmpty
            ? 'Completed with skipped records'
            : 'Completed with warnings',
      'skipped' => 'Skipped',
      _ => 'Running / unfinished',
    };
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : status == 'warning'
                      ? Icons.warning_amber_outlined
                      : status == 'skipped'
                      ? Icons.pause_circle_outline
                      : Icons.info_outline,
                  color: failed
                      ? Theme.of(context).colorScheme.error
                      : status == 'warning'
                      ? Colors.amber
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$source: $label',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (timestamp != null) Text(timestamp!),
            const SizedBox(height: 8),
            SelectableText(
              detail ?? 'This older run has no saved explanation.',
            ),
            if (diagnostics.containsKey('pages_read')) ...[
              const SizedBox(height: 8),
              SelectableText(
                [
                  'Pages read: ${diagnostics['pages_read']}',
                  if (diagnostics['more_results_available'] == true)
                    'More results available: stopped at the first page (100-result limit).',
                  'Listing records: $observations',
                  'New jobs: ${diagnostics['created_jobs']}',
                  'Existing observations: ${diagnostics['existing_observations']}',
                  'Filtered by search: ${diagnostics['filtered_by_search']}',
                  'Blocked employers: ${diagnostics['blocked_employers']}',
                  'Could not normalize: ${diagnostics['normalization_failures']}',
                  'Eligible for AI: ${diagnostics['ai_candidates']}',
                  'Duplicate or otherwise ineligible for AI: ${diagnostics['ineligible_for_ai']}',
                ].join('\n'),
              ),
            ] else if (status == 'succeeded')
              Text(
                'Recorded observations: $observations. Detailed counters were not saved for this older run.',
              ),
            if (diagnostics.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Run diagnostics'),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert({
                      for (final entry in diagnostics.entries)
                        if (entry.key != 'requests') entry.key: entry.value,
                    }),
                  ),
                ],
              ),
            for (final (index, exchange)
                in (diagnostics['requests'] as List? ?? const []).indexed)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Request ${index + 1} and response'),
                children: [
                  if ((exchange as Map)['request'] == null)
                    const Text(
                      'Request and response bodies were not saved for this older run.',
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(exchange),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
