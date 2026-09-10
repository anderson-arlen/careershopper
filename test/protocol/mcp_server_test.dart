import 'package:careershopper/src/domain/job.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;

  setUp(() => database = CareerShopperDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test(
    'MCP search returns eligible jobs without launching an agent or enabling polling',
    () async {
      final configuration = ConfigurationRepository(
        database,
        JobRepository(database),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'jobs': [
                {
                  'id': 42,
                  'title': 'Backend Engineer',
                  'location': {'name': 'Remote'},
                  'content': '<p>Build APIs.</p>',
                  'absolute_url': 'https://example.test/42',
                },
              ],
            }),
            200,
          ),
        ),
      );
      final source = await configuration.saveSourceConfiguration(
        const SourceConfigurationDraft(
          sourceFamily: 'greenhouse',
          enabled: true,
          values: {'employer_name': 'Example', 'board_token': 'example'},
        ),
      );
      final search = await configuration.saveSavedSearch(
        SavedSearchDraft(
          name: 'Backend',
          enabled: false,
          pollIntervalMinutes: 60,
          scoreThreshold: 70,
          query: const SavedSearchQuery(name: 'Backend'),
          sourceConfigIds: {source},
        ),
      );
      final responses = await _exchange(database, [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'saved_search_run',
            'arguments': {'saved_search_id': search, 'confirmed': true},
          },
        },
      ], configuration: configuration);
      expect(responses.single, isNot(contains('error')));
      final data =
          (responses.single['result'] as Map)['structuredContent'] as Map;
      expect(data['candidate_job_ids'], [
        (await database.select(database.jobs).getSingle()).id,
      ]);
      expect(
        (await configuration.watchSavedSearches().first).single.enabled,
        isFalse,
      );
      expect(await database.select(database.aiWorkOrders).get(), isEmpty);
    },
  );

  test('serves initialize and strict tool discovery over JSONL', () async {
    final responses = await _exchange(database, [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-11-25'},
      },
      {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}},
    ]);

    expect(
      responses.first['result'],
      containsPair('protocolVersion', '2025-11-25'),
    );
    final result = responses.last['result']! as Map<String, Object?>;
    final tools = result['tools']! as List<Object?>;
    expect(
      tools.whereType<Map<String, Object?>>().map((tool) => tool['name']),
      containsAll([
        'profile_get',
        'job_import_submit',
        'employer_block_set',
        'source_config_upsert',
        'saved_search_run',
      ]),
    );
    final evaluationTool = tools.whereType<Map<String, Object?>>().singleWhere(
      (tool) => tool['name'] == 'job_evaluation_submit',
    );
    expect(
      evaluationTool['description'],
      contains(jobEvaluationScoringInstructions),
    );
    for (final tool in tools.whereType<Map<String, Object?>>()) {
      final schema = tool['inputSchema']! as Map<String, Object?>;
      expect(
        schema['additionalProperties'],
        isFalse,
        reason: '${tool['name']}',
      );
    }
  });

  test('document-derived profile facts remain pending', () async {
    final responses = await _exchange(database, [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'profile_facts_upsert_batch',
          'arguments': {
            'provenance': 'document_extraction',
            'source_label': 'resume.pdf',
            'facts': [
              {
                'kind': 'skill',
                'value': {'name': 'Dart'},
                'verification_status': 'confirmed',
              },
            ],
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'profile_get', 'arguments': {}},
      },
    ]);

    final firstResult = responses.first['result']! as Map<String, Object?>;
    final firstStructured =
        firstResult['structuredContent']! as Map<String, Object?>;
    final writtenFacts = firstStructured['facts']! as List<Object?>;
    expect(
      (writtenFacts.single as Map<String, Object?>)['verification_status'],
      'pending',
    );

    final profileResult = responses.last['result']! as Map<String, Object?>;
    final profile = profileResult['structuredContent']! as Map<String, Object?>;
    final facts = profile['facts']! as List<Object?>;
    expect(
      (facts.single as Map<String, Object?>)['verification_status'],
      'pending',
    );
  });

  test('configures and binds a source through MCP', () async {
    final responses = await _exchange(database, [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'source_config_upsert',
          'arguments': {
            'id': 'source-1',
            'source_family': 'greenhouse',
            'employer_name': 'Acme',
            'board_identifier': 'acme',
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'saved_search_upsert',
          'arguments': {
            'id': 'search-1',
            'name': 'Backend',
            'query': {
              'included_titles': ['Backend'],
            },
            'source_config_ids': ['source-1'],
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {'name': 'saved_searches_list', 'arguments': {}},
      },
      {
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'saved_search_run',
          'arguments': {'saved_search_id': 'search-1', 'confirmed': false},
        },
      },
    ]);

    final listResult = responses[2]['result']! as Map<String, Object?>;
    final structured = listResult['structuredContent']! as Map<String, Object?>;
    final searches = structured['saved_searches']! as List<Object?>;
    expect((searches.single as Map<String, Object?>)['source_config_ids'], [
      'source-1',
    ]);
    expect(responses[3]['error'], isNotNull);
  });

  test('stores AI-maintained career preferences for search strategy', () async {
    final responses = await _exchange(database, [
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'profile_preferences_upsert',
          'arguments': {
            'preferences': [
              {
                'key': 'preferred_workplace',
                'value': ['remote', 'hybrid'],
              },
              {'key': 'minimum_compensation', 'value': 150000},
            ],
          },
        },
      },
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {'name': 'profile_get', 'arguments': {}},
      },
    ]);

    final profileResult = responses.last['result']! as Map<String, Object?>;
    final profile = profileResult['structuredContent']! as Map<String, Object?>;
    final preferences = profile['preferences']! as Map<String, Object?>;
    expect(preferences['preferred_workplace'], ['remote', 'hybrid']);
    expect(preferences['minimum_compensation'], 150000);
  });

  for (final searchBatch in [false, true]) {
    test(
      'scoped import and evaluation complete work (search batch: $searchBatch)',
      () async {
        final jobs = JobRepository(database);
        final runner = _PendingAcpRunner();
        final harnesses = AiHarnessRepository(database, runner: runner);
        await harnesses.saveProfile(
          const AiHarnessProfileDraft(
            name: 'Test harness',
            executable: '/bin/true',
            arguments: ['--acp'],
          ),
        );
        final jobId = await jobs.queueManualUrl(
          Uri.parse('https://jobs.example.test/roles/42'),
        );
        final String workOrderId;
        if (searchBatch) {
          expect(await harnesses.dispatchSearchAnalysis([jobId]), 1);
          workOrderId =
              (await database.select(database.aiWorkOrders).getSingle()).id;
        } else {
          workOrderId = (await harnesses.dispatchManualImport(
            jobId,
          )).workOrderId;
        }

        final responses = await _exchange(database, [
          {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
              'name': 'job_import_submit',
              'arguments': {
                'job_id': jobId,
                'source_url': 'https://jobs.example.test/roles/42',
                'application_url': 'https://apply.example.test/jobs/42',
                'source_family': 'example_ats',
                'provider_job_id': '42',
                'title': 'Platform Engineer',
                'employer_name': 'Example Inc.',
                'location': 'Remote',
                'description': 'Build reliable platforms.',
              },
            },
          },
          {
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'job_evaluation_submit',
              'arguments': {
                'job_id': jobId,
                'personal_fit_score': 80,
                'attainability_score': 75,
                'confidence': 0.35,
                'summary':
                    'Matches the stated work; the complete posting is brief.',
                'strengths': ['Relevant platform experience'],
                'concerns': <String>[],
                'unknowns': ['Detailed technology stack not specified'],
              },
            },
          },
        ], workOrderId: workOrderId);

        expect(responses, everyElement(isNot(contains('error'))));
        final order = await database.select(database.aiWorkOrders).getSingle();
        final item = await database.select(database.aiWorkItems).getSingle();
        final storedJobs = await database.select(database.jobs).get();
        final identityKeys = await database
            .select(database.jobIdentityKeys)
            .get();
        expect(order.status, 'completed');
        expect(item.status, 'completed');
        expect(await jobs.watchInbox().first, hasLength(1));
        final evaluation = await database
            .select(database.jobEvaluations)
            .getSingle();
        expect(evaluation.confidence, 0.35);
        expect(evaluation.personalFitScore, 80);
        expect(evaluation.attainabilityScore, 75);
        expect(evaluation.overallScore, 78);
        expect(jsonDecode(evaluation.unknownsJson), [
          'Detailed technology stack not specified',
        ]);
        expect(await jobs.searchAnalysisCandidates([jobId]), isEmpty);
        expect(storedJobs, hasLength(1));
        expect(
          identityKeys.map((key) => key.keyValue),
          containsAll([
            'https://apply.example.test/jobs/42',
            'example_ats::42',
          ]),
        );
        final states = StreamIterator(harnesses.watchConversations());
        await states.moveNext();
        runner.pending.complete();
        await states.moveNext();
        await states.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
  }
}

class _PendingAcpRunner implements AcpAgentRunner {
  final Completer<void> pending = Completer<void>();

  @override
  Future<void> run(AcpRunRequest request) => pending.future;
}

Future<List<Map<String, Object?>>> _exchange(
  CareerShopperDatabase database,
  List<Map<String, Object?>> requests, {
  String? workOrderId,
  ConfigurationRepository? configuration,
}) async {
  final outputController = StreamController<List<int>>();
  final output = IOSink(outputController.sink);
  final responseFuture = outputController.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((line) => (jsonDecode(line) as Map).cast<String, Object?>())
      .toList();
  final input = Stream<List<int>>.value(
    utf8.encode('${requests.map(jsonEncode).join('\n')}\n'),
  );

  await McpServer(
    database,
    workOrderId: workOrderId,
    configuration: configuration,
  ).serve(input: input, output: output);
  await output.close();
  return responseFuture;
}
