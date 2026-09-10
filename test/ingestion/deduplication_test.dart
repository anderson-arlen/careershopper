import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/ingestion/deduplication.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact provider IDs merge across observations from the same family', () {
    final first = _listing(providerJobId: '123', contentHash: 'old');
    final second = _listing(providerJobId: '123', contentHash: 'new');

    expect(
      compareListings(first, second).disposition,
      DeduplicationDisposition.merge,
    );
  });

  test(
    'same title, employer, and location with different content needs review',
    () {
      final first = _listing(contentHash: 'old');
      final second = _listing(contentHash: 'new');

      expect(
        compareListings(first, second).disposition,
        DeduplicationDisposition.reviewCandidate,
      );
    },
  );

  test('similar titles alone never merge', () {
    final first = _listing(title: 'Backend Engineer', employer: 'one');
    final second = _listing(title: 'Senior Backend Engineer', employer: 'two');

    expect(
      compareListings(first, second).disposition,
      DeduplicationDisposition.create,
    );
  });
}

NormalizedListing _listing({
  String? providerJobId,
  String title = 'Engineer',
  String employer = 'example',
  String contentHash = 'hash',
}) {
  return NormalizedListing(
    sourceFamily: 'test',
    adapterId: 'test_v1',
    providerJobId: providerJobId,
    title: title,
    employerName: employer,
    normalizedEmployerName: employer,
    location: 'Remote',
    description: 'Description',
    contentHash: contentHash,
    sourceUrl: Uri.parse('https://example.com/source/$contentHash'),
    applicationUrl: Uri.parse(
      'https://example.com/apply/${Uri.encodeComponent(employer)}/${Uri.encodeComponent(title)}/$contentHash',
    ),
    observedAt: DateTime.utc(2026, 9, 4),
  );
}
