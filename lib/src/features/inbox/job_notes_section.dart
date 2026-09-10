import 'package:flutter/material.dart';

import '../../storage/job_repository.dart';

class JobNotesSection extends StatelessWidget {
  const JobNotesSection({required this.jobId, required this.jobs, super.key});
  final String jobId;
  final JobStore jobs;

  @override
  Widget build(BuildContext context) => StreamBuilder<String>(
    stream: jobs.watchJobNotes(jobId),
    builder: (context, snapshot) => Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_note),
                label: Text(
                  snapshot.data?.isNotEmpty == true
                      ? 'Edit notes'
                      : 'Add notes',
                ),
                onPressed: !snapshot.hasData
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => _NotesEditor(
                          jobId: jobId,
                          jobs: jobs,
                          notes: snapshot.data!,
                        ),
                      ),
              ),
            ],
          ),
          if (snapshot.hasError)
            Text('Could not load notes: ${snapshot.error}')
          else if (snapshot.hasData)
            Text(snapshot.data!.isEmpty ? 'No notes yet.' : snapshot.data!),
        ],
      ),
    ),
  );
}

class _NotesEditor extends StatefulWidget {
  const _NotesEditor({
    required this.jobId,
    required this.jobs,
    required this.notes,
  });
  final String jobId, notes;
  final JobStore jobs;

  @override
  State<_NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends State<_NotesEditor> {
  late final _controller = TextEditingController(text: widget.notes);
  late String _saved = widget.notes;
  bool _saving = false;
  String? _error;
  bool get _dirty => _controller.text != _saved;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved notes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard notes'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final notes = _controller.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.jobs.saveJobNotes(
        widget.jobId,
        notes,
        expectedNotes: _saved,
      );
      if (mounted) {
        setState(() => _saved = notes);
        Navigator.pop(context);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: AlertDialog(
      title: const Text('Job notes'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              minLines: 5,
              maxLines: 14,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          final notes = await widget.jobs
                              .watchJobNotes(widget.jobId)
                              .first;
                          if (mounted) {
                            setState(() {
                              _saved = notes;
                              _controller.text = notes;
                              _error = null;
                            });
                          }
                        } on Object catch (error) {
                          if (mounted) {
                            setState(() => _error = error.toString());
                          }
                        }
                      },
                child: const Text('Reload saved notes'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _close,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || !_dirty ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save notes'),
        ),
      ],
    ),
  );
}
