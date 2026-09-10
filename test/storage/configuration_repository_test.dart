import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late CareerShopperDatabase database;
  late JobRepository jobs;

  setUp(() {
    database = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(database);
  });

  tearDown(() => database.close());

  test('supports multiple employer boards using the same adapter', () async {
    final repository = ConfigurationRepository(database, jobs);

    for (final employer in const ['Acme', 'Example']) {
      await repository.saveSourceConfiguration(
        SourceConfigurationDraft(
          sourceFamily: 'greenhouse',
          enabled: true,
          values: {
            'employer_name': employer,
            'board_token': employer.toLowerCase(),
          },
        ),
      );
    }

    final sources = await repository.watchSourceConfigurations().first;
    expect(sources, hasLength(2));
    expect(
      sources.map((item) => item.employerName),
      containsAll(['Acme', 'Example']),
    );
  });

  test(
    'runs a paused search without enabling it and respects backoff',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'jobs': [
              {
                'id': 42,
                'title': 'Backend Engineer',
                'location': {'name': 'Remote, US'},
                'content': '<p>Build reliable APIs.</p>',
                'absolute_url': 'https://boards.greenhouse.io/acme/jobs/42',
                'updated_at': '2026-09-04T12:00:00Z',
              },
            ],
          }),
          200,
        ),
      );
      final repository = ConfigurationRepository(
        database,
        jobs,
        httpClient: client,
      );
      final sourceId = await repository.saveSourceConfiguration(
        const SourceConfigurationDraft(
          sourceFamily: 'greenhouse',
          enabled: true,
          values: {'employer_name': 'Acme', 'board_token': 'acme'},
        ),
      );
      final searchId = await repository.saveSavedSearch(
        SavedSearchDraft(
          name: 'Backend',
          enabled: false,
          pollIntervalMinutes: 60,
          scoreThreshold: 70,
          query: const SavedSearchQuery(
            name: 'Backend',
            includedTitles: ['Backend'],
            remoteStatuses: ['remote'],
          ),
          sourceConfigIds: {sourceId},
        ),
      );

      final saved = await repository.watchSavedSearches().first;
      expect(saved.single.sourceConfigIds, {sourceId});

      final result = await repository.runSavedSearch(searchId);
      expect(result.observations, 1);
      expect(result.createdJobs, 1);
      expect(
        (await repository.watchSavedSearches().first).single.enabled,
        isFalse,
      );
      expect(await jobs.watchAllJobs().first, hasLength(1));
      expect(
        (await database.select(database.searchRuns).get()).single.status,
        'succeeded',
      );

      final immediateRepeat = await repository.runSavedSearch(searchId);
      expect(immediateRepeat.sources.single.status, 'skipped');
    },
  );

  test(
    'upgrades a v1 database without retaining the one-adapter limit',
    () async {
      // This migration test intentionally closes and reopens one database.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'careershopper-migration-',
      );
      final file = File('${directory.path}/migration.sqlite3');
      CareerShopperDatabase? fileDatabase;
      try {
        fileDatabase = CareerShopperDatabase(NativeDatabase(file));
        await fileDatabase.select(fileDatabase.savedSearches).get();
        await fileDatabase.customStatement('PRAGMA foreign_keys = OFF');
        await fileDatabase.customStatement('PRAGMA legacy_alter_table = ON');
        await fileDatabase.customStatement(
          'ALTER TABLE source_configs RENAME TO source_configs_v2',
        );
        await fileDatabase.customStatement('''
        CREATE TABLE source_configs (
          id TEXT NOT NULL PRIMARY KEY,
          source_family TEXT NOT NULL,
          adapter_id TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
          use_fixed_proxy INTEGER NOT NULL DEFAULT 0
            CHECK (use_fixed_proxy IN (0, 1)),
          config_json TEXT NOT NULL DEFAULT '{}',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE (source_family, adapter_id)
        )
      ''');
        await fileDatabase.customStatement('DROP TABLE source_configs_v2');
        await fileDatabase.customStatement('PRAGMA user_version = 1');
        await fileDatabase.close();

        fileDatabase = CareerShopperDatabase(NativeDatabase(file));
        final fileJobs = JobRepository(fileDatabase);
        final repository = ConfigurationRepository(fileDatabase, fileJobs);
        for (final employer in const ['Acme', 'Example']) {
          await repository.saveSourceConfiguration(
            SourceConfigurationDraft(
              sourceFamily: 'greenhouse',
              enabled: true,
              values: {
                'employer_name': employer,
                'board_token': employer.toLowerCase(),
              },
            ),
          );
        }
        expect(
          await fileDatabase.select(fileDatabase.sourceConfigs).get(),
          hasLength(2),
        );
      } finally {
        await fileDatabase?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      }
    },
  );
}
