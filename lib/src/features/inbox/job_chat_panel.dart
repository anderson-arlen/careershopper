import 'package:flutter/material.dart';

import '../../domain/job.dart';
import '../../storage/ai_harness_repository.dart';
import '../ai/chat_transcript.dart';
import '../ai/chat_attachment_input.dart';
import '../../domain/chat_image.dart';
import '../ai/chat_keyboard_shortcuts.dart';
import '../ai/chat_work_indicator.dart';

class JobChatPanel extends StatefulWidget {
  const JobChatPanel({required this.job, required this.harnesses, super.key});
  final InboxJob job;
  final AiHarnessStore harnesses;

  @override
  State<JobChatPanel> createState() => _JobChatPanelState();
}

class _JobChatPanelState extends State<JobChatPanel> {
  final _message = TextEditingController();
  List<ChatImage> _images = [];
  late final Stream<List<AiConversation>> _conversations;
  String? _selectedId, _error;
  bool _sending = false;
  bool get _hasDraft => _message.text.trim().isNotEmpty || _images.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _conversations = widget.harnesses.watchConversations(jobId: widget.job.id);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_hasDraft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsent message?'),
          content: const Text('You have an unsent message for this job.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard message'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _send(AiConversation? conversation) async {
    final message = _message.text.trim();
    if ((message.isEmpty && _images.isEmpty) || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (conversation?.kind == 'job_chat') {
        await widget.harnesses.sendMessage(
          conversation!.id,
          message,
          images: _images,
        );
      } else {
        final id = await widget.harnesses.startJobConversation(
          widget.job.id,
          message,
          contextConversationId: conversation?.id,
          images: _images,
        );
        if (mounted) _selectedId = id;
      }
      if (mounted) {
        _message.clear();
        _images = [];
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retry(AiConversation conversation) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.harnesses.resumeMaterialGeneration(conversation.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _interrupt(AiConversation conversation) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.harnesses.interruptConversation(conversation.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_hasDraft,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Column(
      children: [
        ListTile(
          title: Text(
            widget.job.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(widget.job.employerName),
          trailing: IconButton(
            tooltip: 'Close job chat',
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<AiConversation>>(
            stream: _conversations,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load job conversations: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final conversations = snapshot.data!;
              _selectedId ??=
                  conversations
                      .where((c) => c.kind == 'job_chat')
                      .firstOrNull
                      ?.id ??
                  conversations.firstOrNull?.id;
              final current = conversations
                  .where((c) => c.id == _selectedId)
                  .firstOrNull;
              final running =
                  current?.kind == 'job_chat' && current?.status == 'running';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(current?.id),
                      initialValue: current?.id ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Conversation context',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('New discussion with listing and notes'),
                        ),
                        for (final conversation in conversations)
                          DropdownMenuItem(
                            value: conversation.id,
                            child: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _sending
                          ? null
                          : (value) => setState(() => _selectedId = value),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      current?.kind == 'job_chat'
                          ? 'Continue this job discussion with its saved agent session.'
                          : 'Your message starts a job discussion using the listing, evaluation, saved notes and the selected conversation’s visible history.',
                    ),
                  ),
                  Expanded(
                    child: current == null
                        ? const Center(
                            child: Text(
                              'Ask about this listing, its fit, or conflicting requirements.',
                            ),
                          )
                        : ChatTranscript(
                            key: ValueKey(current.id),
                            conversationId: current.id,
                            harnesses: widget.harnesses,
                          ),
                  ),
                  if (current != null)
                    ChatWorkIndicator(
                      status: current.status,
                      busy: _sending,
                      onInterrupt: () => _interrupt(current),
                      onRetry: current.kind == 'application_materials'
                          ? () => _retry(current)
                          : null,
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: ChatAttachmentInput(
                            controller: _message,
                            images: _images,
                            enabled: !_sending,
                            onChanged: (images) =>
                                setState(() => _images = images),
                            child: ChatKeyboardShortcuts(
                              controller: _message,
                              hasAttachments: _images.isNotEmpty,
                              onSend: _sending ? null : () => _send(current),
                              child: TextField(
                                controller: _message,
                                enabled: !_sending,
                                minLines: 2,
                                maxLines: 6,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Message about this job',
                                  hintText: running
                                      ? 'Send a message to steer the agent…'
                                      : 'Is this actually a remote role?',
                                ),
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: running
                              ? 'Steer job message'
                              : 'Send job message',
                          child: FilledButton.icon(
                            onPressed: _sending ? null : () => _send(current),
                            icon: const Icon(Icons.send),
                            label: Text(running ? 'Steer' : 'Send'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
