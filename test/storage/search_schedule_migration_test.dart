import 'dart:io';

import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'v17 splits sources and preserves history, matches, and saved settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'search-schedule-migration-',
      );
      final file = File('${directory.path}/database.sqlite');
      var database = CareerShopperDatabase(NativeDatabase(file));
      final now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      );
      try {
        final configuration = ConfigurationRepository(
          database,
          JobRepository(database),
          httpClient: MockClient(
            (_) async => http.Response(
              '{"jobs":[{"id":42,"title":"Engineer","location":{"name":"Remote"},'
              '"content":"Build APIs.","absolute_url":"https://example.test/jobs/42"}]}',
              200,
            ),
          ),
        );
        for (final id in ['a', 'b']) {
          await configuration.saveSourceConfiguration(
            SourceConfigurationDraft(
              id: id,
              sourceFamily: 'greenhouse',
              enabled: true,
              values: {'employer_name': id, 'board_token': id},
            ),
          );
        }
        final id = await configuration.saveSavedSearch(
          const SavedSearchDraft(
            id: 'original',
            name: 'Engineering',
            enabled: true,
            pollIntervalMinutes: 720,
            scoreThreshold: 82,
            query: SavedSearchQuery(
              name: 'Engineering',
              includedTitles: ['Engineer'],
            ),
            sourceConfigIds: {'a'},
          ),
        );
        await configuration.runSavedSearch(id);
        await database.customStatement('DROP INDEX saved_search_single_source');
        await database
            .into(database.savedSearchSources)
            .insert(
              SavedSearchSourcesCompanion.insert(
                savedSearchId: id,
                sourceConfigId: 'b',
              ),
            );
        await database
            .into(database.searchRuns)
            .insert(
              SearchRunsCompanion.insert(
                id: 'b-history',
                savedSearchId: id,
                sourceConfigId: 'b',
                status: 'succeeded',
                startedAt: now,
              ),
            );
        await database
            .into(database.savedSearches)
            .insert(
              SavedSearchesCompanion.insert(
                id: 'orphan',
                name: 'Unattached',
                queryJson: '{}',
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final column in [
          'schedule_cron',
          'next_scheduled_at',
          'last_schedule_error',
        ]) {
          await database.customStatement(
            'ALTER TABLE saved_searches DROP COLUMN $column',
          );
        }
        await database.customStatement('PRAGMA user_version = 16');
        await database.close();
        database = CareerShopperDatabase(NativeDatabase(file));
        final migrated = ConfigurationRepository(
          database,
          JobRepository(database),
        );
        final searches = await migrated.watchSavedSearches().first;
        expect(searches, hasLength(3));
        final original = searches.singleWhere((s) => s.id == id);
        final split = searches.singleWhere(
          (s) => s.sourceConfigIds.contains('b'),
        );
        expect(original.sourceConfigIds, {'a'});
        for (final search in [original, split]) {
          expect(search.enabled, isTrue);
          expect(search.pollIntervalMinutes, 720);
          expect(search.scoreThreshold, 82);
          expect(search.query.includedTitles, ['Engineer']);
          expect(search.scheduleCron, isNull);
          expect(search.nextScheduledAt, isNull);
        }
        expect(searches.singleWhere((s) => s.id == 'orphan').enabled, isFalse);
        final history = await database.select(database.searchRuns).get();
        expect(history, hasLength(2));
        expect(
          history.singleWhere((r) => r.sourceConfigId == 'b').savedSearchId,
          split.id,
        );
        expect(await database.select(database.jobs).get(), hasLength(1));
        expect(
          await database.select(database.jobSearchMatches).get(),
          hasLength(2),
        );
        await expectLater(
          database
              .into(database.savedSearchSources)
              .insert(
                SavedSearchSourcesCompanion.insert(
                  savedSearchId: id,
                  sourceConfigId: 'b',
                ),
              ),
          throwsA(isA<Exception>()),
        );
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(await migrated.claimDueSearches(now), isEmpty);
        expect(
          (await migrated.watchSavedSearches().first)
              .where((s) => s.enabled)
              .every(
                (s) =>
                    s.nextScheduledAt?.toUtc() ==
                    now.add(const Duration(minutes: 720)),
              ),
          isTrue,
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
