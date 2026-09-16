import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/job.dart';
import 'editable_markdown_preview.dart';
import '../../storage/ai_harness_repository.dart';
import '../../storage/application_material_repository.dart';

class ApplicationMaterialsPanel extends StatefulWidget {
  const ApplicationMaterialsPanel({
    super.key,
    required this.job,
    required this.harnesses,
    this.onDirtyChanged,
    this.applying = false,
  });
  final InboxJob job;
  final AiHarnessStore harnesses;
  final ValueChanged<bool>? onDirtyChanged;
  final bool applying;
  @override
  State<ApplicationMaterialsPanel> createState() =>
      _ApplicationMaterialsPanelState();
}

class _ApplicationMaterialsPanelState extends State<ApplicationMaterialsPanel> {
  bool _busy = false;
  bool _dirty = false;
  late Stream<ApplicationMaterials?> _materials;
  late Stream<String?> _status;
  @override
  void initState() {
    super.initState();
    _materials = widget.harnesses.watchMaterials(widget.job.id);
    _status = widget.harnesses.watchMaterialStatus(widget.job.id);
    if (widget.job.reviewState == ReviewState.approved &&
        (widget.job.applicationStatus == ApplicationStatus.notApplied ||
            widget.job.applicationStatus == ApplicationStatus.readyToApply)) {
      unawaited(_ensureDrafts());
    }
  }

  Future<void> _ensureDrafts() => _run(() async {
    final draft = await widget.harnesses.watchMaterials(widget.job.id).first;
    final status = await widget.harnesses
        .watchMaterialStatus(widget.job.id)
        .first;
    // Catch up approvals predating automatic generation. Never retry a failed
    // attempt on navigation or regenerate an existing draft without user action.
    if (mounted && draft == null && status == null) {
      await widget.harnesses.queueApplication(widget.job.id);
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: _status,
    builder: (context, status) => StreamBuilder<ApplicationMaterials?>(
      stream: _materials,
      builder: (context, snapshot) {
        final draft = snapshot.data;
        final generating = ['queued', 'running'].contains(status.data);
        return Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Application documents',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  status.data == 'queued'
                      ? 'Document regeneration is queued. Follow progress in AI → Activity.'
                      : generating
                      ? 'Drafting resume and cover letter… Follow progress in AI → Activity.'
                      : _dirty
                      ? 'Unsaved Markdown edits. Save or revert them before regenerating, exporting, or applying.'
                      : (status.data == 'failed' ||
                            status.data == 'interrupted')
                      ? draft == null
                            ? 'Generation paused. Resume saved work or generate from scratch below. See AI → Activity for details.'
                            : 'Generation paused after an error. Your previous documents and new staged work are preserved. Choose Resume generation or Generate from scratch.'
                      : draft == null
                      ? 'Generate a tailored resume and cover letter to enable Apply. Review is optional.'
                      : draft.outdated
                      ? 'Documents out of date: your profile has changed. Regenerate only if you want to update them; you can still export or apply with this saved pair.'
                      : draft.reviewed
                      ? 'Resume and cover letter reviewed.'
                      : 'Documents ready to apply. You can optionally review or edit them here.',
                ),
                if (snapshot.hasError || status.hasError)
                  Text(
                    'Could not load drafts: ${snapshot.error ?? status.error}',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _busy || widget.applying || generating || _dirty
                          ? null
                          : () => _run(() async {
                              await widget.harnesses.queueApplication(
                                widget.job.id,
                                fromScratch:
                                    status.data != 'failed' &&
                                    status.data != 'interrupted',
                              );
                            }),
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        status.data == 'failed' || status.data == 'interrupted'
                            ? 'Resume generation'
                            : draft == null
                            ? 'Generate documents'
                            : 'Generate from scratch',
                      ),
                    ),
                    if (status.data == 'failed' || status.data == 'interrupted')
                      OutlinedButton.icon(
                        onPressed:
                            _busy || widget.applying || generating || _dirty
                            ? null
                            : () => _run(() async {
                                await widget.harnesses.queueApplication(
                                  widget.job.id,
                                  fromScratch: true,
                                );
                              }),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate from scratch'),
                      ),
                  ],
                ),
                if (_busy || generating) const LinearProgressIndicator(),
                if (draft != null) ...[
                  const SizedBox(height: 16),
                  _MaterialEditor(
                    key: ValueKey(draft.id),
                    job: widget.job,
                    draft: draft,
                    harnesses: widget.harnesses,
                    enabled: !_busy && !widget.applying && !generating,
                    onDirtyChanged: (value) {
                      if (mounted) setState(() => _dirty = value);
                      widget.onDirtyChanged?.call(value);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _MaterialEditor extends StatefulWidget {
  const _MaterialEditor({
    super.key,
    required this.job,
    required this.draft,
    required this.harnesses,
    required this.enabled,
    required this.onDirtyChanged,
  });
  final InboxJob job;
  final ApplicationMaterials draft;
  final AiHarnessStore harnesses;
  final bool enabled;
  final ValueChanged<bool> onDirtyChanged;
  @override
  State<_MaterialEditor> createState() => _MaterialEditorState();
}

class _MaterialEditorState extends State<_MaterialEditor> {
  late final TextEditingController _resume = TextEditingController(
    text: widget.draft.resume,
  );
  late final TextEditingController _cover = TextEditingController(
    text: widget.draft.coverLetter,
  );
  bool _source = false, _saving = false;
  String? _error;
  @override
  void dispose() {
    _resume.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onDirtyChanged(true);
    try {
      await widget.harnesses.saveMaterials(
        widget.job.id,
        widget.draft.id,
        _resume.text,
        _cover.text,
      );
      widget.onDirtyChanged(false);
      if (mounted) setState(() => _saving = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _copyMarkdown(
    TextEditingController controller,
    String label,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: controller.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label Markdown copied, including current edits and evidence references.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not copy Markdown: $error')),
      );
    }
  }

  Widget _document(TextEditingController controller, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () => _copyMarkdown(controller, label),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy Markdown'),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(child: _documentContent(controller)),
    ],
  );

  Widget _documentContent(TextEditingController controller) {
    if (_source) {
      return TextField(
        controller: controller,
        readOnly: !widget.enabled || _saving,
        onChanged: (_) => widget.onDirtyChanged(
          _resume.text != widget.draft.resume ||
              _cover.text != widget.draft.coverLetter,
        ),
        expands: true,
        minLines: null,
        maxLines: null,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Markdown',
        ),
        style: const TextStyle(fontFamily: 'monospace'),
      );
    }
    return EditableMarkdownPreview(
      controller: controller,
      enabled: widget.enabled && !_saving,
      onChanged: () => widget.onDirtyChanged(
        _resume.text != widget.draft.resume ||
            _cover.text != widget.draft.coverLetter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 520,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Markdown source'),
                subtitle: const Text(
                  'Edit the preview directly. Use source for structure and evidence references.',
                ),
                value: _source,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _source = value),
              ),
              if (_source)
                const Text(
                  'Keep each block’s facts comment linked to confirmed career facts. These comments are excluded from exported files.',
                ),
              const TabBar(
                tabs: [
                  Tab(text: 'Resume'),
                  Tab(text: 'Cover letter'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _document(_resume, 'Resume'),
                    _document(_cover, 'Cover letter'),
                  ],
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: _saving || !widget.enabled
                ? null
                : () {
                    setState(() {
                      _resume.text = widget.draft.resume;
                      _cover.text = widget.draft.coverLetter;
                      _error = null;
                    });
                    widget.onDirtyChanged(false);
                  },
            child: const Text('Revert edits'),
          ),
          FilledButton(
            onPressed: _saving || !widget.enabled ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save & mark reviewed'),
          ),
        ],
      ),
    ],
  );
}
