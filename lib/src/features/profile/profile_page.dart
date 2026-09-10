import 'dart:convert';

import 'package:flutter/material.dart';

import '../../storage/profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.profile, super.key});

  final ProfileStore profile;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _statusFilter = 'all';
  String _kindFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CareerProfileFact>>(
      stream: widget.profile.watchCareerFacts(),
      builder: (context, factSnapshot) {
        if (factSnapshot.hasError) {
          return Center(
            child: SelectableText(
              'Unable to load career profile:\n${factSnapshot.error}',
            ),
          );
        }
        final facts = factSnapshot.data ?? const <CareerProfileFact>[];
        return StreamBuilder<List<CareerPreferenceValue>>(
          stream: widget.profile.watchCareerPreferences(),
          builder: (context, preferenceSnapshot) {
            final preferences =
                preferenceSnapshot.data ?? const <CareerPreferenceValue>[];
            return DefaultTabController(
              length: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Career profile',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The factual background and preferences used to design searches and ground application materials.',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _editPreference(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add preference'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _editFact(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add fact'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _ProfileSummary(
                      facts: facts,
                      preferenceCount: preferences.length,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Career facts'),
                      Tab(text: 'Preferences'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _factsView(facts),
                        _PreferencesView(
                          preferences: preferences,
                          onEdit: _editPreference,
                          onDelete: _deletePreference,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _factsView(List<CareerProfileFact> facts) {
    final kinds =
        facts
            .map((fact) => fact.kind)
            .where((kind) => kind != 'all')
            .toSet()
            .toList()
          ..sort();
    final effectiveKind = kinds.contains(_kindFilter) ? _kindFilter : 'all';
    final filtered = facts
        .where(
          (fact) =>
              (_statusFilter == 'all' ||
                  fact.verificationStatus == _statusFilter) &&
              (effectiveKind == 'all' || fact.kind == effectiveKind),
        )
        .toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Type:'),
              InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('fact-type-filter'),
                    value: effectiveKind,
                    isDense: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All types'),
                      ),
                      for (final kind in kinds)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(_humanize(kind)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _kindFilter = value ?? 'all'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Status:'),
              for (final status in const [
                'all',
                'pending',
                'confirmed',
                'disputed',
                'retired',
              ]) ...[
                FilterChip(
                  label: Text(_humanize(status)),
                  selected: _statusFilter == status,
                  onSelected: (_) => setState(() => _statusFilter = status),
                ),
              ],
              if (effectiveKind != 'all' || _statusFilter != 'all')
                TextButton.icon(
                  onPressed: () => setState(() {
                    _kindFilter = 'all';
                    _statusFilter = 'all';
                  }),
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear filters'),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyFacts(hasAnyFacts: facts.isNotEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _FactCard(
                    fact: filtered[index],
                    onStatus: (status) => _setStatus(filtered[index], status),
                    onEdit: () => _editFact(filtered[index]),
                    onRetire: () => _retireFact(filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _setStatus(CareerProfileFact fact, String status) async {
    if (status != 'confirmed') {
      final verb = status == 'confirmed' ? 'confirm' : 'mark as disputed';
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${_humanize(status)} career fact?'),
          content: Text(
            'Do you want to $verb this ${_humanize(fact.kind).toLowerCase()} fact? A new immutable review revision will be recorded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_humanize(status)),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    try {
      await widget.profile.setFactVerificationStatus(
        fact.id,
        status,
        actor: 'desktop_user',
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _editFact([CareerProfileFact? existing]) async {
    final draft = await showDialog<CareerFactDraft>(
      context: context,
      builder: (context) => _CareerFactDialog(existing: existing),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.profile.saveCareerFact(draft, actor: 'desktop_user');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing == null ? 'Fact added.' : 'Fact updated.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _retireFact(CareerProfileFact fact) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire career fact?'),
        content: const Text(
          'The fact will stop grounding new application materials. Its revision history will be retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retire fact'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.profile.retireCareerFact(fact.id, actor: 'desktop_user');
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _editPreference([CareerPreferenceValue? existing]) async {
    final draft = await showDialog<CareerPreferenceDraft>(
      context: context,
      builder: (context) => _CareerPreferenceDialog(existing: existing),
    );
    if (draft == null || !mounted) return;
    try {
      await widget.profile.saveCareerPreference(draft);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Preference added.' : 'Preference updated.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  Future<void> _deletePreference(CareerPreferenceValue preference) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove career preference?'),
        content: Text(
          'Remove “${_humanize(preference.key)}” from the profile?',
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
    if (accepted != true || !mounted) return;
    try {
      await widget.profile.deleteCareerPreference(preference.id);
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    }
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.facts, required this.preferenceCount});

  final List<CareerProfileFact> facts;
  final int preferenceCount;

  @override
  Widget build(BuildContext context) {
    final confirmed = facts
        .where((fact) => fact.verificationStatus == 'confirmed')
        .length;
    final pending = facts
        .where((fact) => fact.verificationStatus == 'pending')
        .length;
    return Card.filled(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'You and your AI harness share this profile. User edits create confirmed revisions; only confirmed facts may ground applicant claims.',
              ),
            ),
            _Count(label: 'Confirmed', value: confirmed),
            _Count(label: 'Pending', value: pending),
            _Count(label: 'Preferences', value: preferenceCount),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 20),
    child: Column(
      children: [
        Text('$value', style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.fact,
    required this.onStatus,
    required this.onEdit,
    required this.onRetire,
  });

  final CareerProfileFact fact;
  final ValueChanged<String> onStatus;
  final VoidCallback onEdit;
  final VoidCallback onRetire;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ExpansionTile(
        initiallyExpanded: fact.verificationStatus == 'pending',
        leading: _StatusIcon(status: fact.verificationStatus),
        title: Text(_humanize(fact.kind)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _StatusChip(status: fact.verificationStatus),
              Chip(
                label: Text(_humanize(fact.visibility)),
                visualDensity: VisualDensity.compact,
              ),
              if (fact.sourceLabel != null)
                Chip(
                  avatar: const Icon(Icons.source_outlined, size: 15),
                  label: Text(fact.sourceLabel!),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            _formatValue(fact.value),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (fact.evidenceText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text('Evidence', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(fact.evidenceText!),
          ],
          const SizedBox(height: 12),
          Text(
            'Fact ${fact.id} · Revision ${fact.revisionId}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (fact.verificationStatus != 'retired')
                TextButton.icon(
                  onPressed: onRetire,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Retire'),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  fact.verificationStatus == 'retired'
                      ? 'Edit and restore'
                      : 'Edit fact',
                ),
              ),
            ],
          ),
          if (fact.verificationStatus != 'confirmed' &&
              fact.verificationStatus != 'retired') ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: fact.verificationStatus == 'disputed'
                      ? null
                      : () => onStatus('disputed'),
                  icon: const Icon(Icons.report_outlined),
                  label: const Text('Dispute'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => onStatus('confirmed'),
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm fact'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Icon(
    switch (status) {
      'confirmed' => Icons.verified_outlined,
      'pending' => Icons.pending_outlined,
      'disputed' => Icons.report_outlined,
      'retired' => Icons.archive_outlined,
      _ => Icons.history,
    },
    color: switch (status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange,
      'disputed' => Theme.of(context).colorScheme.error,
      _ => null,
    },
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(_humanize(status)),
    visualDensity: VisualDensity.compact,
  );
}

class _PreferencesView extends StatelessWidget {
  const _PreferencesView({
    required this.preferences,
    required this.onEdit,
    required this.onDelete,
  });
  final List<CareerPreferenceValue> preferences;
  final ValueChanged<CareerPreferenceValue> onEdit;
  final ValueChanged<CareerPreferenceValue> onDelete;

  @override
  Widget build(BuildContext context) {
    if (preferences.isEmpty) {
      return const _EmptyPreferences();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      itemCount: preferences.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final preference = preferences[index];
        return Card.outlined(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: Text(_humanize(preference.key)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(_formatValue(preference.value)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit preference',
                  onPressed: () => onEdit(preference),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove preference',
                  onPressed: () => onDelete(preference),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CareerFactDialog extends StatefulWidget {
  const _CareerFactDialog({this.existing});

  final CareerProfileFact? existing;

  @override
  State<_CareerFactDialog> createState() => _CareerFactDialogState();
}

class _CareerFactDialogState extends State<_CareerFactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kind;
  late final TextEditingController _value;
  late final TextEditingController _evidence;
  late String _visibility;

  @override
  void initState() {
    super.initState();
    _kind = TextEditingController(text: widget.existing?.kind);
    _value = TextEditingController(
      text: _editableJson(widget.existing?.value ?? <String, Object?>{}),
    );
    _evidence = TextEditingController(text: widget.existing?.evidenceText);
    _visibility = widget.existing?.visibility ?? 'resume';
  }

  @override
  void dispose() {
    _kind.dispose();
    _value.dispose();
    _evidence.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CareerFactDraft(
        id: widget.existing?.id,
        kind: _kind.text.trim(),
        value: _requiredJson(_value.text),
        visibility: _visibility,
        evidenceText: _evidence.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add career fact' : 'Edit career fact',
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _kind,
                  autofocus: widget.existing == null,
                  decoration: const InputDecoration(
                    labelText: 'Fact type',
                    hintText: 'employment',
                    helperText:
                        'Use lower_snake_case, such as identity, employment, skill, project, or education.',
                  ),
                  validator: _snakeCase,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _visibility,
                  decoration: const InputDecoration(labelText: 'Visibility'),
                  items: const [
                    DropdownMenuItem(value: 'resume', child: Text('Resume')),
                    DropdownMenuItem(
                      value: 'application_only',
                      child: Text('Application only'),
                    ),
                    DropdownMenuItem(value: 'private', child: Text('Private')),
                  ],
                  onChanged: (value) => setState(() => _visibility = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _value,
                  minLines: 6,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    labelText: 'Structured value (JSON)',
                    alignLabelWithHint: true,
                    helperText:
                        'Edit every field while preserving the structure needed for dates, lists, and related details.',
                  ),
                  validator: _requiredJsonValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _evidence,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes or evidence',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history),
                  title: Text('Edits preserve history'),
                  subtitle: Text(
                    'Saving creates a new confirmed revision attributed to you. Earlier revisions and their provenance remain intact.',
                  ),
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
        FilledButton(onPressed: _submit, child: const Text('Save fact')),
      ],
    );
  }
}

class _CareerPreferenceDialog extends StatefulWidget {
  const _CareerPreferenceDialog({this.existing});

  final CareerPreferenceValue? existing;

  @override
  State<_CareerPreferenceDialog> createState() =>
      _CareerPreferenceDialogState();
}

class _CareerPreferenceDialogState extends State<_CareerPreferenceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _key;
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: widget.existing?.key);
    _value = TextEditingController(
      text: _editableJson(widget.existing?.value ?? ''),
    );
  }

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CareerPreferenceDraft(
        id: widget.existing?.id,
        key: _key.text.trim(),
        value: _requiredJson(_value.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Add career preference'
            : 'Edit career preference',
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _key,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Preference name',
                  hintText: 'preferred_workplace',
                  helperText: 'Use a stable lower_snake_case name.',
                ),
                validator: _snakeCase,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _value,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Value (JSON)',
                  alignLabelWithHint: true,
                  helperText:
                      'Examples: "remote", true, or ["remote", "hybrid"].',
                ),
                validator: _requiredJsonValidator,
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
        FilledButton(onPressed: _submit, child: const Text('Save preference')),
      ],
    );
  }
}

class _EmptyFacts extends StatelessWidget {
  const _EmptyFacts({required this.hasAnyFacts});
  final bool hasAnyFacts;

  @override
  Widget build(BuildContext context) => _EmptyProfileSection(
    icon: Icons.badge_outlined,
    title: hasAnyFacts ? 'No facts match this filter' : 'No career facts yet',
    message: hasAnyFacts
        ? 'Choose another verification filter.'
        : 'Add a fact here or ask your AI harness to build your factual CareerShopper profile from existing material.',
  );
}

class _EmptyPreferences extends StatelessWidget {
  const _EmptyPreferences();

  @override
  Widget build(BuildContext context) => const _EmptyProfileSection(
    icon: Icons.tune,
    title: 'No career preferences yet',
    message:
        'Add preferences here, or tell your AI harness what you want more or less of.',
  );
}

class _EmptyProfileSection extends StatelessWidget {
  const _EmptyProfileSection({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
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
          ],
        ),
      ),
    ),
  );
}

String _humanize(String value) {
  final spaced = value.replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return value;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _formatValue(Object? value) {
  if (value == null) return 'Not specified';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map((item) => '• ${_formatValue(item)}').join('\n');
  }
  if (value is Map) {
    return value.entries
        .map(
          (entry) =>
              '${_humanize(entry.key.toString())}: ${_inlineValue(entry.value)}',
        )
        .join('\n');
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

String _inlineValue(Object? value) {
  if (value is List) return value.map(_inlineValue).join(', ');
  if (value is Map) {
    return value.entries
        .map(
          (entry) =>
              '${_humanize(entry.key.toString())}: ${_inlineValue(entry.value)}',
        )
        .join('; ');
  }
  return value?.toString() ?? 'Not specified';
}

String _editableJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Object _requiredJson(String value) {
  final decoded = jsonDecode(value);
  if (decoded == null) {
    throw const FormatException('A value is required.');
  }
  return decoded as Object;
}

String? _requiredJsonValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'A value is required';
  try {
    _requiredJson(value);
  } on FormatException catch (error) {
    return 'Enter valid JSON: ${error.message}';
  }
  return null;
}

String? _snakeCase(String? value) {
  final candidate = value?.trim() ?? '';
  if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(candidate)) {
    return 'Use lower_snake_case';
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
