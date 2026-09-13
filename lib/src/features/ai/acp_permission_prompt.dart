import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

/// Serializes prompts from concurrent jobs so each decision has visible context.
class AcpPermissionPrompter {
  AcpPermissionPrompter({this.onPrompt});

  final Future<void> Function()? onPrompt;
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
          await onPrompt?.call();
          if (stopped) return;
          final navigator = navigatorKey.currentState;
          if (navigator == null || !navigator.mounted) {
            if (!response.isCompleted) response.complete(null);
            return;
          }
          final call = params['toolCall'];
          final details = _PermissionDetails(call, params['workingDirectory']);
          final options = (params['options'] as List).whereType<Map>().toList();
          final allows = options
              .where((o) => {'allow_once', 'allow_always'}.contains(o['kind']))
              .toList();
          final always = allows
              .where((o) => o['kind'] == 'allow_always')
              .toList();
          final deny = options
              .where((o) => o['kind'] == 'reject_once')
              .firstOrNull;
          route = DialogRoute<String>(
            context: navigator.context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Agent approval required'),
              content: SizedBox(
                width: 680,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                  ),
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
                        const SizedBox(height: 20),
                        Text(
                          'Requested action',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          details.title ?? 'Action details unavailable',
                        ),
                        if (details.explanation != null) ...[
                          const SizedBox(height: 8),
                          Text(details.explanation!),
                        ],
                        if (!details.hasAction) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'The agent supplied only an internal ID and status. The action cannot be reviewed, so approval is unavailable. Deny this request and retry the task.',
                          ),
                        ],
                        if (always.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Remembered permissions',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final option in always)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${_allowLabel(option, allows)}: ${_optionDescription(option) ?? 'The agent controls the scope and duration of this permission.'}',
                              ),
                            ),
                        ],
                        for (final field in details.fields.entries) ...[
                          const SizedBox(height: 16),
                          Text(
                            field.key,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            field.value,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Technical details'),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(call ?? params),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                for (final allow in allows)
                  if (allow['kind'] == 'allow_always')
                    OutlinedButton(
                      onPressed: details.hasAction
                          ? () => Navigator.pop(
                              context,
                              allow['optionId'] as String,
                            )
                          : null,
                      child: Text(_allowLabel(allow, allows)),
                    )
                  else
                    FilledButton(
                      onPressed: details.hasAction
                          ? () => Navigator.pop(
                              context,
                              allow['optionId'] as String,
                            )
                          : null,
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

String _allowLabel(Map option, List<Map> options) {
  String base(Map value) =>
      _PermissionDetails._text(value['name'])?.trim() ?? 'Always allow';
  final name = base(option);
  final repeated =
      options
          .where((o) => o['kind'] == 'allow_always' && base(o) == name)
          .length >
      1;
  return repeated ? '$name (${option['optionId']})' : name;
}

String? _optionDescription(Map option) {
  final meta = option['_meta'];
  final permission = meta is Map ? meta['permission'] : null;
  return permission is Map
      ? _PermissionDetails._text(permission['description'])
      : null;
}

class _PermissionDetails {
  _PermissionDetails(Object? raw, Object? workingDirectory) {
    final call = raw is Map ? raw : const {};
    title = _text(call['title']);
    final input = call['rawInput'];
    final arguments = input is Map ? input : const {};
    final command = arguments['command'] ?? arguments['cmd'];
    if (command != null) fields['Command'] = _format(command);
    final cwd = arguments['cwd'] ?? arguments['workdir'] ?? workingDirectory;
    if (cwd != null) fields['Working directory'] = _format(cwd);
    final reason = arguments['justification'] ?? arguments['reason'];
    if (reason != null) fields['Reason supplied by agent'] = _format(reason);
    if (input != null) {
      final remaining = input is Map ? Map.of(input) : input;
      if (remaining is Map) {
        for (final key in [
          'command',
          'cmd',
          'cwd',
          'workdir',
          'justification',
          'reason',
        ]) {
          remaining.remove(key);
        }
      }
      if (remaining is! Map || remaining.isNotEmpty) {
        fields['Arguments'] = _format(remaining);
      }
    }
    final locations = call['locations'];
    if (locations is List && locations.isNotEmpty) {
      fields['Affected paths'] = _format(locations);
    }
    final content = call['content'];
    if (content is List && content.isNotEmpty) {
      fields['Action details'] = _format(content);
    }
    hasAction =
        title != null ||
        command != null ||
        fields.containsKey('Arguments') ||
        fields.containsKey('Affected paths') ||
        fields.containsKey('Action details');
    if (title?.endsWith('careershopper_session.application_materials_submit') ==
        true) {
      explanation =
          'Save the generated resume and cover letter drafts in CareerShopper. This tool does not submit an application to the employer.';
    }
  }
  String? title, explanation;
  bool hasAction = false;
  final fields = <String, String>{};
  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
  static String _format(Object? value) => value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);
}
