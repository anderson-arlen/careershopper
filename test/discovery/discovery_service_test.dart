import 'dart:convert';

import 'package:careershopper/src/discovery/discovery_service.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late JobRepository jobs;

  setUp(() async {
    database = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(database);
    await database
        .into(database.savedSearches)
        .insert(
          SavedSearchesCompanion.insert(
            id: 'search-1',
            name: 'Backend',
            queryJson: '{}',
            createdAt: DateTime.utc(2026, 9, 4),
            updatedAt: DateTime.utc(2026, 9, 4),
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'all provider results are AI candidates despite residual title and keyword mismatches',
    () async {
      final result = await DiscoveryService(jobs).run(
        adapter: _FixtureAdapter(),
        config: const SourceConfig({}),
        savedSearchId: 'search-1',
        search: const SavedSearchQuery(
          name: 'Backend',
          includedTitles: ['backend'],
          includedKeywords: ['Node.js'],
        ),
        startedAt: DateTime.utc(2026, 9, 4),
      );

      expect(result.observations, 2);
      expect(result.createdJobs, 2);
      expect(result.aiCandidates, 2);
      expect(result.filteredBySearch, 0);
      expect(await jobs.watchAllJobs().first, hasLength(2));
      final stored = await database.select(database.jobs).get();
      expect(
        stored.map((job) => job.reviewState),
        everyElement('pending_evaluation'),
      );
    },
  );
  test(
    'repeated snippets preserve hydrated evaluations; changes need analysis',
    () async {
      Future<DiscoveryRunResult> run([String version = '1']) =>
          DiscoveryService(jobs).run(
            adapter: _FixtureAdapter(version: version),
            config: const SourceConfig({}),
            savedSearchId: 'search-1',
            search: const SavedSearchQuery(
              name: 'Backend',
              includedTitles: ['backend'],
            ),
          );
      final first = await run();
      final id = first.candidateJobIds.first;
      final otherId = first.candidateJobIds.last;
      await database.customStatement(
        "UPDATE jobs SET current_evaluation_id = 'other-evaluation' WHERE id = ?",
        [otherId],
      );
      final full = _FixtureAdapter(
        version: 'full',
        adapterId: 'manual',
      ).normalize({'id': '1', 'title': 'Backend Engineer'});
      await jobs.ingestIntoExistingJob(id, full);
      await database.customStatement(
        'UPDATE jobs SET current_evaluation_id = ?, review_state = ? WHERE id = ?',
        ['evaluation', 'inbox', id],
      );
      final snapshot = (await database.select(database.jobs).get())
          .firstWhere((j) => j.id == id)
          .currentSnapshotId;
      final repeat = await run();
      expect(repeat.createdJobs, 0);
      expect(repeat.candidateJobIds, isEmpty);
      final stored = (await database.select(database.jobs).get()).firstWhere(
        (j) => j.id == id,
      );
      expect(stored.currentSnapshotId, snapshot);
      expect(stored.currentEvaluationId, 'evaluation');
      expect((await run('2')).candidateJobIds, unorderedEquals([id, otherId]));
      for (final state in ['approved', 'discarded']) {
        await database.customStatement(
          'UPDATE jobs SET review_state = ? WHERE id = ?',
          [state, id],
        );
        expect(await jobs.searchAnalysisCandidates([id]), isEmpty);
      }
      await database.customStatement(
        "UPDATE jobs SET review_state = 'hidden_by_search' WHERE id = ?",
        [id],
      );
      expect(await jobs.searchAnalysisCandidates([id]), [id]);
      await database.customStatement('UPDATE employers SET blocked_at = 1');
      expect(await jobs.searchAnalysisCandidates([id]), isEmpty);
    },
  );
}

class _FixtureAdapter implements JobSourceAdapter {
  _FixtureAdapter({this.version = '1', this.adapterId = 'fixture_v1'});
  final String version;
  final String adapterId;
  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) =>
      QueryPlan(remoteParameters: const {}, residualQuery: search);

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'fixture',
    adapterId: 'fixture_v1',
    displayName: 'Fixture',
    capabilities: {},
    minimumPollInterval: Duration(hours: 1),
    policyTier: SourcePolicyTier.publicApi,
  );

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    yield const RawSourcePage(
      records: [
        {'id': '1', 'title': 'Backend Engineer'},
        {'id': '2', 'title': 'Sales Engineer'},
      ],
    );
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final id = record['id']! as String;
    final title = record['title']! as String;
    return NormalizedListing(
      sourceFamily: 'fixture',
      adapterId: adapterId,
      providerJobId: id,
      title: title,
      employerName: 'Example',
      normalizedEmployerName: 'example',
      location: '',
      description: 'Description $id $version',
      rawPayloadJson: jsonEncode({...record, 'version': version}),
      contentHash: 'hash-$id-$version',
      sourceUrl: Uri.parse('https://example.com/jobs/$id'),
      applicationUrl: Uri.parse('https://example.com/jobs/$id/apply'),
      observedAt: DateTime.utc(2026, 9, 4),
    );
  }

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async =>
      const SourceConfigCheck(valid: true);
}
