import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'acp_permission.dart';

/// Remembers explicit Codex choices for the local CareerShopper MCP tool only.
/// Commands, title matches, other servers and unknown option scopes never match.
class AcpToolPermissions {
  AcpToolPermissions(this.directory, this.endpointIdentity);
  final Directory directory;
  final List<Object> endpointIdentity;

  String? _tool(Map<String, Object?> params) {
    final call = params['toolCall'];
    if (call is! Map) return null;
    final meta = call['_meta'];
    final input = call['rawInput'];
    if (meta is! Map ||
        meta['is_mcp_tool_call'] != true ||
        input is! Map ||
        input['server'] != 'careershopper_session' ||
        input['tool'] is! String ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(input['tool'] as String)) {
      return null;
    }
    return input['tool'] as String;
  }

  Map<String, Object> _grant(String tool, String? session) => {
    'version': 1,
    'endpoint': endpointIdentity,
    'server': 'careershopper_session',
    'tool': tool,
    'session': ?session,
  };

  File _file(Map<String, Object> grant) => File(
    '${directory.path}/${sha256.convert(utf8.encode(jsonEncode(grant)))}.json',
  );

  Future<bool> _has(Map<String, Object> grant) async {
    try {
      return await _file(grant).readAsString() == jsonEncode(grant);
    } on FileSystemException {
      return false;
    }
  }

  Map<String, Object?> describe(Map<String, Object?> params) {
    if (_tool(params) == null || params['options'] is! List) return params;
    return {
      ...params,
      'options': [
        for (final raw in params['options'] as List)
          if (raw is Map &&
              raw['kind'] == 'allow_always' &&
              {'allow_session', 'allow_always'}.contains(raw['optionId']))
            {
              ...raw,
              '_meta': {
                'permission': {
                  'version': 1,
                  'description': raw['optionId'] == 'allow_session'
                      ? 'CareerShopper will remember this tool for this agent session, including resumed work.'
                      : 'CareerShopper will remember this tool for future jobs and after restarting the app.',
                },
              },
            }
          else
            raw,
      ],
    };
  }

  Future<Map<String, Object?>> resolve(
    Map<String, Object?> params, {
    required AcpPermissionPrompt? prompt,
    required Future<void> cancelled,
    required void Function() onRemembered,
  }) async {
    final tool = _tool(params);
    final session = params['sessionId'] is String
        ? params['sessionId'] as String
        : null;
    final response = await requestAcpPermission(
      params,
      cancelled: cancelled,
      prompt: (offered, stop) async {
        if (tool != null) {
          final once = (offered['options'] as List)
              .whereType<Map>()
              .where((o) => o['kind'] == 'allow_once')
              .firstOrNull;
          if (once != null &&
              (await _has(_grant(tool, null)) ||
                  (session != null && await _has(_grant(tool, session))))) {
            onRemembered();
            return once['optionId'] as String;
          }
        }
        if (prompt == null) {
          throw StateError(
            'The agent requested authorization, but no interactive approval prompt is available. Continue this work in the CareerShopper desktop app. Nothing was authorized.',
          );
        }
        return prompt(describe(offered), stop);
      },
    );
    final outcome = response['outcome'] as Map;
    final selected = outcome['optionId'];
    final raw = params['options'];
    final option = raw is List
        ? raw
              .whereType<Map>()
              .where((o) => o['optionId'] == selected)
              .firstOrNull
        : null;
    if (tool != null &&
        outcome['outcome'] == 'selected' &&
        option?['kind'] == 'allow_always' &&
        (selected == 'allow_always' ||
            (selected == 'allow_session' && session != null))) {
      final grant = _grant(tool, selected == 'allow_session' ? session : null);
      await directory.create(recursive: true);
      final file = _file(grant);
      final temporary = File('${file.path}.${const Uuid().v4()}.tmp');
      try {
        await temporary.writeAsString(jsonEncode(grant), flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return response;
  }
}
