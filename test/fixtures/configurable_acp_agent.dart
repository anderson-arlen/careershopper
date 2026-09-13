// A real JSONL subprocess for exercising the ACP transport, without a model.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final log = File(args.first);
  if (args.contains('record-environment')) {
    await log.writeAsString(
      '${jsonEncode({'method': 'fixture/environment', 'home': Platform.environment['CODEX_HOME'], 'sqlite': Platform.environment['CODEX_SQLITE_HOME'], 'initialMode': Platform.environment['INITIAL_AGENT_MODE'], 'config': Platform.environment['CODEX_CONFIG']})}\n',
      mode: FileMode.append,
    );
  }
  var model = 'alpha';
  var effort = 'low';
  var fast = false;
  var mode = 'agent';
  final codex = args.contains('@agentclientprotocol/codex-acp@1.9.0');
  Object? permissionPromptId;
  List<Map<String, Object>> options() => [
    if (codex && !args.contains('missing-approval-mode'))
      {
        'id': 'mode',
        'name': 'Mode',
        'category': 'mode',
        'type': 'select',
        'currentValue': mode,
        'options': [
          {'value': 'read-only', 'name': 'Ask for approval'},
          {'value': 'agent', 'name': 'Approve for me'},
          {'value': 'agent-full-access', 'name': 'Full access'},
        ],
      },
    {
      'id': 'engine',
      'name': 'Model',
      'category': 'model',
      'type': 'select',
      'currentValue': model,
      'options': [
        {'value': 'alpha', 'name': 'Alpha'},
        {'value': 'beta', 'name': 'Beta'},
      ],
    },
    {
      'id': 'thinking',
      'name': 'Effort',
      'category': 'thought_level',
      'type': 'select',
      'currentValue': effort,
      'options': [
        for (final value in model == 'alpha' ? ['low'] : ['low', 'high'])
          {'value': value, 'name': value},
      ],
    },
    if (model == 'beta')
      {
        'id': 'quick',
        'name': 'Fast mode',
        'type': 'boolean',
        'currentValue': fast,
      },
  ];
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map;
    await log.writeAsString('$line\n', mode: FileMode.append);
    if (request['id'] == null) continue;
    if (request['id'] == 'permission-1' && request['method'] == null) {
      stdout.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': permissionPromptId,
          'result': {'stopReason': 'end_turn'},
        }),
      );
      continue;
    }
    final params = request['params'] as Map;
    Object result;
    switch (request['method']) {
      case 'initialize':
        result = {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': !args.contains('no-session-load'),
            'promptCapabilities': {'image': args.contains('images')},
          },
        };
      case 'session/new':
      case 'session/load':
        result = {'sessionId': 'fixture-session', 'configOptions': options()};
      case 'session/set_config_option':
        switch (params['configId']) {
          case 'mode':
            if (!args.contains('ignore-approval-mode')) {
              mode = params['value'] as String;
            }
          case 'engine':
            model = params['value'] as String;
            effort = 'low';
          case 'thinking':
            effort = params['value'] as String;
          case 'quick':
            if (params['type'] != 'boolean') {
              throw StateError('Missing boolean type');
            }
            fast = params['value'] as bool;
        }
        result = {'configOptions': options()};
      case 'session/prompt':
        if (codex && mode != 'read-only') {
          throw StateError('Prompt used automatic approval');
        }
        if (args.contains('permission')) {
          permissionPromptId = request['id'];
          if (args.contains('partial-permission')) {
            for (final update in [
              {
                'sessionUpdate': 'tool_call',
                'toolCallId': 'exec-example',
                'title':
                    'mcp.careershopper_session.application_materials_submit',
                'kind': 'execute',
                'status': 'in_progress',
                'rawInput': {
                  'job_id': 'job-123',
                  'cover_letter_markdown': 'Draft cover letter',
                },
              },
              {
                'sessionUpdate': 'tool_call_update',
                'toolCallId': 'exec-example',
                'status': 'in_progress',
              },
            ]) {
              stdout.writeln(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'session/update',
                  'params': {
                    'sessionId': args.contains('foreign-tool-session')
                        ? 'other-session'
                        : 'fixture-session',
                    'update': update,
                  },
                }),
              );
            }
          }

          stdout.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'permission-1',
              'method': 'session/request_permission',
              'params': {
                'sessionId': 'fixture-session',
                'toolCall': args.contains('remembered-permission')
                    ? {
                        'toolCallId': 'mcp-1',
                        'kind': 'execute',
                        'title':
                            'mcp.careershopper_session.application_materials_submit',
                        '_meta': {'is_mcp_tool_call': true},
                        'rawInput': {
                          'server': 'careershopper_session',
                          'tool': 'application_materials_submit',
                          'arguments': {'job_id': params['prompt'].toString()},
                        },
                      }
                    : args.contains('partial-permission')
                    ? {
                        'toolCallId': 'exec-example',
                        'kind': 'execute',
                        'status': 'pending',
                        if (args.contains('override-input'))
                          'rawInput': {'job_id': 'updated-job'},
                      }
                    : {
                        'title': 'Execute command in careershopper for job-123',
                        'kind': 'execute',
                        'rawInput': {'command': 'touch /tmp/example'},
                      },
                'options': [
                  {
                    'optionId': 'allow-this',
                    'kind': 'allow_once',
                    'name': 'Allow once',
                  },
                  {
                    'optionId': 'deny-this',
                    'kind': 'reject_once',
                    'name': 'Deny',
                  },
                  {
                    'optionId': args.contains('remembered-permission')
                        ? 'allow_always'
                        : 'allow-all',
                    'kind': 'allow_always',
                    'name': 'Always allow',
                  },
                ],
              },
            }),
          );
          continue;
        }
        // An unsolicited update must also replace the full option list.
        effort = 'low';
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': 'fixture-session',
              'update': {
                'sessionUpdate': 'config_option_update',
                'configOptions': options(),
              },
            },
          }),
        );
        result = {'stopReason': 'end_turn'};
      default:
        throw StateError('Unexpected method ${request['method']}');
    }
    stdout.writeln(
      jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'result': result}),
    );
  }
}
