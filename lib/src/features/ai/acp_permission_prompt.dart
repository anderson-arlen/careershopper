import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

/// Serializes prompts from concurrent jobs so each decision has visible context.
class AcpPermissionPrompter {
  final navigatorKey = GlobalKey<NavigatorState>();
  Future<void> _queue = Future.value();

  Future<String?> request(Map<String, Object?> params, Future<void> cancelled) {
    final response = Completer<String?>();
    var stopped = false;
    DialogRoute<String>? route;
    unawaited(
      cancelled.then((_) {
        stopped = true;
        if (!response.isCompleted) response.complete(null);
        final active = route;
        if (active != null && active.isActive) {
          active.navigator?.removeRoute(active);
        }
      }),
    );
    _queue = _queue
        .then((_) async {
          if (stopped) return;
          final navigator = navigatorKey.currentState;
          if (navigator == null || !navigator.mounted) {
            if (!response.isCompleted) response.complete(null);
            return;
          }
          final call = params['toolCall'];
          final title = call is Map ? call['title']?.toString() : null;
          final options = (params['options'] as List).whereType<Map>().toList();
          final allow = options
              .where((o) => o['kind'] == 'allow_once')
              .firstOrNull;
          final deny = options
              .where((o) => o['kind'] == 'reject_once')
              .firstOrNull;
          route = DialogRoute<String>(
            context: navigator.context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Agent approval required'),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        params['conversationTitle']?.toString() ??
                            'AI conversation',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        title ??
                            'The agent is requesting permission to use a tool.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Review this request before allowing it. This decision applies once.',
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(call ?? params),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () =>
                      Navigator.pop(context, deny?['optionId'] as String?),
                  child: const Text('Deny'),
                ),
                if (allow != null)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, allow['optionId'] as String),
                    child: const Text('Allow once'),
                  ),
              ],
            ),
          );
          try {
            final selected = await navigator.push(route!);
            if (!response.isCompleted) {
              response.complete(stopped ? null : selected);
            }
          } finally {
            route = null;
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (!response.isCompleted) response.completeError(error, stack);
        });
    return response.future;
  }
}
