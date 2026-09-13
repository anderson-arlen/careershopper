import 'package:careershopper/src/documents/resume_content.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/documents/application_answer_service.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/ai_agent_purpose.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/writing_style_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWriter implements AcpAgentRunner {
  AcpRunRequest? last;
  late String response;
  Completer<void>? hold;
  bool progress = false;
  @override
  Future<void> run(AcpRunRequest request) async {
    last = request;
    await hold?.future;
    if (progress) {
      await request.onSessionUpdate!({
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          '_meta': {
            'codex': {'phase': 'commentary'},
          },
          'content': {
            'type': 'text',
            'text': 'I’m checking the current confirmed applicant record.',
          },
        },
      }, false);
    }
    // Exercise chunk assembly; thinking/tool text must not become the answer.
    for (final part in [
      response.substring(0, response.length ~/ 2),
      response.substring(response.length ~/ 2),
    ]) {
      await request.onSessionUpdate!({
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          if (progress)
            '_meta': {
              'codex': {'phase': 'final_answer'},
            },
          'content': {'type': 'text', 'text': part},
        },
      }, false);
    }
  }
}

void main() {
  late CareerShopperDatabase db;
  late Directory dir;
  late WritingStyleRepository style;
  late FakeWriter runner;
  late McpUiTools tools;
  late String revision;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('careershopper-answer-');
    style = WritingStyleRepository(directory: dir);
    runner = FakeWriter();
    tools = McpUiTools(
      db,
      writingStyle: style,
      answerWriter: ApplicationAnswerService(db, runner: runner, style: style),
    );
    final now = DateTime.now();
    await db
        .into(db.aiHarnessProfiles)
        .insert(
          AiHarnessProfilesCompanion.insert(
            id: 'default',
            name: 'Configured writer',
            executable: '/configured/agent',
            argumentsJson: const Value('["--acp"]'),
            protocol: const Value('acp_stdio'),
            configValuesJson: const Value(
              '{"model":"chosen","effort":"high","fast":false}',
            ),
            isDefault: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await ProfileRepository(db).saveCareerFact(
      CareerFactDraft(
        kind: 'resume_content',
        value: {
          ...ResumeContent.empty(),
          'header': {'name': 'Alex', 'contact': ''},
        },
        visibility: 'resume',
      ),
      actor: 'user',
    );
    revision = (await ProfileRepository(
      db,
    ).watchCareerFacts().first).single.revisionId;
    runner.response = jsonEncode({
      'answer': 'I built reliable systems.',
      'fact_revision_ids': [revision],
    });
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<Map<String, Object?>> generate([
    Map<String, Object?> extra = const {},
  ]) => tools.call('application_answer_generate', {
    'question': 'Describe relevant experience.',
    'confirmed': true,
    ...extra,
  });

  test(
    'uses configured model and shared style, returns answer without saved history',
    () async {
      final initial = await style.read();
      await style.save(
        'Use concrete, short sentences.',
        initial['revision'] as String,
      );
      final result = await generate({
        'max_words': 10,
        'posting_text': 'Build reliable systems.',
        'previous_answer': 'Earlier answer',
        'revision_feedback': 'Shorten it',
      });
      expect(result['answer'], 'I built reliable systems.');
      expect(result['word_count'], 4);
      expect(runner.last!.executable, '/configured/agent');
      expect(runner.last!.configValues, {
        'model': 'chosen',
        'effort': 'high',
        'fast': false,
      });
      expect(runner.last!.answerWriter, true);
      expect(runner.last!.existingSessionId, isNull);
      expect(runner.last!.prompt, contains('Use concrete, short sentences.'));
      expect(runner.last!.prompt, contains('Shorten it'));
      expect(await db.select(db.aiWorkOrders).get(), isEmpty);
      expect(await db.select(db.aiWorkItems).get(), isEmpty);
      expect(await db.select(db.materialSets).get(), isEmpty);
    },
  );

  test(
    'Codex progress is excluded from a chunked successful JSON answer',
    () async {
      runner.progress = true;
      final result = await generate();
      expect(result['answer'], 'I built reliable systems.');
      expect(result['error'], isNull);
    },
  );

  test(
    'Codex progress does not hide valid missing-information details',
    () async {
      runner.progress = true;
      final error = {
        'code': 'missing_information',
        'message': 'The profile lacks testing-framework details.',
        'missing_information': [
          'Unit and integration test frameworks used for this feature',
        ],
      };
      runner.response = jsonEncode({'error': error});
      expect((await generate())['error'], error);
    },
  );

  test('essay writer uses the application writing configuration', () async {
    final harnesses = AiHarnessRepository(db);
    final writer = await harnesses.duplicateProfile('default', 'Writing');
    await db.customStatement(
      'UPDATE ai_harness_profiles SET config_values_json = ? WHERE id = ?',
      ['{"effort":"thorough"}', writer],
    );
    await harnesses.setPurposeProfile(
      AiAgentPurpose.applicationWriting,
      writer,
    );
    await generate();
    expect(runner.last!.configValues, {'effort': 'thorough'});
  });

  test(
    'requires explicit request and rejects arbitrary ACP inputs and scoped calls',
    () async {
      for (final extra in [
        <String, Object?>{'confirmed': false},
        {'job_id': 'x'},
        {'prompt': 'Run a command'},
        {'model': 'other'},
        {'executable': 'sh'},
        {'max_words': 0},
        {'question': 'x' * 12001},
      ]) {
        await expectLater(generate(extra), throwsFormatException);
      }
      await expectLater(
        tools.call('application_answer_generate', {
          'question': 'Why?',
          'confirmed': true,
        }, workOrderId: 'order'),
        throwsStateError,
      );
      expect(runner.last, isNull);
    },
  );

  test('missing information returns an MCP tool error to the caller', () async {
    runner.response = jsonEncode({
      'error': {
        'code': 'missing_information',
        'message': 'Need work authorization.',
        'missing_information': ['Are you authorized to work here?'],
      },
    });
    final response = await exchange(
      McpServer(db, uiTools: tools),
      'tools/call',
      {
        'name': 'application_answer_generate',
        'arguments': {'question': 'Can you work here?', 'confirmed': true},
      },
    );
    final result = response['result'] as Map;
    expect(result['isError'], true);
    expect(
      ((result['structuredContent'] as Map)['error'] as Map)['code'],
      'missing_information',
    );
    expect(await db.select(db.aiWorkOrders).get(), isEmpty);
  });

  test(
    'rejects unsupported claims, em dashes, excess length, malformed output',
    () async {
      for (final value in [
        {
          'answer': 'I built systems.',
          'fact_revision_ids': ['invented'],
        },
        {
          'answer': 'I built systems\u2014reliably.',
          'fact_revision_ids': [revision],
        },
        {
          'answer': '',
          'fact_revision_ids': [revision],
        },
        {
          'error': {'code': 'missing_information'},
        },
      ]) {
        runner.response = jsonEncode(value);
        expect((await generate())['error'], isNotNull);
      }
      runner.response = jsonEncode({
        'answer': 'I built reliable systems.',
        'fact_revision_ids': [revision],
      });
      expect((await generate({'max_words': 2}))['error'], isNotNull);
      expect((await generate({'max_characters': 5}))['error'], isNotNull);
    },
  );

  test('busy guard rejects recursive or overlapping calls', () async {
    runner.hold = Completer<void>();
    final first = generate();
    while (runner.last == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(((await generate())['error'] as Map)['code'], 'writer_busy');
    runner.hold!.complete();
    expect((await first)['answer'], isNotNull);
  });

  test(
    'writer server hides and rejects mutation and generation, including resource bypass',
    () async {
      await ProfileRepository(db).saveCareerFact(
        const CareerFactDraft(
          kind: 'identity',
          value: {'secret': 'private'},
          visibility: 'private',
        ),
        actor: 'user',
      );
      final server = McpServer(db, uiTools: tools, answerWriter: true);
      final list = await exchange(server, 'tools/list', {});
      expect(
        ((list['result'] as Map)['tools'] as List)
            .map((t) => (t as Map)['name'])
            .toSet(),
        {'health_get', 'profile_get'},
      );
      final profile = await exchange(server, 'tools/call', {
        'name': 'profile_get',
      });
      expect(
        (((profile['result'] as Map)['structuredContent'] as Map)['facts']
            as List),
        hasLength(1),
      );
      for (final name in [
        'application_answer_generate',
        'profile_facts_upsert_batch',
        'writing_style_update',
        'application_status_set',
      ]) {
        expect(
          await exchange(server, 'tools/call', {
            'name': name,
            'arguments': {'confirmed': true},
          }),
          contains('error'),
        );
      }
      expect(
        await exchange(server, 'resources/read', {
          'uri': 'careershopper://jobs/x',
        }),
        contains('error'),
      );
      expect(runner.last, isNull);
    },
  );

  test(
    'MCP style edit and reset use the shared file with stale-write protection',
    () async {
      final initial = await tools.call('writing_style_get', {});
      final updated = await tools.call('writing_style_update', {
        'text': 'My style',
        'expected_revision': initial['revision'],
        'confirmed': true,
      });
      expect(await style.file.readAsString(), 'My style');
      await expectLater(
        tools.call('writing_style_reset', {
          'expected_revision': initial['revision'],
          'confirmed': true,
        }),
        throwsStateError,
      );
      final reset = await tools.call('writing_style_reset', {
        'expected_revision': updated['revision'],
        'confirmed': true,
      });
      expect(reset['text'], initial['text']);
    },
  );
}

Future<Map<String, dynamic>> exchange(
  McpServer server,
  String method,
  Map<String, Object?> params,
) async {
  final controller = StreamController<List<int>>();
  final sink = IOSink(controller.sink);
  final output = controller.stream.transform(utf8.decoder).join();
  await server.serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params})}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return jsonDecode(await output) as Map<String, dynamic>;
}
