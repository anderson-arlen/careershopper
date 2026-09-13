import 'dart:convert';
import 'package:flutter/material.dart';
import '../../storage/profile_repository.dart';
import 'resume_content_editor.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.profile, super.key});
  final ProfileStore profile;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<CareerPreferenceValue>>(
    stream: widget.profile.watchCareerPreferences(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: SelectableText(
            'Unable to load preferences: ${snapshot.error}',
          ),
        );
      }
      final preferences = snapshot.data ?? const <CareerPreferenceValue>[];
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
                    'Your resume content and preferences guide job matching and applications.',
                  ),
                ],
              ),
            ),
            Builder(
              builder: (context) => AnimatedBuilder(
                animation: DefaultTabController.of(context),
                builder: (context, _) =>
                    DefaultTabController.of(context).index == 0
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _editPreference(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add preference'),
                          ),
                        ),
                      ),
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Resume content'),
                Tab(text: 'Preferences'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ResumeContentEditor(profile: widget.profile),
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
