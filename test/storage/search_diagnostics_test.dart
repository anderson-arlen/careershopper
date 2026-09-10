import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late CareerShopperDatabase db;
  setUp(() => db = CareerShopperDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<(ConfigurationRepository, String, String)> setup(
    http.Client client,
  ) async {
    final repo = ConfigurationRepository(
      db,
      JobRepository(db),
      httpClient: client,
    );
    final source = await repo.saveSourceConfiguration(
      const SourceConfigurationDraft(
        sourceFamily: 'indeed',
        enabled: true,
        values: {'country_site': 'www.indeed.com'},
      ),
    );
    final search = await repo.saveSavedSearch(
      SavedSearchDraft(
        name: 'Test',
        enabled: false,
        pollIntervalMinutes: 60,
        scoreThreshold: 70,
        sourceConfigIds: {source},
        query: const SavedSearchQuery(
          name: 'Test',
          includedTitles: ['Engineer'],
        ),
      ),
    );
    return (repo, search, source);
  }

  test(
    'failed provider response and subsequent skip are persistent and readable via MCP',
    () async {
      var requests = 0;
      final (repo, id, _) = await setup(
        MockClient((_) async {
          requests++;
          return http.Response('<html>Verify you are human</html>', 403);
        }),
      );
      final result = await repo.runSavedSearch(id);
      expect(result.sources.single.status, 'failed');
      expect(result.sources.single.detail, contains('CAPTCHA'));
      final history = await repo.watchSearchRuns(savedSearchId: id).first;
      expect(history.single.diagnostics['requests'], [
        containsPair('http_status', 403),
      ]);
      final mcp = await McpUiTools(
        db,
      ).call('saved_search_runs_list', {'saved_search_id': id});
      expect(mcp['runs'], history.map((r) => r.toJson()).toList());
      final exchange =
          (history.single.diagnostics['requests'] as List).single as Map;
      expect(
        (exchange['request'] as Map)['headers'],
        containsPair('indeed-api-key', '[redacted]'),
      );
      expect(
        (exchange['response'] as Map)['body'],
        '<html>Verify you are human</html>',
      );
      final skipped = await repo.runSavedSearch(id);
      expect(skipped.sources.single.status, 'skipped');
      expect(skipped.sources.single.detail, contains('No request was sent'));
      expect(requests, 1);
      expect(await repo.watchSearchRuns(savedSearchId: id).first, hasLength(2));
      expect((await repo.watchSavedSearches().first).single.enabled, false);
      await expectLater(
        McpUiTools(db).call('saved_search_runs_list', {'limit': 0}),
        throwsFormatException,
      );
    },
  );

  test(
    'explicit block clearing preserves history and scheduling without requests',
    () async {
      var requests = 0;
      final (repo, search, source) = await setup(
        MockClient((_) async {
          requests++;
          return http.Response('Access denied', 403);
        }),
      );
      await repo.runSavedSearch(search);
      final history = await repo.watchSearchRuns(savedSearchId: search).first;
      final backoff = DateTime.utc(2099);
      await (db.update(db.sourceHealthRecords)
            ..where((r) => r.sourceConfigId.equals(source)))
          .write(SourceHealthRecordsCompanion(backoffUntil: Value(backoff)));
      await repo.setSourceConfigurationEnabled(source, false);
      final mcp = McpUiTools(db);
      await expectLater(
        mcp.call('source_block_clear', {'source_config_id': source}),
        throwsFormatException,
      );
      await expectLater(
        mcp.call('source_block_clear', {
          'source_config_id': source,
          'confirmed': true,
        }, workOrderId: 'scoped'),
        throwsStateError,
      );
      expect(
        (await repo.watchSourceConfigurations().first).single.healthState,
        'unavailable',
      );
      expect(
        await mcp.call('source_block_clear', {
          'source_config_id': source,
          'confirmed': true,
        }),
        {'source_config_id': source, 'cleared': true},
      );
      final health = (await repo.watchSourceConfigurations().first).single;
      expect(health.healthState, 'not_checked');
      expect(health.healthDetail, isNull);
      expect(health.backoffUntil?.toUtc(), backoff);
      expect(health.enabled, false);
      expect((await repo.watchSavedSearches().first).single.enabled, false);
      expect(
        (await repo.watchSearchRuns(savedSearchId: search).first)
            .map((r) => r.toJson())
            .toList(),
        history.map((r) => r.toJson()).toList(),
      );
      expect(requests, 1);
      expect(await repo.clearSourceBlock(source), false);
      await expectLater(repo.clearSourceBlock('missing'), throwsArgumentError);
      final audit = await (db.select(
        db.auditEvents,
      )..where((r) => r.eventType.equals('source_block_cleared'))).get();
      expect(audit, hasLength(1));
      expect(audit.single.subjectId, source);
      expect(
        (await db.select(db.sourceHealthRecords).getSingle())
            .consecutiveFailures,
        0,
      );
    },
  );

  test(
    'reports genuine zero results, then records interval and disabled skips',
    () async {
      var requests = 0;
      final (repo, id, source) = await setup(
        MockClient((_) async {
          requests++;
          return page([]);
        }),
      );
      final result = await repo.runSavedSearch(id);
      expect(result.sources.single.status, 'succeeded');
      expect(result.sources.single.detail, 'Source returned no listings.');
      expect(result.sources.single.diagnostics['pages_read'], 1);
      expect(result.sources.single.diagnostics['ai_candidates'], 0);
      expect(
        (await repo.runSavedSearch(id)).sources.single.detail,
        contains('Minimum source interval'),
      );
      await repo.setSourceConfigurationEnabled(source, false);
      expect(
        (await repo.runSavedSearch(id)).sources.single.detail,
        contains('disabled'),
      );
      expect(requests, 1);
    },
  );

  test('Indeed first-page limit processes every returned listing', () async {
    var requests = 0;
    final (repo, id, _) = await setup(
      MockClient(
        (_) async => ++requests == 1
            ? page([
                job('one'),
                job('filtered', title: 'Sales Manager'),
              ], cursor: 'next')
            : http.Response('unavailable', 503),
      ),
    );
    final result = await repo.runSavedSearch(id);
    expect(result.sources.single.status, 'succeeded');
    expect(requests, 1);
    expect(result.observations, 2);
    expect(result.candidateJobIds, hasLength(2));
    final diagnostics = (await repo.watchSearchRuns(savedSearchId: id).first)
        .single
        .diagnostics;
    expect(diagnostics['more_results_available'], true);
    expect(diagnostics['remote_parameters'], containsPair('result_limit', 100));
    expect(diagnostics['created_jobs'], 2);
    expect(diagnostics['filtered_by_search'], 0);
    expect(diagnostics['pages_read'], 1);
    expect(diagnostics['requests'], hasLength(1));
  });

  test(
    'saves actual POST and JSON response with skipped record reasons',
    () async {
      http.Request? sent;
      final response = page([job('bad')..['employer'] = null, job('good')]);
      final (repo, id, _) = await setup(
        MockClient((request) async {
          sent = request;
          return http.Response(
            response.body,
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie': 'private-cookie',
            },
          );
        }),
      );
      final result = (await repo.runSavedSearch(id)).sources.single;
      expect(result.status, 'warning');
      expect(
        result.detail,
        contains('Search completed. 1 listing records processed; 1 skipped'),
      );
      expect(result.candidateJobIds, hasLength(1));
      final mcp = await McpUiTools(
        db,
      ).call('saved_search_runs_list', {'saved_search_id': id});
      final diagnostics =
          ((mcp['runs'] as List).single as Map)['diagnostics'] as Map;
      expect(diagnostics['normalization_errors'], [
        containsPair('record_number', 1),
      ]);
      expect(
        ((diagnostics['normalization_errors'] as List).single as Map)['reason'],
        isNotEmpty,
      );
      final exchange = (diagnostics['requests'] as List).single as Map;
      final request = exchange['request'] as Map;
      expect(request['method'], 'POST');
      expect(request['url'], sent!.url.toString());
      expect(request['body'], jsonDecode(sent!.body));
      expect((exchange['response'] as Map)['body'], jsonDecode(response.body));
      expect(
        (exchange['response'] as Map)['headers'],
        containsPair('set-cookie', '[redacted]'),
      );
      expect(jsonEncode(mcp), isNot(contains('private-cookie')));
      expect(
        jsonEncode(mcp),
        isNot(contains(sent!.headers['indeed-api-key']!)),
      );
    },
  );

  test(
    'all malformed records are a failure, not successful completion',
    () async {
      final (repo, id, _) = await setup(
        MockClient((_) async => page([job('bad')..['employer'] = null])),
      );
      final result = (await repo.runSavedSearch(id)).sources.single;
      expect(result.status, 'failed');
      expect(result.candidateJobIds, isEmpty);
      expect(result.diagnostics['normalization_errors'], hasLength(1));
    },
  );

  test('saves invalid JSON response for debugging parsing failures', () async {
    final (repo, id, _) = await setup(
      MockClient((_) async => http.Response('{broken', 200)),
    );
    final result = (await repo.runSavedSearch(id)).sources.single;
    expect(result.status, 'failed');
    final exchange = (result.diagnostics['requests'] as List).single as Map;
    expect((exchange['response'] as Map)['body'], '{broken');
  });

  test('marks oversized response capture as truncated', () async {
    const limit = 20 * 1024 * 1024;
    final (repo, id, _) = await setup(
      MockClient((_) async => http.Response('x' * (limit + 1), 200)),
    );
    final result = (await repo.runSavedSearch(id)).sources.single;
    expect(result.status, 'failed');
    final response =
        ((result.diagnostics['requests'] as List).single as Map)['response']
            as Map;
    expect(response['body_truncated'], true);
    expect((response['body'] as String).length, limit);
  });

  test('repeat discoveries are counted separately from new jobs', () async {
    final (repo, id, _) = await setup(
      MockClient((_) async => page([job('one')])),
    );
    await repo.runSavedSearch(id);
    await db
        .update(db.searchRuns)
        .write(
          SearchRunsCompanion(
            startedAt: Value(DateTime.now().subtract(const Duration(days: 1))),
          ),
        );
    final result = await repo.runSavedSearch(id);
    expect(result.createdJobs, 0);
    expect(result.sources.single.diagnostics['existing_observations'], 1);
  });

  test(
    'v12 migration retains historical runs without fabricating diagnostics',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final directory = await Directory.systemTemp.createTemp(
        'search-diagnostics-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/db.sqlite');
      var local = CareerShopperDatabase(NativeDatabase(file));
      final config = ConfigurationRepository(
        local,
        JobRepository(local),
        httpClient: MockClient((_) async => page([])),
      );
      final source = await config.saveSourceConfiguration(
        const SourceConfigurationDraft(
          sourceFamily: 'indeed',
          enabled: true,
          values: {'country_site': 'www.indeed.com'},
        ),
      );
      final search = await config.saveSavedSearch(
        SavedSearchDraft(
          name: 'Historic',
          enabled: false,
          pollIntervalMinutes: 60,
          scoreThreshold: 70,
          sourceConfigIds: {source},
          query: const SavedSearchQuery(name: 'Historic'),
        ),
      );
      await config.runSavedSearch(search);
      await local.customStatement(
        'ALTER TABLE search_runs DROP COLUMN diagnostics_json',
      );
      await local.customStatement('PRAGMA user_version = 12');
      await local.close();
      local = CareerShopperDatabase(NativeDatabase(file));
      final columns = await local
          .customSelect("PRAGMA table_info('search_runs')")
          .get();
      expect(columns.map((r) => r.data['name']), contains('diagnostics_json'));
      final historic = await local.select(local.searchRuns).getSingle();
      expect(historic.status, 'succeeded');
      expect(historic.detail, 'Source returned no listings.');
      expect(historic.diagnosticsJson, isNull);
      expect(
        (await local.customSelect('PRAGMA user_version').getSingle())
            .data['user_version'],
        local.schemaVersion,
      );
      await local.close();
    },
  );
}

http.Response page(List<Map<String, Object?>> jobs, {String? cursor}) =>
    http.Response(
      jsonEncode({
        'data': {
          'jobSearch': {
            'results': jobs.map((j) => {'job': j}).toList(),
            'pageInfo': {'nextCursor': cursor},
          },
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
Map<String, Object?> job(String id, {String title = 'Engineer'}) => {
  'key': id,
  'title': title,
  'employer': {'name': 'Example'},
  'description': {'html': '<p>Build useful products.</p>'},
  'location': {},
  'attributes': [],
};
