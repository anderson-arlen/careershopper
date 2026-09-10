import 'package:flutter/material.dart';

import '../../storage/ai_harness_repository.dart';
import 'ai_activity_entry_view.dart';

class ChatTranscript extends StatefulWidget {
  const ChatTranscript({
    required this.conversationId,
    required this.harnesses,
    super.key,
  });
  final String conversationId;
  final AiHarnessStore harnesses;
  @override
  State<ChatTranscript> createState() => _ChatTranscriptState();
}

class _ChatTranscriptState extends State<ChatTranscript> {
  final _scroll = ScrollController();
  late final _activity = widget.harnesses.watchActivity(widget.conversationId);
  bool _follow = true, _scheduled = false, _adjusting = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _followOutput() {
    if (!_follow || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_follow || !_scroll.hasClients) return;
      final bottom = _scroll.position.maxScrollExtent;
      if ((_scroll.offset - bottom).abs() < 0.5) return;
      _adjusting = true;
      _scroll.jumpTo(bottom);
      _adjusting = false;
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AiActivityEntry>>(
    stream: _activity,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text('Could not load transcript: ${snapshot.error}'),
        );
      }
      final entries = (snapshot.data ?? const <AiActivityEntry>[])
          .where(
            (entry) =>
                !(entry.kind == 'tool_call' && entry.text == 'completed'),
          )
          .toList();
      _followOutput();
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _followOutput();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                !_adjusting &&
                notification is ScrollUpdateNotification) {
              _follow = notification.metrics.extentAfter <= 24;
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (_, index) =>
                AiActivityEntryView(entry: entries[index]),
          ),
        ),
      );
    },
  );
}
