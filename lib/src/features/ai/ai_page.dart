import 'chat_transcript.dart';
import 'chat_attachment_input.dart';
import '../../domain/chat_image.dart';
import 'chat_work_indicator.dart';
import 'package:flutter/material.dart';

import '../../storage/ai_harness_repository.dart';
import 'ai_harnesses_page.dart';
import 'agent_settings_dialog.dart';
import 'chat_keyboard_shortcuts.dart';

class AiPage extends StatelessWidget {
  const AiPage({required this.harnesses, super.key});

  final AiHarnessStore harnesses;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.forum_outlined), text: 'Activity'),
                Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Agents'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                AiActivityPage(harnesses: harnesses),
                AiHarnessesPage(harnesses: harnesses),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AiActivityPage extends StatefulWidget {
  const AiActivityPage({required this.harnesses, super.key});

  final AiHarnessStore harnesses;

  @override
  State<AiActivityPage> createState() => _AiActivityPageState();
}

class _AiActivityPageState extends State<AiActivityPage> {
  String? _selectedId;
  int _limit = 50;
  late var _conversations = widget.harnesses.watchConversations(
    limit: _limit + 1,
  );

  Future<void> _newChat() async {
    final message = await _messageDialog(
      title: 'New AI chat',
      action: 'Start chat',
    );
    if (message == null || !mounted) return;
    try {
      final id = await widget.harnesses.startConversation(
        message.text,
        images: message.images,
      );
      if (mounted) setState(() => _selectedId = id);
    } on Object catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<({String text, List<ChatImage> images})?> _messageDialog({
    required String title,
    required String action,
  }) => showDialog<({String text, List<ChatImage> images})>(
    context: context,
    builder: (context) => _NewChatDialog(
      harnesses: widget.harnesses,
      title: title,
      action: action,
    ),
  );

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('AI request failed: $error')));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiConversation>>(
      stream: _conversations,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load AI activity: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final hasMore = snapshot.data!.length > _limit;
        final conversations = snapshot.data!.take(_limit).toList();
        final selected = conversations
            .where((item) => item.id == _selectedId)
            .firstOrNull;
        final current = selected ?? conversations.firstOrNull;
        return Row(
          children: [
            SizedBox(
              width: 310,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _newChat,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('New chat'),
                    ),
                  ),
                  Expanded(
                    child: conversations.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'AI imports and chats will appear here as they happen.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: conversations.length + (hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == conversations.length) {
                                return TextButton(
                                  onPressed: () => setState(() {
                                    _limit += 50;
                                    _conversations = widget.harnesses
                                        .watchConversations(limit: _limit + 1);
                                  }),
                                  child: const Text('Load more conversations'),
                                );
                              }
                              final conversation = conversations[index];
                              return ListTile(
                                selected: conversation.id == current?.id,
                                leading: _StatusIcon(
                                  status: conversation.status,
                                ),
                                title: Text(
                                  conversation.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  conversation.kind == 'manual_job_import'
                                      ? 'Job import'
                                      : 'Chat',
                                ),
                                onTap: () => setState(
                                  () => _selectedId = conversation.id,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: current == null
                  ? _EmptyActivity(onNewChat: _newChat)
                  : _ConversationView(
                      key: ValueKey(current.id),
                      harnesses: widget.harnesses,
                      conversation: current,
                      onError: _showError,
                      onNewGeneration: (id) => setState(() => _selectedId = id),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _NewChatDialog extends StatefulWidget {
  const _NewChatDialog({
    required this.harnesses,
    required this.title,
    required this.action,
  });
  final AiHarnessStore harnesses;
  final String title, action;

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  final _controller = TextEditingController();
  List<ChatImage> _images = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty || _images.isNotEmpty) {
      Navigator.pop(context, (text: value, images: _images));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 560,
      child: ChatAttachmentInput(
        controller: _controller,
        images: _images,
        enabled: true,
        onChanged: (images) => setState(() => _images = images),
        child: ChatKeyboardShortcuts(
          controller: _controller,
          hasAttachments: _images.isNotEmpty,
          onSend: _submit,
          child: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Ask about your profile, searches, or jobs…',
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () => showAgentSettings(context, widget.harnesses),
        icon: const Icon(Icons.tune),
        label: const Text('Agent defaults'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

class _ConversationView extends StatefulWidget {
  const _ConversationView({
    required this.harnesses,
    required this.conversation,
    required this.onError,
    required this.onNewGeneration,
    super.key,
  });

  final AiHarnessStore harnesses;
  final AiConversation conversation;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onNewGeneration;

  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView> {
  final _controller = TextEditingController();
  List<ChatImage> _images = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if ((message.isEmpty && _images.isEmpty) || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.harnesses.sendMessage(
        widget.conversation.id,
        message,
        images: _images,
      );
      if (mounted) {
        _controller.clear();
        _images = [];
      }
    } on Object catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retry() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.harnesses.resumeMaterialGeneration(widget.conversation.id);
    } on Object catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _regenerate() async {
    final jobId = widget.conversation.jobId;
    if (_sending || jobId == null) return;
    setState(() => _sending = true);
    try {
      final result = await widget.harnesses.queueApplication(
        jobId,
        fromScratch: true,
      );
      if (mounted) widget.onNewGeneration(result.workOrderId);
    } on Object catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _interrupt() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.harnesses.interruptConversation(widget.conversation.id);
    } on Object catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.conversation.status == 'running';
    return Column(
      children: [
        ListTile(
          title: Text(
            widget.conversation.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: const Text(
            'The agent owns conversation context; CareerShopper saves this visible transcript and resumes the ACP session.',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ChatTranscript(
            key: ValueKey(widget.conversation.id),
            conversationId: widget.conversation.id,
            harnesses: widget.harnesses,
          ),
        ),
        ChatWorkIndicator(
          status: widget.conversation.status,
          busy: _sending,
          onInterrupt: _interrupt,
          onRegenerate:
              widget.conversation.kind == 'application_materials' &&
                  widget.conversation.jobId != null
              ? _regenerate
              : null,
          onRetry: widget.conversation.kind == 'application_materials'
              ? _retry
              : null,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Conversation settings',
                onPressed: running || _sending
                    ? null
                    : () => showAgentSettings(
                        context,
                        widget.harnesses,
                        conversationId: widget.conversation.id,
                      ),
                icon: const Icon(Icons.tune),
              ),
              Expanded(
                child: ChatAttachmentInput(
                  controller: _controller,
                  images: _images,
                  enabled: !_sending,
                  onChanged: (images) => setState(() => _images = images),
                  child: ChatKeyboardShortcuts(
                    controller: _controller,
                    hasAttachments: _images.isNotEmpty,
                    onSend: _sending ? null : _send,
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: running
                            ? 'Send a message to steer the agent…'
                            : 'Message the agent…',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: running ? 'Steer' : 'Send',
                child: FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                  label: Text(running ? 'Steer' : 'Send'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => status == 'running'
      ? const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(
          status == 'failed' ? Icons.error_outline : Icons.chat_bubble_outline,
          color: status == 'failed'
              ? Theme.of(context).colorScheme.error
              : null,
        );
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.onNewChat});

  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.forum_outlined, size: 52),
        const SizedBox(height: 16),
        Text(
          'No AI activity yet',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Start a chat, or add a job URL and watch the agent work here.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onNewChat,
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('New chat'),
        ),
      ],
    ),
  );
}
