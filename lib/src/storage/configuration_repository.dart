import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../discovery/discovery_service.dart';
import '../sources/ats_adapters.dart';
import '../sources/job_source_adapter.dart';
import '../sources/search_page_adapters.dart';
import '../sources/source_http.dart';
import 'database.dart';
import 'job_repository.dart';

class SavedSearchDefinition {
  const SavedSearchDefinition({
    required this.id,
    required this.name,
    required this.enabled,
    required this.pollIntervalMinutes,
    required this.scoreThreshold,
    required this.query,
    required this.sourceConfigIds,
  });

  final String id;
  final String name;
  final bool enabled;
  final int pollIntervalMinutes;
  final int scoreThreshold;
  final SavedSearchQuery query;
  final Set<String> sourceConfigIds;
}

class SavedSearchDraft {
  const SavedSearchDraft({
    this.id,
    required this.name,
    required this.enabled,
    required this.pollIntervalMinutes,
    required this.scoreThreshold,
    required this.query,
    required this.sourceConfigIds,
  });

  final String? id;
  final String name;
  final bool enabled;
  final int pollIntervalMinutes;
  final int scoreThreshold;
  final SavedSearchQuery query;
  final Set<String> sourceConfigIds;
}

class SourceConfiguration {
  const SourceConfiguration({
    required this.id,
    required this.sourceFamily,
    required this.adapterId,
    required this.enabled,
    required this.values,
    required this.healthState,
    this.healthDetail,
    this.backoffUntil,
  });

  final String id;
  final String sourceFamily;
  final String adapterId;
  final bool enabled;
  final Map<String, Object?> values;
  final String healthState;
  final String? healthDetail;
  final DateTime? backoffUntil;

  String get employerName => values['employer_name']?.toString() ?? '';

  String get boardIdentifier => switch (sourceFamily) {
    'greenhouse' => values['board_token']?.toString() ?? '',
    'lever' => values['site']?.toString() ?? '',
    'ashby' => values['board_name']?.toString() ?? '',
    'indeed' => values['country_site']?.toString() ?? 'www.indeed.com',
    'linkedin' => 'Global public search',
    _ => '',
  };
}

class SourceConfigurationDraft {
  const SourceConfigurationDraft({
    this.id,
    required this.sourceFamily,
    required this.enabled,
    required this.values,
  });

  final String? id;
  final String sourceFamily;
  final bool enabled;
  final Map<String, Object?> values;
}

class BuiltInSourceType {
  const BuiltInSourceType({
    required this.family,
    required this.adapterId,
    required this.displayName,
    required this.identifierLabel,
    required this.identifierKey,
    required this.identifierHint,
    required this.employerRequired,
    this.defaultIdentifier,
  });

  final String family;
  final String adapterId;
  final String displayName;
  final String? identifierLabel;
  final String? identifierKey;
  final String? identifierHint;
  final bool employerRequired;
  final String? defaultIdentifier;
}

const builtInSourceTypes = <BuiltInSourceType>[
  BuiltInSourceType(
    family: 'indeed',
    adapterId: 'indeed_public_search_v1',
    displayName: 'Indeed',
    identifierLabel: 'Country site',
    identifierKey: 'country_site',
    identifierHint:
        'Supported: www.indeed.com, ca.indeed.com, uk.indeed.com, au.indeed.com',
    employerRequired: false,
    defaultIdentifier: 'www.indeed.com',
  ),
  BuiltInSourceType(
    family: 'linkedin',
    adapterId: 'linkedin_guest_search_v1',
    displayName: 'LinkedIn',
    identifierLabel: null,
    identifierKey: null,
    identifierHint: null,
    employerRequired: false,
  ),
  BuiltInSourceType(
    family: 'greenhouse',
    adapterId: 'greenhouse_job_board_v1',
    displayName: 'Greenhouse',
    identifierLabel: 'Board token',
    identifierKey: 'board_token',
    identifierHint: 'For boards.greenhouse.io/acme, enter acme',
    employerRequired: true,
  ),
  BuiltInSourceType(
    family: 'lever',
    adapterId: 'lever_postings_v1',
    displayName: 'Lever',
    identifierLabel: 'Site name',
    identifierKey: 'site',
    identifierHint: 'For jobs.lever.co/acme, enter acme',
    employerRequired: true,
  ),
  BuiltInSourceType(
    family: 'ashby',
    adapterId: 'ashby_job_board_v1',
    displayName: 'Ashby',
    identifierLabel: 'Board name',
    identifierKey: 'board_name',
    identifierHint: 'For jobs.ashbyhq.com/acme, enter acme',
    employerRequired: true,
  ),
];

class SourceRunResult {
  const SourceRunResult({
    required this.sourceName,
    required this.status,
    this.observations = 0,
    this.createdJobs = 0,
    this.candidateJobIds = const [],
    this.detail,
    this.runId,
    this.diagnostics = const {},
  });

  final String sourceName;
  final String? runId;
  final Map<String, Object?> diagnostics;
  Map<String, Object?> toJson() => {
    'run_id': runId,
    'source_name': sourceName,
    'status': status,
    'observations': observations,
    'created_jobs': createdJobs,
    'candidate_job_ids': candidateJobIds,
    'detail': detail,
    'diagnostics': diagnostics,
  };
  final String status;
  final int observations;
  final int createdJobs;
  final List<String> candidateJobIds;
  final String? detail;
}

class SearchRunRecord {
  const SearchRunRecord({
    required this.id,
    required this.savedSearchId,
    required this.sourceName,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    required this.observations,
    this.detail,
    this.diagnostics = const {},
  });
  final String id, savedSearchId, sourceName, status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int observations;
  final String? detail;
  final Map<String, Object?> diagnostics;
  Map<String, Object?> toJson() => {
    'id': id,
    'saved_search_id': savedSearchId,
    'source_name': sourceName,
    'status': status,
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt?.toUtc().toIso8601String(),
    'observations': observations,
    'detail': detail,
    'diagnostics': diagnostics,
  };
}

class SavedSearchRunResult {
  const SavedSearchRunResult(this.sources);

  final List<SourceRunResult> sources;

  List<String> get candidateJobIds =>
      sources.expand((source) => source.candidateJobIds).toSet().toList();

  int get observations =>
      sources.fold(0, (sum, item) => sum + item.observations);
  int get createdJobs => sources.fold(0, (sum, item) => sum + item.createdJobs);
  int get failures => sources.where((item) => item.status == 'failed').length;
}

abstract interface class ConfigurationStore {
  Stream<List<SearchRunRecord>> watchSearchRuns({
    String? savedSearchId,
    int limit = 50,
  });

  Stream<List<SavedSearchDefinition>> watchSavedSearches();

  Stream<List<SourceConfiguration>> watchSourceConfigurations();

  Future<String> saveSavedSearch(SavedSearchDraft draft);

  Future<void> deleteSavedSearch(String id);

  Future<void> setSavedSearchEnabled(String id, bool enabled);

  Future<String> saveSourceConfiguration(SourceConfigurationDraft draft);

  Future<void> deleteSourceConfiguration(String id);

  Future<void> setSourceConfigurationEnabled(String id, bool enabled);

  Future<bool> clearSourceBlock(String id);

  Future<SavedSearchRunResult> runSavedSearch(String id);
}

class ConfigurationRepository implements ConfigurationStore {
  ConfigurationRepository(
    this.database,
    this.jobs, {
    Uuid? uuid,
    http.Client? httpClient,
  }) : _uuid = uuid ?? const Uuid(),
       _httpClient = httpClient ?? http.Client();

  final CareerShopperDatabase database;
  final JobRepository jobs;
  final Uuid _uuid;
  final http.Client _httpClient;

  @override
  Stream<List<SearchRunRecord>> watchSearchRuns({
    String? savedSearchId,
    int limit = 50,
  }) {
    if (limit < 1 || limit > 200) throw ArgumentError('limit must be 1 to 200');
    final query = database.select(database.searchRuns).join([
      leftOuterJoin(
        database.sourceConfigs,
        database.sourceConfigs.id.equalsExp(database.searchRuns.sourceConfigId),
      ),
    ]);
    if (savedSearchId != null) {
      query.where(database.searchRuns.savedSearchId.equals(savedSearchId));
    }
    query.orderBy([
      OrderingTerm.desc(database.searchRuns.startedAt),
      OrderingTerm.desc(database.searchRuns.id),
    ]);
    query.limit(limit);
    return query.watch().map(
      (rows) => rows.map((row) {
        final run = row.readTable(database.searchRuns);
        final source = row.readTableOrNull(database.sourceConfigs);
        final diagnostics = run.diagnosticsJson == null
            ? <String, Object?>{}
            : _decodeObject(run.diagnosticsJson!);
        return SearchRunRecord(
          id: run.id,
          savedSearchId: run.savedSearchId,
          sourceName:
              diagnostics['source_name'] as String? ??
              (source == null ? run.sourceConfigId : _sourceName(source)),
          status: run.status,
          startedAt: run.startedAt,
          finishedAt: run.finishedAt,
          observations: run.observationsSeen,
          detail: run.detail,
          diagnostics: diagnostics,
        );
      }).toList(),
    );
  }

  @override
  Stream<List<SavedSearchDefinition>> watchSavedSearches() {
    final query = database.select(database.savedSearches).join([
      leftOuterJoin(
        database.savedSearchSources,
        database.savedSearchSources.savedSearchId.equalsExp(
          database.savedSearches.id,
        ),
      ),
    ])..orderBy([OrderingTerm.asc(database.savedSearches.name)]);
    return query.watch().map((rows) {
      final grouped = <String, SavedSearchDefinition>{};
      for (final row in rows) {
        final search = row.readTable(database.savedSearches);
        final binding = row.readTableOrNull(database.savedSearchSources);
        final existing = grouped[search.id];
        final sourceIds = {...?existing?.sourceConfigIds};
        if (binding != null) sourceIds.add(binding.sourceConfigId);
        grouped[search.id] = SavedSearchDefinition(
          id: search.id,
          name: search.name,
          enabled: search.enabled,
          pollIntervalMinutes: search.pollIntervalMinutes,
          scoreThreshold: search.scoreThreshold,
          query: _decodeQuery(search.name, search.queryJson),
          sourceConfigIds: sourceIds,
        );
      }
      return grouped.values.toList(growable: false);
    });
  }

  @override
  Stream<List<SourceConfiguration>> watchSourceConfigurations() {
    final query =
        database.select(database.sourceConfigs).join([
          leftOuterJoin(
            database.sourceHealthRecords,
            database.sourceHealthRecords.sourceConfigId.equalsExp(
              database.sourceConfigs.id,
            ),
          ),
        ])..orderBy([
          OrderingTerm.asc(database.sourceConfigs.sourceFamily),
          OrderingTerm.asc(database.sourceConfigs.createdAt),
        ]);
    return query.watch().map(
      (rows) => rows
          .map((row) {
            final source = row.readTable(database.sourceConfigs);
            final health = row.readTableOrNull(database.sourceHealthRecords);
            return SourceConfiguration(
              id: source.id,
              sourceFamily: source.sourceFamily,
              adapterId: source.adapterId,
              enabled: source.enabled,
              values: _decodeObject(source.configJson),
              healthState: health?.state ?? 'not_checked',
              healthDetail: health?.detail,
              backoffUntil: health?.backoffUntil,
            );
          })
          .toList(growable: false),
    );
  }

  @override
  Future<String> saveSavedSearch(SavedSearchDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError('Search name is required.');
    if (draft.pollIntervalMinutes < 30 || draft.pollIntervalMinutes > 10080) {
      throw ArgumentError(
        'Polling interval must be between 30 and 10080 minutes.',
      );
    }
    if (draft.scoreThreshold < 0 || draft.scoreThreshold > 100) {
      throw ArgumentError('AI threshold must be between 0 and 100.');
    }
    final id = draft.id ?? _uuid.v7();
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final existing = await (database.select(
        database.savedSearches,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      await database
          .into(database.savedSearches)
          .insertOnConflictUpdate(
            SavedSearchesCompanion.insert(
              id: id,
              name: name,
              enabled: Value(draft.enabled),
              pollIntervalMinutes: Value(draft.pollIntervalMinutes),
              scoreThreshold: Value(draft.scoreThreshold),
              queryJson: jsonEncode(_encodeQuery(draft.query)),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await (database.delete(
        database.savedSearchSources,
      )..where((row) => row.savedSearchId.equals(id))).go();
      for (final sourceId in draft.sourceConfigIds) {
        await database
            .into(database.savedSearchSources)
            .insert(
              SavedSearchSourcesCompanion.insert(
                savedSearchId: id,
                sourceConfigId: sourceId,
              ),
            );
      }
    });
    return id;
  }

  @override
  Future<void> deleteSavedSearch(String id) async {
    await (database.delete(
      database.savedSearches,
    )..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> setSavedSearchEnabled(String id, bool enabled) async {
    await (database.update(
      database.savedSearches,
    )..where((row) => row.id.equals(id))).write(
      SavedSearchesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<String> saveSourceConfiguration(SourceConfigurationDraft draft) async {
    final type = builtInSourceTypes
        .where((item) => item.family == draft.sourceFamily)
        .firstOrNull;
    if (type == null) throw ArgumentError('Unsupported source type.');
    final values = Map<String, Object?>.from(draft.values);
    if (type.employerRequired || values.containsKey('employer_name')) {
      values['employer_name'] = values['employer_name']?.toString().trim();
    }
    if (type.identifierKey != null) {
      values[type.identifierKey!] =
          values[type.identifierKey!]?.toString().trim() ??
          type.defaultIdentifier;
    }
    final adapter = _adapterFor(type.adapterId);
    final check = await adapter.validateConfig(SourceConfig(values));
    if (!check.valid) throw ArgumentError(check.messages.join(' '));

    final id = draft.id ?? _uuid.v7();
    final now = DateTime.now().toUtc();
    final existing = await (database.select(
      database.sourceConfigs,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    await database
        .into(database.sourceConfigs)
        .insertOnConflictUpdate(
          SourceConfigsCompanion.insert(
            id: id,
            sourceFamily: type.family,
            adapterId: type.adapterId,
            enabled: Value(draft.enabled),
            configJson: Value(jsonEncode(values)),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return id;
  }

  @override
  Future<void> deleteSourceConfiguration(String id) async {
    await (database.delete(
      database.sourceConfigs,
    )..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> setSourceConfigurationEnabled(String id, bool enabled) async {
    await (database.update(
      database.sourceConfigs,
    )..where((row) => row.id.equals(id))).write(
      SourceConfigsCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<bool> clearSourceBlock(String id) => database.transaction(() async {
    final source = await (database.select(
      database.sourceConfigs,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (source == null) {
      throw ArgumentError('Unknown source configuration: $id');
    }
    final health = await (database.select(
      database.sourceHealthRecords,
    )..where((row) => row.sourceConfigId.equals(id))).getSingleOrNull();
    if (health?.state != 'unavailable') return false;
    final now = DateTime.now().toUtc();
    await (database.update(
      database.sourceHealthRecords,
    )..where((row) => row.sourceConfigId.equals(id))).write(
      SourceHealthRecordsCompanion(
        state: const Value('not_checked'),
        detail: const Value(null),
        consecutiveFailures: const Value(0),
        updatedAt: Value(now),
      ),
    );
    await database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: _uuid.v7(),
            eventType: 'source_block_cleared',
            subjectType: 'source_config',
            subjectId: id,
            actor: 'user',
            payloadJson: Value(jsonEncode({'previous_detail': health!.detail})),
            occurredAt: now,
          ),
        );
    return true;
  });

  @override
  Future<SavedSearchRunResult> runSavedSearch(String id) async {
    final search = await (database.select(
      database.savedSearches,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (search == null) throw ArgumentError('Saved search no longer exists.');
    final bindings = await (database.select(
      database.savedSearchSources,
    )..where((row) => row.savedSearchId.equals(id))).get();
    if (bindings.isEmpty) {
      throw StateError(
        'Choose at least one source before running this search.',
      );
    }
    final query = _decodeQuery(search.name, search.queryJson);
    final results = <SourceRunResult>[];
    for (final binding in bindings) {
      final source =
          await (database.select(database.sourceConfigs)
                ..where((row) => row.id.equals(binding.sourceConfigId)))
              .getSingleOrNull();
      if (source == null) continue;
      results.add(await _runSource(search.id, query, source));
    }
    if (results.isEmpty) {
      throw StateError('All sources attached to this search are disabled.');
    }
    return SavedSearchRunResult(results);
  }

  Future<SourceRunResult> _runSource(
    String savedSearchId,
    SavedSearchQuery query,
    SourceConfigRow source,
  ) async {
    final diagnosticClient = _SearchDiagnosticClient(_httpClient);
    final adapter = _adapterFor(source.adapterId, client: diagnosticClient);
    final sourceName = _sourceName(source);
    final now = DateTime.now().toUtc();
    final runId = _uuid.v7();
    final diagnostics = <String, Object?>{
      'source_name': sourceName,
      'adapter_id': source.adapterId,
      'remote_parameters': adapter
          .compileQuery(query, SourceConfig(_decodeObject(source.configJson)))
          .remoteParameters,
      'requests': diagnosticClient.requests,
    };
    await database
        .into(database.searchRuns)
        .insert(
          SearchRunsCompanion.insert(
            id: runId,
            savedSearchId: savedSearchId,
            sourceConfigId: source.id,
            status: 'running',
            startedAt: now,
            diagnosticsJson: Value(jsonEncode(diagnostics)),
          ),
        );
    DiscoveryRunResult? partial;
    Future<void> recordProgress(DiscoveryRunResult result) async {
      partial = result;
      diagnostics.addAll({
        'pages_read': result.pagesRead,
        'created_jobs': result.createdJobs,
        'existing_observations': result.mergedObservations,
        'filtered_by_search': result.filteredBySearch,
        'blocked_employers': result.blockedEmployers,
        'normalization_failures': result.normalizationFailures,
        'normalization_errors': result.normalizationErrors,
        'ai_candidates': result.aiCandidates,
        'ineligible_for_ai':
            result.observations -
            result.normalizationFailures -
            result.blockedEmployers -
            result.filteredBySearch -
            result.aiCandidates,
        'warnings': result.warnings,
        if (result.hasMoreResults != null)
          'more_results_available': result.hasMoreResults,
      });
      await (database.update(
        database.searchRuns,
      )..where((row) => row.id.equals(runId))).write(
        SearchRunsCompanion(
          observationsSeen: Value(result.observations),
          diagnosticsJson: Value(jsonEncode(diagnostics)),
        ),
      );
    }

    Future<SourceRunResult> finish(
      String status,
      String detail, {
      int observations = 0,
      int createdJobs = 0,
      List<String> candidates = const [],
    }) async {
      if (status == 'failed' && partial != null) {
        observations = partial!.observations;
        createdJobs = partial!.createdJobs;
        candidates = partial!.candidateJobIds;
        diagnostics['partial_results'] = true;
      }

      await (database.update(
        database.searchRuns,
      )..where((row) => row.id.equals(runId))).write(
        SearchRunsCompanion(
          status: Value(status),
          finishedAt: Value(DateTime.now().toUtc()),
          observationsSeen: Value(observations),
          detail: Value(detail),
          diagnosticsJson: Value(jsonEncode(diagnostics)),
        ),
      );
      return SourceRunResult(
        runId: runId,
        sourceName: sourceName,
        status: status,
        observations: observations,
        createdJobs: createdJobs,
        candidateJobIds: candidates,
        detail: detail,
        diagnostics: diagnostics,
      );
    }

    try {
      if (!source.enabled) {
        return await finish(
          'skipped',
          'Source is disabled. No request was sent.',
        );
      }
      final health =
          await (database.select(database.sourceHealthRecords)
                ..where((row) => row.sourceConfigId.equals(source.id)))
              .getSingleOrNull();
      if (health?.state == 'unavailable') {
        return await finish(
          'skipped',
          'Source previously blocked access. No request was sent. ${health?.detail ?? ''}',
        );
      }
      if (health?.backoffUntil != null && health!.backoffUntil!.isAfter(now)) {
        return await finish(
          'skipped',
          'Provider backoff remains active until ${health.backoffUntil}. No request was sent.',
        );
      }
      final latest =
          await (database.select(database.searchRuns)
                ..where(
                  (row) =>
                      row.savedSearchId.equals(savedSearchId) &
                      row.sourceConfigId.equals(source.id) &
                      row.id.equals(runId).not() &
                      row.status.equals('skipped').not(),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null &&
          now.difference(latest.startedAt) <
              adapter.descriptor.minimumPollInterval) {
        final available = latest.startedAt.add(
          adapter.descriptor.minimumPollInterval,
        );
        return await finish(
          'skipped',
          'Minimum source interval: available again at $available. No request was sent.',
        );
      }
      final result = await DiscoveryService(jobs).run(
        adapter: adapter,
        config: SourceConfig(_decodeObject(source.configJson)),
        savedSearchId: savedSearchId,
        search: query,
        startedAt: now,
        onProgress: recordProgress,
      );
      final warning =
          result.warnings.isNotEmpty || result.normalizationFailures > 0;
      final noneImported =
          result.observations > 0 &&
          result.normalizationFailures == result.observations;
      final detail = noneImported
          ? 'No listing records could be imported. See normalization errors in run diagnostics.'
          : result.warnings.isNotEmpty
          ? result.warnings.join('\n')
          : result.normalizationFailures > 0
          ? 'Search completed. ${result.observations - result.normalizationFailures} listing records processed; ${result.normalizationFailures} skipped because they could not be imported. ${result.aiCandidates} eligible for AI analysis.'
          : result.observations == 0
          ? 'Source returned no listings.'
          : '${result.observations} listing records processed; ${result.aiCandidates} eligible for AI analysis.';
      await _setSourceHealth(
        source.id,
        noneImported ? 'error' : 'healthy',
        detail: noneImported ? detail : null,
      );
      return await finish(
        noneImported
            ? 'failed'
            : warning
            ? 'warning'
            : 'succeeded',
        detail,
        observations: result.observations,
        createdJobs: result.createdJobs,
        candidates: result.candidateJobIds,
      );
    } on SourceBackoffException catch (error) {
      final backoff = now.add(error.retryAfter ?? const Duration(hours: 1));
      await _setSourceHealth(
        source.id,
        'backoff',
        detail: error.message,
        backoffUntil: backoff,
      );
      return await finish('failed', '${error.message} Retry after $backoff.');
    } on SourceUnavailableException catch (error) {
      await _setSourceHealth(source.id, 'unavailable', detail: error.message);
      return await finish('failed', error.message);
    } on Object catch (error) {
      await _setSourceHealth(source.id, 'error', detail: error.toString());
      return await finish('failed', error.toString());
    }
  }

  Future<void> _setSourceHealth(
    String sourceId,
    String state, {
    String? detail,
    DateTime? backoffUntil,
  }) async {
    final existing = await (database.select(
      database.sourceHealthRecords,
    )..where((row) => row.sourceConfigId.equals(sourceId))).getSingleOrNull();
    await database
        .into(database.sourceHealthRecords)
        .insertOnConflictUpdate(
          SourceHealthRecordsCompanion.insert(
            sourceConfigId: sourceId,
            state: Value(state),
            consecutiveFailures: Value(
              state == 'healthy' ? 0 : (existing?.consecutiveFailures ?? 0) + 1,
            ),
            backoffUntil: Value(backoffUntil),
            detail: Value(detail),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  JobSourceAdapter _adapterFor(
    String adapterId, {
    http.Client? client,
  }) => switch (adapterId) {
    'greenhouse_job_board_v1' => GreenhouseSourceAdapter(client ?? _httpClient),
    'lever_postings_v1' => LeverSourceAdapter(client ?? _httpClient),
    'ashby_job_board_v1' => AshbySourceAdapter(client ?? _httpClient),
    'indeed_public_search_v1' => IndeedSearchAdapter(client ?? _httpClient),
    'linkedin_guest_search_v1' => LinkedInSearchAdapter(client ?? _httpClient),
    _ => throw ArgumentError('Unsupported adapter: $adapterId'),
  };

  String _sourceName(SourceConfigRow source) {
    final values = _decodeObject(source.configJson);
    return '${values['employer_name'] ?? source.sourceFamily} (${source.sourceFamily})';
  }
}

Map<String, Object?> _decodeObject(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) return const {};
  return decoded.map((key, item) => MapEntry(key.toString(), item));
}

SavedSearchQuery _decodeQuery(String name, String value) {
  final query = _decodeObject(value);
  return SavedSearchQuery(
    name: name,
    includedTitles: _stringList(query['included_titles']),
    excludedTitles: _stringList(query['excluded_titles']),
    includedKeywords: _stringList(query['included_keywords']),
    excludedKeywords: _stringList(query['excluded_keywords']),
    locations: _stringList(query['locations']),
    remoteStatuses: _stringList(query['remote_statuses']),
    employmentTypes: _stringList(query['employment_types']),
    minimumCompensation: (query['minimum_compensation'] as num?)?.round(),
    currency: query['currency'] as String?,
  );
}

Map<String, Object?> _encodeQuery(SavedSearchQuery query) => {
  'included_titles': query.includedTitles,
  'excluded_titles': query.excludedTitles,
  'included_keywords': query.includedKeywords,
  'excluded_keywords': query.excludedKeywords,
  'locations': query.locations,
  'remote_statuses': query.remoteStatuses,
  'employment_types': query.employmentTypes,
  'minimum_compensation': query.minimumCompensation,
  'currency': query.currency,
};

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

class _SearchDiagnosticClient extends http.BaseClient {
  _SearchDiagnosticClient(this.delegate);
  final http.Client delegate;
  final requests = <Map<String, Object?>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final record = <String, Object?>{
      'url': request.url.toString(),
      'request': {
        'method': request.method,
        'url': request.url.toString(),
        'headers': _diagnosticHeaders(request.headers),
        'body': request is http.Request
            ? _diagnosticBody(request.bodyBytes)
            : null,
      },
    };
    requests.add(record);
    final timer = Stopwatch()..start();
    try {
      final response = await delegate
          .send(request)
          .timeout(const Duration(seconds: 30));
      record['http_status'] = response.statusCode;
      record['content_type'] = response.headers['content-type'];
      record['content_length'] = response.contentLength;
      final responseRecord = <String, Object?>{
        'status': response.statusCode,
        'reason': response.reasonPhrase,
        'headers': _diagnosticHeaders(response.headers),
      };
      record['response'] = responseRecord;
      return http.StreamedResponse(
        _captureResponse(
          response.stream.timeout(const Duration(seconds: 30)),
          responseRecord,
        ),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        request: response.request,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object catch (error) {
      record['error'] = error.toString();
      rethrow;
    } finally {
      record['response_ms'] = timer.elapsedMilliseconds;
    }
  }

  Stream<List<int>> _captureResponse(
    Stream<List<int>> stream,
    Map<String, Object?> record,
  ) async* {
    const limit = 20 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in stream) {
        final remaining = limit - bytes.length;
        if (chunk.length > remaining) record['body_truncated'] = true;
        if (remaining > 0) {
          bytes.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
        }
        yield chunk;
      }
    } on Object catch (error) {
      record['body_incomplete'] = true;
      record['error'] = error.toString();
      rethrow;
    } finally {
      record['body'] = _diagnosticBody(bytes.takeBytes());
    }
  }
}

Object? _diagnosticBody(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final body = utf8.decode(bytes, allowMalformed: true);
  try {
    return jsonDecode(body);
  } on FormatException {
    return body;
  }
}

Map<String, String> _diagnosticHeaders(Map<String, String> headers) => {
  for (final entry in headers.entries)
    entry.key:
        RegExp(
          'authorization|cookie|token|api[-_]?key|secret',
          caseSensitive: false,
        ).hasMatch(entry.key)
        ? '[redacted]'
        : entry.value,
};
