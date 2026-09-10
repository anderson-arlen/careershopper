import 'dart:async';

import 'package:flutter/material.dart';

import '../../protocol/acp_configuration.dart';
import '../../storage/ai_harness_repository.dart';

Future<void> showAgentSettings(
  BuildContext context,
  AiHarnessStore harnesses, {
  String? profileId,
  String? conversationId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AgentSettingsDialog(
    harnesses: harnesses,
    profileId: profileId,
    conversationId: conversationId,
  ),
);

class _AgentSettingsDialog extends StatefulWidget {
  const _AgentSettingsDialog({
    required this.harnesses,
    this.profileId,
    this.conversationId,
  });
  final AiHarnessStore harnesses;
  final String? profileId;
  final String? conversationId;
  @override
  State<_AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<_AgentSettingsDialog> {
  final _done = Completer<void>();
  AcpConfigurationSession? _session;
  StreamSubscription<void>? _updates;
  late final Future<void> _connection;
  Object? _error;
  bool _busy = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _connection = _connect();
  }

  Future<void> _connect() async {
    try {
      await widget.harnesses.configureAgent(
        (session) async {
          if (!mounted) return;
          _updates = session.changes.listen((_) {
            if (mounted) setState(() {});
          });
          setState(() => _session = session);
          await _done.future;
        },
        profileId: widget.profileId,
        conversationId: widget.conversationId,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _finished = true);
    }
  }

  Future<void> _set(AcpConfigOption option, Object value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final options = await _session!.setOption(option.id, value);
      _session!.update(options);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_finished) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!_done.isCompleted) _done.complete();
    await _connection;
    if (!mounted) return;
    if (_error == null) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (!_done.isCompleted) _done.complete();
    _updates?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _finished,
    child: AlertDialog(
      title: Text(
        widget.conversationId == null
            ? 'Agent defaults'
            : 'Conversation settings',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.conversationId == null
                    ? 'Used for new chats and job imports. Choices come from the selected agent.'
                    : 'Used for the next turn in this conversation. Choices come from its agent.',
              ),
              const SizedBox(height: 20),
              for (final warning in _session?.warnings ?? <String>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(warning),
                ),
              if (_session == null && !_finished)
                const Center(child: CircularProgressIndicator()),
              if (_session?.options.isEmpty == true)
                const Text('This agent does not advertise supported settings.'),
              for (final option
                  in _session?.options ?? <AcpConfigOption>[]) ...[
                if (option.type == 'boolean')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.name),
                    subtitle: option.description == null
                        ? null
                        : Text(option.description!),
                    value: option.currentValue as bool,
                    onChanged: _busy || _finished
                        ? null
                        : (value) => _set(option, value),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${option.id}:${option.currentValue}:${option.choices.map((c) => c.value).join(',')}',
                    ),
                    initialValue:
                        option.choices.any(
                          (c) => c.value == option.currentValue,
                        )
                        ? option.currentValue as String
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: option.name,
                      helperText: option.description,
                      helperMaxLines: 4,
                    ),
                    items: [
                      for (final choice in option.choices)
                        DropdownMenuItem(
                          value: choice.value,
                          child: Text(
                            choice.group == null
                                ? choice.name
                                : '${choice.group} — ${choice.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy || _finished
                        ? null
                        : (value) {
                            if (value != null) _set(option, value);
                          },
                  ),
                const SizedBox(height: 16),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  'Could not configure agent: $_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || (_session == null && !_finished) ? null : _close,
          child: Text(_finished ? 'Close' : 'Done'),
        ),
      ],
    ),
  );
}
