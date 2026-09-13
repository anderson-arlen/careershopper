import 'package:careershopper/src/domain/job.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/listing_availability_service.dart';
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
    'MCP configures LinkedIn page limits and preserves them on edits',
    () async {
      Map<String, Object?> upsert(Map<String, Object?> arguments) => {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'source_config_upsert', 'arguments': arguments},
      };
      final created = await _exchange(database, [
        upsert({'source_family': 'linkedin', 'max_pages': 5}),
      ]);
      final id =
          (((created.single['result'] as Map)['structuredContent'])
              as Map)['id'];
      final edited = await _exchange(database, [
        upsert({'id': id, 'source_family': 'linkedin', 'enabled': false}),
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {'name': 'source_configs_list'},
        },
      ]);
      final sources =
          ((edited.last['result'] as Map)['structuredContent']
                  as Map)['source_configs']
              as List;
      expect(sources.single['max_pages'], 5);
      for (final value in [0, 101, 1.5, '2', null]) {
        final rejected = await _exchange(database, [
          upsert({'id': id, 'source_family': 'linkedin', 'max_pages': value}),
        ]);
        expect(rejected.single, contains('error'));
      }
      final row = await database.select(database.sourceConfigs).getSingle();
      expect(jsonDecode(row.configJson)['max_pages'], 5);
      final other = await _exchange(database, [
        upsert({'source_family': 'indeed', 'max_pages': 5}),
      ]);
      expect(other.single, contains('error'));
    },
  );

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

  test(
    'posting fetch requires confirmation and work-order scope before HTTP',
    () async {
      final jobs = JobRepository(database);
      final id = await jobs.queueManualUrl(
        Uri.parse('https://www.linkedin.com/jobs/view/42'),
      );
      var calls = 0;
      final listings = ListingAvailabilityService(
        database,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response(
            '<main><h1>Engineer</h1><p>Build APIs.</p></main>',
            200,
          );
        }),
      );
      Map<String, Object?> request(bool confirmed) => {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'job_posting_fetch',
          'arguments': {'job_id': id, 'confirmed': confirmed},
        },
      };
      final unconfirmed = await _exchange(database, [
        request(false),
      ], listings: listings);
      expect(unconfirmed.single, contains('error'));
      expect(calls, 0);
      final outside = await _exchange(
        database,
        [request(true)],
        listings: listings,
        workOrderId: 'other-order',
      );
      expect((outside.single['error'] as Map)['message'], contains('outside'));
      expect(calls, 0);
      final success = await _exchange(database, [
        request(true),
      ], listings: listings);
      expect((success.single['result'] as Map)['isError'], false);
      final content =
          (success.single['result'] as Map)['structuredContent'] as Map;
      expect(content['text'], 'Engineer\nBuild APIs.');
      expect(content['source_url'], 'https://www.linkedin.com/jobs/view/42');
      expect(calls, 1);
      final read = await _exchange(database, [
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'job_get',
            'arguments': {'job_id': id},
          },
        },
      ]);
      expect(
        (((read.single['result'] as Map)['structuredContent'] as Map)['job']
            as Map)['source_family'],
        'manual',
      );
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
        'job_posting_fetch',
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
    expect(
      evaluationTool['description'],
      contains(
        'personal_fit_score and attainability_score as integers from 0 through 100',
      ),
    );
    expect(
      evaluationTool['description'],
      contains('confidence as a number from 0 through 1 inclusive'),
    );
    final evaluationSchema = evaluationTool['inputSchema']! as Map;
    final evaluationProperties = evaluationSchema['properties']! as Map;
    final confidenceSchema = evaluationProperties['confidence']! as Map;
    expect(confidenceSchema['type'], 'number');
    expect(confidenceSchema['minimum'], 0);
    expect(confidenceSchema['maximum'], 1);
    expect(
      confidenceSchema['description'],
      contains('for 78% confidence, use 0.78, not 78'),
    );
    final searchTool = tools.whereType<Map<String, Object?>>().singleWhere(
      (tool) => tool['name'] == 'saved_search_upsert',
    );
    final searchProperties =
        (searchTool['inputSchema'] as Map)['properties'] as Map;
    expect((searchProperties['source_config_ids'] as Map)['minItems'], 1);
    expect((searchProperties['source_config_ids'] as Map)['maxItems'], 1);
    expect(searchProperties, contains('schedule_cron'));
    for (final tool in tools.whereType<Map<String, Object?>>()) {
      final schema = tool['inputSchema']! as Map<String, Object?>;
      expect(
        schema['additionalProperties'],
        isFalse,
        reason: '${tool['name']}',
      );
    }
  });

  test(
    'legacy fact mutations are unavailable and an empty profile requires resume content',
    () async {
      final responses = await _exchange(database, [
        for (final name in [
          'profile_facts_upsert_batch',
          'profile_fact_verification_set',
          'profile_fact_retire',
        ])
          {
            'jsonrpc': '2.0',
            'id': name,
            'method': 'tools/call',
            'params': {'name': name, 'arguments': {}},
          },
        {
          'jsonrpc': '2.0',
          'id': 'read',
          'method': 'tools/call',
          'params': {'name': 'profile_get', 'arguments': {}},
        },
      ]);
      for (final response in responses.take(3)) {
        expect(response, contains('error'));
      }
      final profile =
          (responses.last['result'] as Map)['structuredContent'] as Map;
      expect(profile['configured'], false);
      expect(profile['facts'], isEmpty);
    },
  );

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
            'schedule_cron': '0 9,17 * * 1-5',
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
    final search = searches.single as Map;
    expect(search['schedule_cron'], '0 9,17 * * 1-5');
    expect(search['schedule_timezone'], 'local');
    expect(DateTime.parse(search['next_scheduled_at'] as String).isUtc, isTrue);
    expect(search['last_schedule_error'], isNull);
    expect(responses[3]['error'], isNotNull);
  });

  test(
    'MCP preserves schedules on edit and rejects invalid source or cron changes',
    () async {
      final configuration = ConfigurationRepository(
        database,
        JobRepository(database),
      );
      final source = await configuration.saveSourceConfiguration(
        const SourceConfigurationDraft(
          sourceFamily: 'linkedin',
          enabled: true,
          values: {},
        ),
      );
      final id = await configuration.saveSavedSearch(
        SavedSearchDraft(
          name: 'Original',
          enabled: false,
          pollIntervalMinutes: 360,
          scoreThreshold: 80,
          scheduleCron: '0 9 * * *',
          query: const SavedSearchQuery(name: 'Original'),
          sourceConfigIds: {source},
        ),
      );
      final responses = await _exchange(database, [
        for (final (index, extra) in <Map<String, Object?>>[
          {},
          {'source_config_ids': []},
          {
            'source_config_ids': [source, 'other'],
          },
          {
            'source_config_ids': [source, source],
          },
          {
            'source_config_ids': ['missing'],
          },
          {'schedule_cron': '0 9 30 2 *'},
        ].indexed)
          {
            'jsonrpc': '2.0',
            'id': index + 1,
            'method': 'tools/call',
            'params': {
              'name': 'saved_search_upsert',
              'arguments': {'id': id, 'name': 'Edited', 'query': {}, ...extra},
            },
          },
      ], configuration: configuration);
      expect(responses.first, isNot(contains('error')));
      for (final response in responses.skip(1)) {
        expect((response['error'] as Map)['code'], -32602);
      }
      final saved = (await configuration.watchSavedSearches().first).single;
      expect(saved.sourceConfigIds, {source});
      expect(saved.scheduleCron, '0 9 * * *');
      expect(saved.enabled, isFalse);
      expect(saved.pollIntervalMinutes, 360);
      expect(saved.scoreThreshold, 80);
    },
  );

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

  for (final mode in ['manual', 'search_missing', 'search_saved']) {
    final searchBatch = mode != 'manual';
    final savedDescription = mode == 'search_saved';
    test('scoped evaluation completes work ($mode)', () async {
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
      if (savedDescription) {
        await jobs.ingestIntoExistingJob(
          jobId,
          NormalizedListing(
            sourceFamily: 'indeed',
            adapterId: 'indeed_public_search_v1',
            providerJobId: '42',
            title: 'Platform Engineer',
            employerName: 'Example Inc.',
            normalizedEmployerName: 'example inc.',
            location: 'Remote',
            description: 'Build reliable platforms.',
            contentHash: 'stored-description',
            sourceUrl: Uri.parse('https://www.indeed.com/viewjob?jk=42'),
            applicationUrl: Uri.parse('https://apply.example.test/jobs/42'),
            observedAt: DateTime.now().toUtc(),
          ),
        );
      }
      final snapshotsBefore = await database
          .select(database.jobSnapshots)
          .get();
      final String workOrderId;
      if (searchBatch) {
        expect(await harnesses.dispatchSearchAnalysis([jobId]), 1);
        workOrderId =
            (await database.select(database.aiWorkOrders).getSingle()).id;
      } else {
        workOrderId = (await harnesses.dispatchManualImport(jobId)).workOrderId;
      }

      final responses = await _exchange(
        database,
        [
          if (!savedDescription)
            {
              'jsonrpc': '2.0',
              'id': 0,
              'method': 'tools/call',
              'params': {
                'name': 'job_posting_fetch',
                'arguments': {'job_id': jobId, 'confirmed': true},
              },
            },
          if (!savedDescription)
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
        ],
        workOrderId: workOrderId,
        listings: ListingAvailabilityService(
          database,
          clientFactory: () => MockClient((request) async {
            expect(
              savedDescription,
              false,
              reason: 'Complete saved descriptions do not need retrieval.',
            );
            expect(
              request.url.toString(),
              'https://jobs.example.test/roles/42',
            );
            return http.Response('<main>Build reliable platforms.</main>', 200);
          }),
        ),
      );

      expect(responses, everyElement(isNot(contains('error'))));
      expect(
        responses.map((response) => (response['result'] as Map)['isError']),
        everyElement(false),
      );
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
      if (savedDescription) {
        final snapshotsAfter = await database
            .select(database.jobSnapshots)
            .get();
        expect(
          snapshotsAfter.map((s) => s.id),
          snapshotsBefore.map((s) => s.id),
        );
        expect(storedJobs.single.currentSnapshotId, snapshotsBefore.last.id);
      }
      expect(
        identityKeys.map((key) => key.keyValue),
        containsAll([
          'https://apply.example.test/jobs/42',
          savedDescription ? 'indeed::42' : 'example_ats::42',
        ]),
      );
      final states = StreamIterator(harnesses.watchConversations());
      await states.moveNext();
      runner.pending.complete();
      await states.moveNext();
      await states.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
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
  ListingAvailabilityService? listings,
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
    listings: listings,
  ).serve(input: input, output: output);
  await output.close();
  return responseFuture;
}
