import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../storage/application_answer_repository.dart';
import '../../storage/database.dart';

class ApplicationAnswersPanel extends StatefulWidget {
  const ApplicationAnswersPanel({
    super.key,
    required this.jobId,
    required this.repository,
  });
  final String jobId;
  final ApplicationAnswerRepository repository;

  @override
  State<ApplicationAnswersPanel> createState() =>
      _ApplicationAnswersPanelState();
}

class _ApplicationAnswersPanelState extends State<ApplicationAnswersPanel> {
  late final answers = widget.repository.watch(widget.jobId);

  void _edit([ApplicationAnswerRow? answer]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AnswerEditor(
      jobId: widget.jobId,
      repository: widget.repository,
      existing: answer,
    ),
  );

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Application answers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('Save answer'),
              ),
            ],
          ),
          const Text(
            'Keep the questions and exact answers from your application. Ask your connected harness to draft an answer or save it here. Mark it submitted once you have sent it; submitted answers are included in interview prep.',
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ApplicationAnswerRow>>(
            stream: answers,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Could not load answers: ${snapshot.error}');
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) {
                return const Text('No saved answers yet.');
              }
              return Column(
                children: [
                  for (final answer in snapshot.data!)
                    ExpansionTile(
                      key: ValueKey(answer.id),
                      tilePadding: EdgeInsets.zero,
                      title: Text(answer.question),
                      subtitle: Text(
                        '${answer.status == 'submitted' ? 'Submitted' : 'Draft'} · Saved ${MaterialLocalizations.of(context).formatMediumDate(answer.updatedAt.toLocal())}, ${answer.updatedAt.toLocal().year}',
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(answer.answer),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: answer.answer),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Answer copied.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy answer'),
                            ),
                            TextButton.icon(
                              onPressed: () => _edit(answer),
                              icon: const Icon(Icons.edit),
                              label: const Text('Edit answer'),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _AnswerEditor extends StatefulWidget {
  const _AnswerEditor({
    required this.jobId,
    required this.repository,
    this.existing,
  });
  final String jobId;
  final ApplicationAnswerRepository repository;
  final ApplicationAnswerRow? existing;
  @override
  State<_AnswerEditor> createState() => _AnswerEditorState();
}

class _AnswerEditorState extends State<_AnswerEditor> {
  final form = GlobalKey<FormState>();
  late final question = TextEditingController(text: widget.existing?.question);
  late final answer = TextEditingController(text: widget.existing?.answer);
  late final id = widget.existing?.id ?? const Uuid().v7();
  late bool submitted = widget.existing?.status == 'submitted';
  bool saving = false;
  String? error;

  @override
  void dispose() {
    question.dispose();
    answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.save(
        jobId: widget.jobId,
        answerId: id,
        expectedRevision: widget.existing?.revision ?? 0,
        question: question.text,
        answer: answer.text,
        status: submitted ? 'submitted' : 'draft',
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null
          ? 'Save application answer'
          : 'Edit application answer',
    ),
    content: SizedBox(
      width: 660,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: question,
                minLines: 1,
                maxLines: 4,
                maxLength: 12000,
                decoration: const InputDecoration(
                  labelText: 'Application question',
                ),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter the question.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: answer,
                minLines: 5,
                maxLines: 12,
                maxLength: 30000,
                decoration: const InputDecoration(labelText: 'Exact answer'),
                validator: (value) =>
                    value!.trim().isEmpty ? 'Enter the answer.' : null,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I submitted this answer'),
                subtitle: const Text('Otherwise, keep it as a draft.'),
                value: submitted,
                onChanged: saving
                    ? null
                    : (value) => setState(() => submitted = value!),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
