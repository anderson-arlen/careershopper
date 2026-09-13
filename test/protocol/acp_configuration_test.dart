import 'package:careershopper/src/domain/chat_image.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:careershopper/src/protocol/acp_configuration.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File log;
  late StdioAcpAgentRunner runner;
  final fixture = File(
    'test/fixtures/configurable_acp_agent.dart',
  ).absolute.path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'careershopper-acp-test-',
    );
    log = File('${directory.path}/requests.jsonl');
    final helper = File(
      '${directory.path}/agent-plugin/bin/careershopper-agent${Platform.isWindows ? '.exe' : ''}',
    );
    await helper.parent.create(recursive: true);
    await helper.writeAsString('fixture placeholder');
    runner = StdioAcpAgentRunner(dataDirectory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  AcpRunRequest request({
    String? existing,
    bool configurationOnly = false,
    Map<String, Object> values = const {},
    AcpConfigure? configure,
  }) => AcpRunRequest(
    executable: Platform.isWindows ? 'dart.exe' : 'dart',
    arguments: [fixture, log.path],
    workOrderId: 'order',
    prompt: 'hello',
    existingSessionId: existing,
    configurationOnly: configurationOnly,
    configValues: values,
    configure: configure,
  );
  Future<List<Map>> requests() async =>
      (await log.readAsLines()).map((line) => jsonDecode(line) as Map).toList();

  for (final supportsResume in [true, false]) {
    test(
      'sequential search rebinds MCP and selects the correct prompt (resume: $supportsResume)',
      () async {
        final sessions = <String>[];
        for (final order in ['first-job', 'second-job']) {
          await runner.run(
            AcpRunRequest(
              executable: 'dart',
              arguments: [
                fixture,
                log.path,
                if (!supportsResume) 'no-session-load',
              ],
              workOrderId: order,
              prompt: 'Full workflow and applicant context instructions',
              resumedPrompt: 'Only the next job; reuse applicant context',
              existingSessionId: sessions.lastOrNull,
              allowNewSessionIfUnsupported: true,
              onSessionStarted: (id) async => sessions.add(id),
            ),
          );
        }
        expect(sessions, ['fixture-session', 'fixture-session']);
        final calls = await requests();
        final starts = calls
            .where((c) => ['session/new', 'session/load'].contains(c['method']))
            .toList();
        expect(starts.map((s) => s['method']), [
          'session/new',
          supportsResume ? 'session/load' : 'session/new',
        ]);
        for (var i = 0; i < starts.length; i++) {
          final params = starts[i]['params'] as Map;
          final server = (params['mcpServers'] as List).single as Map;
          expect(server['name'], 'careershopper_session');
          expect(
            server['env'],
            contains(
              equals({
                'name': 'CAREERSHOPPER_WORK_ORDER_ID',
                'value': i == 0 ? 'first-job' : 'second-job',
              }),
            ),
          );
        }
        final prompts = calls
            .where((c) => c['method'] == 'session/prompt')
            .map(
              (c) =>
                  (((c['params'] as Map)['prompt'] as List).single
                      as Map)['text'],
            )
            .toList();
        expect(prompts, [
          'Full workflow and applicant context instructions',
          supportsResume
              ? 'Only the next job; reuse applicant context'
              : 'Full workflow and applicant context instructions',
        ]);
      },
    );
  }

  for (final supportsImages in [false, true]) {
    test(
      'image prompts respect ACP capability (supported: $supportsImages)',
      () async {
        final image = ChatImage.fromBytes(
          await File('test/fixtures/chat-image.png').readAsBytes(),
        );
        final run = runner.run(
          AcpRunRequest(
            executable: 'dart',
            arguments: [fixture, log.path, if (supportsImages) 'images'],
            workOrderId: 'image-chat',
            prompt: 'Explain this screenshot',
            images: [image],
          ),
        );
        if (supportsImages) {
          await run;
          final prompt = (await requests()).singleWhere(
            (r) => r['method'] == 'session/prompt',
          );
          expect((prompt['params'] as Map)['prompt'], [
            {'type': 'text', 'text': 'Explain this screenshot'},
            image.toContentBlock(),
          ]);
        } else {
          await expectLater(
            run,
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('does not support image'),
              ),
            ),
          );
          expect(
            (await requests()).map((r) => r['method']),
            isNot(contains('session/prompt')),
          );
        }
      },
    );
  }

  test(
    'Codex ACP uses private storage and user approvals for new and resumed sessions',
    () async {
      final personal = await Directory('${directory.path}/personal').create();
      final isolatedRunner = StdioAcpAgentRunner(
        dataDirectory: directory,
        processEnvironment: {
          ...Platform.environment,
          'CODEX_HOME': personal.path,
        },
      );
      for (final existing in [null, 'saved-session']) {
        await isolatedRunner.run(
          AcpRunRequest(
            executable: Platform.isWindows ? 'dart.exe' : 'dart',
            arguments: [
              fixture,
              log.path,
              '@agentclientprotocol/codex-acp@1.9.0',
              'record-environment',
            ],
            workOrderId: 'storage-test',
            prompt: 'fixture-only',
            existingSessionId: existing,
            configValues: {'mode': 'agent-full-access'},
            configure: (session) async {
              final mode = session.options.singleWhere((o) => o.id == 'mode');
              expect(mode.currentValue, 'read-only');
              expect(mode.choices.map((c) => c.value), ['read-only']);
              await expectLater(
                session.setOption('mode', 'agent'),
                throwsStateError,
              );
            },
          ),
        );
      }
      final calls = await requests();
      final environments = calls
          .where((c) => c['method'] == 'fixture/environment')
          .toList();
      expect(environments, hasLength(2));
      for (final value in environments) {
        expect(value['home'], '${directory.path}/codex-home');
        expect(value['sqlite'], value['home']);
        expect(value['initialMode'], 'read-only');
        expect(jsonDecode(value['config'])['approvals_reviewer'], 'user');
      }
      expect(calls.where((c) => c['method'] == 'session/new'), hasLength(1));
      expect(calls.where((c) => c['method'] == 'session/load'), hasLength(1));
      expect(await personal.list().toList(), isEmpty);
    },
  );

  for (final failure in ['missing-approval-mode', 'ignore-approval-mode']) {
    test('Codex cannot prompt if user approval mode is $failure', () async {
      await expectLater(
        runner.run(
          AcpRunRequest(
            executable: 'dart',
            arguments: [
              fixture,
              log.path,
              '@agentclientprotocol/codex-acp@1.9.0',
              failure,
            ],
            workOrderId: 'approval-test',
            prompt: 'must not execute',
          ),
        ),
        throwsStateError,
      );
      expect(
        (await requests()).any((c) => c['method'] == 'session/prompt'),
        false,
      );
    });
  }

  test(
    'answer writer inherits recursion guard and receives restricted MCP mode',
    () async {
      await runner.run(
        AcpRunRequest(
          executable: Platform.isWindows ? 'dart.exe' : 'dart',
          arguments: [fixture, log.path],
          workOrderId: 'essay',
          prompt: 'question',
          answerWriter: true,
          configValues: {'engine': 'beta', 'thinking': 'high'},
        ),
      );
      final calls = await requests();
      final session = calls.firstWhere(
        (call) => call['method'] == 'session/new',
      );
      final server =
          ((session['params'] as Map)['mcpServers'] as List).single as Map;
      expect(
        server['env'],
        contains(equals({'name': 'CAREERSHOPPER_ANSWER_WRITER', 'value': '1'})),
      );
      expect(
        server['env'],
        contains(
          equals({'name': 'CAREERSHOPPER_WORK_ORDER_ID', 'value': 'essay'}),
        ),
      );
    },
  );

  test(
    'recruiting reviewer starts a new isolated context without MCP servers',
    () async {
      for (final previousSession in [null, 'previous-review-or-writer']) {
        await runner.run(
          AcpRunRequest(
            executable: Platform.isWindows ? 'dart.exe' : 'dart',
            arguments: [fixture, log.path],
            workOrderId: 'screen',
            prompt: 'Review supplied documents',
            recruitingReviewer: true,
            existingSessionId: previousSession,
          ),
        );
      }
      final calls = await requests();
      final sessions = calls
          .where((c) => c['method'] == 'session/new')
          .map((c) => c['params'] as Map)
          .toList();
      expect(sessions, hasLength(2));
      for (final session in sessions) {
        expect(session['mcpServers'], isEmpty);
        expect(session['cwd'], contains('careershopper-review-'));
        expect(await Directory(session['cwd'] as String).exists(), false);
      }
      expect(sessions.map((s) => s['cwd']).toSet(), hasLength(2));
      expect(calls.any((c) => c['method'] == 'session/load'), false);
    },
  );

  test(
    'permission protocol waits for the user and returns only their selected option',
    () async {
      final shown = Completer<Map<String, Object?>>();
      final choice = Completer<String?>();
      final approvingRunner = StdioAcpAgentRunner(
        dataDirectory: directory,
        permissionPrompt: (params, _) {
          shown.complete(params);
          return choice.future;
        },
      );
      final run = approvingRunner.run(
        AcpRunRequest(
          executable: 'dart',
          arguments: [fixture, log.path, 'permission'],
          workOrderId: 'job-123',
          prompt: 'Draft materials',
          permissionContext: 'Writer: Engineer at Example',
        ),
      );
      final pending = await shown.future;
      expect(pending['conversationTitle'], 'Writer: Engineer at Example');
      expect((await requests()).any((r) => r['id'] == 'permission-1'), false);
      choice.complete('allow-this');
      await run;
      final response = (await requests()).singleWhere(
        (r) => r['id'] == 'permission-1',
      );
      expect(response['result'], {
        'outcome': {'outcome': 'selected', 'optionId': 'allow-this'},
      });
    },
  );

  for (final overrideInput in [false, true]) {
    test(
      'partial permission events recover the same tool details and preserve current input ($overrideInput)',
      () async {
        Map<String, Object?>? shown;
        final activity = <Map<String, Object?>>[];
        final approving = StdioAcpAgentRunner(
          dataDirectory: directory,
          permissionPrompt: (params, _) async {
            shown = params;
            return 'allow-all';
          },
        );
        await approving.run(
          AcpRunRequest(
            executable: 'dart',
            arguments: [
              fixture,
              log.path,
              'permission',
              'partial-permission',
              if (overrideInput) 'override-input',
            ],
            workOrderId: 'writer',
            prompt: 'Draft materials',
            onSessionUpdate: (params, _) async {
              activity.add(params);
            },
          ),
        );
        final tool = shown!['toolCall'] as Map;
        expect(
          tool['title'],
          'mcp.careershopper_session.application_materials_submit',
        );
        expect(tool['status'], 'pending');
        expect(
          (tool['rawInput'] as Map)['job_id'],
          overrideInput ? 'updated-job' : 'job-123',
        );
        if (overrideInput) {
          expect(
            (tool['rawInput'] as Map).containsKey('cover_letter_markdown'),
            false,
          );
        }
        expect(
          activity.any(
            (p) =>
                (p['update'] as Map)['title'] ==
                'Always allowed: mcp.careershopper_session.application_materials_submit',
          ),
          true,
        );
        final response = (await requests()).singleWhere(
          (r) => r['id'] == 'permission-1',
        );
        expect(response['result'], {
          'outcome': {'outcome': 'selected', 'optionId': 'allow-all'},
        });
      },
    );
  }

  test(
    'permission context is never taken from another session with the same tool ID',
    () async {
      final approving = StdioAcpAgentRunner(
        dataDirectory: directory,
        permissionPrompt: (params, _) async {
          final tool = params['toolCall'] as Map;
          expect(tool['title'], isNull);
          expect(tool['rawInput'], isNull);
          return 'deny-this';
        },
      );
      await approving.run(
        AcpRunRequest(
          executable: 'dart',
          arguments: [
            fixture,
            log.path,
            'permission',
            'partial-permission',
            'foreign-tool-session',
          ],
          workOrderId: 'writer',
          prompt: 'Draft materials',
        ),
      );
    },
  );

  test(
    'Always allow survives a fresh adapter and runner for the same MCP tool',
    () async {
      var prompts = 0;
      for (var attempt = 0; attempt < 2; attempt++) {
        final freshRunner = StdioAcpAgentRunner(
          dataDirectory: directory,
          permissionPrompt: (_, _) async {
            prompts++;
            return 'allow_always';
          },
        );
        await freshRunner.run(
          AcpRunRequest(
            executable: 'dart',
            arguments: [
              fixture,
              log.path,
              'permission',
              'remembered-permission',
              '@agentclientprotocol/codex-acp@1.9.0',
            ],
            workOrderId: 'job-$attempt',
            prompt: 'Save different draft $attempt',
          ),
        );
      }
      expect(prompts, 1);
      final replies = (await requests())
          .where((r) => r['id'] == 'permission-1')
          .toList();
      expect((replies[0]['result'] as Map)['outcome'], {
        'outcome': 'selected',
        'optionId': 'allow_always',
      });
      expect((replies[1]['result'] as Map)['outcome'], {
        'outcome': 'selected',
        'optionId': 'allow-this',
      });
    },
  );

  test('headless ACP never auto-approves a matching title', () async {
    await expectLater(
      runner.run(
        AcpRunRequest(
          executable: 'dart',
          arguments: [fixture, log.path, 'permission'],
          workOrderId: 'job-123',
          prompt: 'Draft materials',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('no interactive approval prompt'),
        ),
      ),
    );
    expect((await requests()).where((r) => r['id'] == 'permission-1'), isEmpty);
  });

  for (final existing in [null, 'fixture-session']) {
    test(
      'applies model before dependent choices before prompting ($existing)',
      () async {
        AcpConfigurationSession? session;
        await runner.run(
          request(
            existing: existing,
            values: {'thinking': 'high', 'quick': true, 'engine': 'beta'},
            configure: (value) async {
              session = value;
            },
          ),
        );
        final calls = await requests();
        expect((calls.first['params'] as Map)['clientCapabilities'], {
          'session': {
            'configOptions': {'boolean': {}},
          },
        });
        final methods = calls.map((call) => call['method']).toList();
        expect(
          methods,
          contains(existing == null ? 'session/new' : 'session/load'),
        );
        final changes = calls
            .where((call) => call['method'] == 'session/set_config_option')
            .toList();
        expect((changes.first['params'] as Map)['configId'], 'engine');
        expect(
          changes.map((call) => (call['params'] as Map)['value']),
          containsAll(['beta', 'high', true]),
        );
        expect(methods.last, 'session/prompt');
        expect(
          session!.options.firstWhere((o) => o.id == 'thinking').currentValue,
          'low',
        );
      },
    );
  }

  test(
    'settings discovery does not prompt and recovers unsupported saved choices',
    () async {
      await runner.run(
        request(
          configurationOnly: true,
          values: {'engine': 'removed'},
          configure: (session) async {
            expect(session.warnings, isNotEmpty);
            await session.setOption('engine', 'beta');
            expect(session.options.any((o) => o.id == 'quick'), isTrue);
            await session.setOption('quick', true);
          },
        ),
      );
      expect(
        (await requests()).map((call) => call['method']),
        isNot(contains('session/prompt')),
      );
    },
  );

  test('invalid saved settings prevent prompting', () async {
    await expectLater(
      runner.run(request(values: {'engine': 'removed'})),
      throwsStateError,
    );
    expect(
      (await requests()).map((call) => call['method']),
      isNot(contains('session/prompt')),
    );
  });

  test('parses grouped options and skips unsupported control types', () {
    final options = AcpConfigOption.parse([
      {
        'id': 'model',
        'name': 'Model',
        'category': '_custom',
        'type': 'select',
        'currentValue': 'a',
        'options': [
          {
            'group': 'vendor',
            'name': 'Vendor',
            'options': [
              {'value': 'a', 'name': 'A'},
            ],
          },
        ],
      },
      {'id': 'future', 'name': 'Future', 'type': 'slider', 'currentValue': 3},
    ]);
    expect(options, hasLength(1));
    expect(options.single.choices.single.group, 'Vendor');
    expect(options.single.accepts('a'), isTrue);
    expect(options.single.accepts('other'), isFalse);
  });
}
