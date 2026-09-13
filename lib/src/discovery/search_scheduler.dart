import 'dart:async';

import '../storage/ai_harness_repository.dart';
import '../storage/configuration_repository.dart';

/// Runs only in the desktop process; MCP can configure schedules but cannot
/// launch the AI harness. Provider access policy stays in the shared repository.
class SearchScheduler {
  SearchScheduler(this.configuration, this.harnesses);

  final ConfigurationRepository configuration;
  final AiHarnessStore harnesses;
  Timer? _timer;
  bool _running = false;

  void start() {
    stop();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(tick()),
    );
    unawaited(tick());
  }

  void stop() => _timer?.cancel();

  Future<void> tick({DateTime? now}) async {
    if (_running) return;
    _running = true;
    try {
      final due = await configuration.claimDueSearches(
        now ?? DateTime.now().toUtc(),
      );
      for (final id in due) {
        final searches = await configuration.watchSavedSearches().first;
        if (!searches.any((s) => s.id == id && s.enabled)) continue;
        try {
          if (!(await harnesses.watchProfiles().first).any(
            (p) => p.isJobMatchingDefault || p.isDefault,
          )) {
            throw const NoDefaultAiHarnessException();
          }
          final result = await configuration.runSavedSearch(id);
          if (result.candidateJobIds.isNotEmpty) {
            await harnesses.dispatchSearchAnalysis(
              result.candidateJobIds,
              savedSearchId: id,
            );
          }
          await configuration.recordScheduleError(
            id,
            result.failures == 0
                ? null
                : result.sources
                      .where((s) => s.status == 'failed')
                      .map((s) => s.detail ?? 'Search failed.')
                      .join('\n'),
          );
        } on Object catch (error) {
          await configuration.recordScheduleError(id, error.toString());
        }
      }
    } finally {
      _running = false;
    }
  }
}
