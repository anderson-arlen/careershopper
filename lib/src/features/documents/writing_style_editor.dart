import 'package:flutter/material.dart';

import '../../storage/writing_style_repository.dart';

class WritingStyleEditor extends StatefulWidget {
  const WritingStyleEditor({this.repository, super.key});
  final WritingStyleRepository? repository;

  @override
  State<WritingStyleEditor> createState() => _WritingStyleEditorState();
}

class _WritingStyleEditorState extends State<WritingStyleEditor> {
  late final repository = widget.repository ?? WritingStyleRepository();
  final text = TextEditingController();
  Map<String, Object?>? saved;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await repository.read();
      if (!mounted) return;
      setState(() {
        saved = value;
        text.text = value['text'] as String;
        error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final value = await repository.save(
        text.text,
        saved!['revision'] as String,
      );
      if (!mounted) return;
      setState(() {
        saved = value;
        error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared writing style saved.')),
      );
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Shared writing style'),
    subtitle: const Text(
      'Voice and writing rules for resumes, cover letters, and application answers',
    ),
    children: [
      if (error != null) SelectableText(error!),
      if (saved != null) ...[
        SelectableText(saved!['path'] as String),
        const SizedBox(height: 8),
        TextField(
          controller: text,
          minLines: 8,
          maxLines: 18,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Writing style',
            border: OutlineInputBorder(),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(
                      () => text.text = saved!['default_text'] as String,
                    ),
              child: const Text('Reset writing style to default'),
            ),
            TextButton(
              onPressed: busy ? null : _load,
              child: const Text('Reload saved style'),
            ),
            FilledButton(
              onPressed: busy ? null : _save,
              child: const Text('Save writing style'),
            ),
          ],
        ),
        const Text(
          'Save writing style commits edits or a reset independently of the template. Existing documents remain unchanged.',
        ),
      ] else if (error == null)
        const LinearProgressIndicator()
      else
        TextButton(onPressed: _load, child: const Text('Reload writing style')),
    ],
  );
}
