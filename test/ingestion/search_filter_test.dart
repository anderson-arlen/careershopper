import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/ingestion/search_filter.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const search = SavedSearchQuery(
    name: 'Backend',
    includedTitles: ['backend', 'platform'],
    excludedKeywords: ['clearance required'],
    locations: ['Denver'],
    remoteStatuses: ['remote'],
    minimumCompensation: 140000,
    currency: 'USD',
  );

  test('known mismatches are rejected', () {
    final result = enforceSavedSearch(
      _listing(
        location: 'Austin, TX',
        remoteStatus: 'onsite',
        compensationMaximum: 120000,
      ),
      search,
    );

    expect(result.disposition, SearchFilterDisposition.reject);
    expect(result.reasons, hasLength(greaterThanOrEqualTo(3)));
  });

  test('unknown source fields stay plausible', () {
    final result = enforceSavedSearch(
      _listing(location: '', remoteStatus: null, compensationMaximum: null),
      search,
    );

    expect(result.disposition, SearchFilterDisposition.plausibleUnknown);
    expect(result.reasons, contains('location is unavailable'));
    expect(result.reasons, contains('compensation is unavailable'));
  });

  test('known matches pass', () {
    final result = enforceSavedSearch(
      _listing(
        location: 'Denver, CO',
        remoteStatus: 'remote',
        compensationMaximum: 180000,
      ),
      search,
    );

    expect(result.disposition, SearchFilterDisposition.match);
  });
}

NormalizedListing _listing({
  required String location,
  required String? remoteStatus,
  required int? compensationMaximum,
}) {
  return NormalizedListing(
    sourceFamily: 'test',
    adapterId: 'test_v1',
    providerJobId: '1',
    title: 'Backend Engineer',
    employerName: 'Example',
    normalizedEmployerName: 'example',
    location: location,
    remoteStatus: remoteStatus,
    compensationMaximum: compensationMaximum,
    compensationCurrency: compensationMaximum == null ? null : 'USD',
    description: 'Build reliable distributed systems.',
    contentHash: 'hash',
    sourceUrl: Uri.parse('https://example.com/jobs/1'),
    applicationUrl: Uri.parse('https://example.com/jobs/1/apply'),
    observedAt: DateTime.utc(2026, 9, 4),
  );
}
