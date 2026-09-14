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
  int _limit = 100;
  late var _activity = widget.harnesses.watchActivity(
    widget.conversationId,
    limit: _limit + 1,
    latest: true,
  );
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
      final rows = snapshot.data ?? const <AiActivityEntry>[];
      final hasMore = rows.length > _limit;
      final entries = (hasMore ? rows.skip(rows.length - _limit) : rows)
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
            itemCount: entries.length + (hasMore ? 1 : 0),
            itemBuilder: (_, index) {
              if (hasMore && index == 0) {
                return TextButton(
                  onPressed: () => setState(() {
                    _follow = false;
                    _limit += 100;
                    _activity = widget.harnesses.watchActivity(
                      widget.conversationId,
                      limit: _limit + 1,
                      latest: true,
                    );
                  }),
                  child: const Text('Load earlier messages'),
                );
              }
              return AiActivityEntryView(
                key: ValueKey(entries[index - (hasMore ? 1 : 0)].id),
                entry: entries[index - (hasMore ? 1 : 0)],
              );
            },
          ),
        ),
      );
    },
  );
}
