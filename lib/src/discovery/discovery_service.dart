import '../sources/job_source_adapter.dart';
import '../storage/job_repository.dart';

class DiscoveryRunResult {
  const DiscoveryRunResult({
    required this.observations,
    required this.createdJobs,
    required this.mergedObservations,
    required this.candidateJobIds,
    required this.blockedEmployers,
    required this.filteredBySearch,
    required this.normalizationFailures,
    this.pagesRead = 0,
    this.warnings = const [],
    this.hasMoreResults,
    this.normalizationErrors = const [],
  });

  final int observations;
  final int createdJobs;
  final int mergedObservations;
  final List<String> candidateJobIds;
  int get aiCandidates => candidateJobIds.length;
  final int blockedEmployers;
  final int filteredBySearch;
  final int normalizationFailures;
  final int pagesRead;
  final List<String> warnings;
  final bool? hasMoreResults;
  final List<Map<String, Object?>> normalizationErrors;
}

class DiscoveryService {
  const DiscoveryService(this.jobs);

  final JobRepository jobs;

  Future<DiscoveryRunResult> run({
    required JobSourceAdapter adapter,
    required SourceConfig config,
    required String savedSearchId,
    required SavedSearchQuery search,
    DateTime? startedAt,
    Future<void> Function(DiscoveryRunResult)? onProgress,
  }) async {
    final validation = await adapter.validateConfig(config);
    if (!validation.valid) {
      throw ArgumentError(
        'Invalid ${adapter.descriptor.displayName} config: '
        '${validation.messages.join(' ')}',
      );
    }

    final plan = adapter.compileQuery(search, config);
    var observations = 0;
    var createdJobs = 0;
    var mergedObservations = 0;
    final candidateJobIds = <String>{};
    var blockedEmployers = 0;
    var normalizationFailures = 0;
    final normalizationErrors = <Map<String, Object?>>[];
    var pagesRead = 0;
    final warnings = <String>[];
    String? cursor;
    bool? hasMoreResults;

    Future<DiscoveryRunResult> summary() async => DiscoveryRunResult(
      observations: observations,
      createdJobs: createdJobs,
      mergedObservations: mergedObservations,
      candidateJobIds: await jobs.searchAnalysisCandidates(candidateJobIds),
      blockedEmployers: blockedEmployers,
      filteredBySearch: 0,
      normalizationFailures: normalizationFailures,
      pagesRead: pagesRead,
      warnings: warnings,
      hasMoreResults: hasMoreResults,
      normalizationErrors: normalizationErrors,
    );

    do {
      final pages = adapter.fetch(
        plan,
        FetchContext(
          startedAt: startedAt ?? DateTime.now().toUtc(),
          cursor: cursor,
        ),
      );
      RawSourcePage? finalPage;
      await for (final page in pages) {
        pagesRead++;
        hasMoreResults = page.hasMoreResults;
        if (page.warning != null) warnings.add(page.warning!);
        finalPage = page;
        for (final rawRecord in page.records) {
          observations++;
          try {
            final listing = adapter.normalize(rawRecord);
            // The provider already selected these results. AI assesses their fit;
            // a second literal filter can incorrectly discard relevant listings.
            final result = await jobs.ingest(
              listing,
              savedSearchId: savedSearchId,
            );
            if (result.created) {
              createdJobs++;
            } else {
              mergedObservations++;
            }
            if (result.blockedEmployer) {
              blockedEmployers++;
            } else {
              candidateJobIds.add(result.jobId);
            }
          } on FormatException catch (error) {
            normalizationFailures++;
            normalizationErrors.add({
              'record_number': observations,
              'reason': error.message,
            });
          }
        }
        if (onProgress != null) await onProgress(await summary());
      }
      cursor = finalPage?.nextCursor;
    } while (cursor != null);

    return summary();
  }
}
