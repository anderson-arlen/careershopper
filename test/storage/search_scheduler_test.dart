import 'dart:async';

import 'package:careershopper/src/discovery/search_scheduler.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late CareerShopperDatabase database;
  late ConfigurationRepository configuration;
  late _Harness harness;
  late SearchScheduler scheduler;
  late String source;
  late int requests;
  final now = DateTime(2026, 9, 12, 10).toUtc();

  setUp(() async {
    requests = 0;
    database = CareerShopperDatabase(NativeDatabase.memory());
    configuration = ConfigurationRepository(
      database,
      JobRepository(database),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          '{"jobs":[{"id":42,"title":"Engineer",'
          '"location":{"name":"Remote"},"content":"Build APIs.",'
          '"absolute_url":"https://example.test/jobs/42"}]}',
          200,
        );
      }),
    );
    source = await configuration.saveSourceConfiguration(
      const SourceConfigurationDraft(
        sourceFamily: 'greenhouse',
        enabled: true,
        values: {'employer_name': 'Example', 'board_token': 'example'},
      ),
    );
    harness = _Harness();
    scheduler = SearchScheduler(configuration, harness);
  });
  tearDown(() async {
    scheduler.stop();
    await database.close();
  });

  Future<String> search({
    bool enabled = true,
    String? cron = '0 9 * * *',
    Set<String>? sources,
  }) => configuration.saveSavedSearch(
    SavedSearchDraft(
      name: 'Engineering',
      enabled: enabled,
      pollIntervalMinutes: 120,
      scheduleCron: cron,
      scoreThreshold: 70,
      query: const SavedSearchQuery(name: 'Engineering'),
      sourceConfigIds: sources ?? {source},
    ),
  );

  Future<void> due(String id, DateTime at) =>
      (database.update(database.savedSearches)..where((r) => r.id.equals(id)))
          .write(SavedSearchesCompanion(nextScheduledAt: Value(at)));

  test(
    'requires exactly one existing source without partially saving',
    () async {
      for (final sources in [
        <String>{},
        {source, 'other'},
        {'missing'},
      ]) {
        await expectLater(search(sources: sources), throwsArgumentError);
      }
      expect(await database.select(database.savedSearches).get(), isEmpty);
      await expectLater(search(cron: '0 9 30 2 *'), throwsArgumentError);
    },
  );

  test(
    'overdue run executes once, advances schedule, and dispatches candidates',
    () async {
      final id = await search();
      await due(id, now.subtract(const Duration(days: 3)));
      await scheduler.tick(now: now);
      await scheduler.tick(now: now);
      expect(requests, 1);
      expect(harness.analyzed, hasLength(1));
      final row = await database.select(database.savedSearches).getSingle();
      expect(row.nextScheduledAt?.toUtc(), DateTime(2026, 9, 13, 9).toUtc());
      expect(row.lastScheduleError, isNull);
    },
  );

  test(
    'paused and future searches do not run; resume gets a future deadline',
    () async {
      final paused = await search(enabled: false);
      final future = await search();
      await due(future, now.add(const Duration(hours: 1)));
      await scheduler.tick(now: now);
      expect(requests, 0);
      await configuration.setSavedSearchEnabled(paused, true);
      expect(
        (await configuration.watchSavedSearches().first)
            .singleWhere((s) => s.id == paused)
            .nextScheduledAt,
        isNotNull,
      );
      await configuration.setSavedSearchEnabled(paused, false);
      expect(
        (await configuration.watchSavedSearches().first)
            .singleWhere((s) => s.id == paused)
            .nextScheduledAt,
        isNull,
      );
    },
  );

  test(
    'intervals survive legacy initialization and concurrent claims',
    () async {
      final id = await search(cron: null);
      await (database.update(database.savedSearches)
            ..where((r) => r.id.equals(id)))
          .write(const SavedSearchesCompanion(nextScheduledAt: Value(null)));
      expect(await configuration.claimDueSearches(now), isEmpty);
      final later = now.add(const Duration(hours: 2));
      final claims = await Future.wait([
        configuration.claimDueSearches(later),
        configuration.claimDueSearches(later),
      ]);
      expect(claims.expand((ids) => ids), [id]);
      expect(
        (await database.select(database.savedSearches).getSingle())
            .nextScheduledAt
            ?.toUtc(),
        later.add(const Duration(hours: 2)),
      );
    },
  );

  test('missing AI setup is visible and does not contact a provider', () async {
    final id = await search();
    await due(id, now);
    harness.configured = false;
    await scheduler.tick(now: now);
    expect(requests, 0);
    expect(
      (await database.select(database.savedSearches).getSingle())
          .lastScheduleError,
      contains('AI'),
    );
  });

  test('scheduled searches respect saved provider blocks', () async {
    final id = await search();
    await due(id, now);
    await database
        .into(database.sourceHealthRecords)
        .insert(
          SourceHealthRecordsCompanion.insert(
            sourceConfigId: source,
            state: const Value('unavailable'),
            updatedAt: now,
          ),
        );
    await scheduler.tick(now: now);
    expect(requests, 0);
    expect(
      (await database.select(database.searchRuns).getSingle()).status,
      'skipped',
    );
    expect(harness.analyzed, isEmpty);
  });
}

class _Harness implements AiHarnessStore {
  bool configured = true;
  final analyzed = <String>[];
  @override
  Stream<List<AiHarnessProfile>> watchProfiles() => Stream.value([
    if (configured)
      AiHarnessProfile(
        id: 'ai',
        name: 'AI',
        executable: '/bin/true',
        arguments: [],
        protocol: 'acp_stdio',
        isDefault: true,
        updatedAt: DateTime(2026),
      ),
  ]);
  @override
  Future<int> dispatchSearchAnalysis(List<String> ids) async {
    analyzed.addAll(ids);
    return ids.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
