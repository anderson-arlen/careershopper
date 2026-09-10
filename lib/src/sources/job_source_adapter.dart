import '../domain/job.dart';

enum SourceCapability {
  title,
  keywords,
  location,
  remoteStatus,
  compensation,
  employmentType,
  recency,
  availabilityCheck,
}

enum SourcePolicyTier { publicApi, fragilePublicEndpoint, manual }

class SourceDescriptor {
  const SourceDescriptor({
    required this.sourceFamily,
    required this.adapterId,
    required this.displayName,
    required this.capabilities,
    required this.minimumPollInterval,
    required this.policyTier,
  });

  final String sourceFamily;
  final String adapterId;
  final String displayName;
  final Set<SourceCapability> capabilities;
  final Duration minimumPollInterval;
  final SourcePolicyTier policyTier;
}

class SavedSearchQuery {
  const SavedSearchQuery({
    required this.name,
    this.includedTitles = const [],
    this.excludedTitles = const [],
    this.includedKeywords = const [],
    this.excludedKeywords = const [],
    this.locations = const [],
    this.remoteStatuses = const [],
    this.employmentTypes = const [],
    this.minimumCompensation,
    this.currency,
  });

  final String name;
  final List<String> includedTitles;
  final List<String> excludedTitles;
  final List<String> includedKeywords;
  final List<String> excludedKeywords;
  final List<String> locations;
  final List<String> remoteStatuses;
  final List<String> employmentTypes;
  final int? minimumCompensation;
  final String? currency;
}

class SourceConfig {
  const SourceConfig(this.values);

  final Map<String, Object?> values;
}

class SourceConfigCheck {
  const SourceConfigCheck({required this.valid, this.messages = const []});

  final bool valid;
  final List<String> messages;
}

class QueryPlan {
  const QueryPlan({
    required this.remoteParameters,
    required this.residualQuery,
  });

  final Map<String, Object?> remoteParameters;
  final SavedSearchQuery residualQuery;
}

class FetchContext {
  const FetchContext({required this.startedAt, this.cursor});

  final DateTime startedAt;
  final String? cursor;
}

class RawSourcePage {
  const RawSourcePage({
    required this.records,
    this.nextCursor,
    this.warning,
    this.hasMoreResults,
  });

  final List<Map<String, Object?>> records;
  final String? nextCursor;
  final String? warning;
  final bool? hasMoreResults;
}

class AvailabilityResult {
  const AvailabilityResult(this.availability, {this.checkedAt, this.detail});

  final JobAvailability availability;
  final DateTime? checkedAt;
  final String? detail;
}

abstract interface class JobSourceAdapter {
  SourceDescriptor get descriptor;

  Future<SourceConfigCheck> validateConfig(SourceConfig config);

  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config);

  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context);

  NormalizedListing normalize(Map<String, Object?> record);

  Future<AvailabilityResult> checkAvailability(NormalizedListing observation);
}
