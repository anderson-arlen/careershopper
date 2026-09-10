import 'package:careershopper/src/ingestion/normalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonicalizeJobUrl removes only known tracking and sorts parameters', () {
    final result = canonicalizeJobUrl(
      Uri.parse(
        'HTTPS://Jobs.Example.com:443/opening/123/?utm_source=email&job=42&b=2&a=1#apply',
      ),
    );

    expect(
      result.toString(),
      'https://jobs.example.com/opening/123?a=1&b=2&job=42',
    );
  });

  test('canonicalizeJobUrl preserves identifiers with unfamiliar names', () {
    final result = canonicalizeJobUrl(
      Uri.parse('https://example.com/job?source=board&gh_jid=100'),
    );

    expect(result.queryParameters, {'gh_jid': '100', 'source': 'board'});
  });

  test('employer normalization stays conservative', () {
    expect(normalizeEmployerName('  Example,   Inc. '), 'example,inc.');
    expect(
      normalizeEmployerName('Data Annotation'),
      isNot(normalizeEmployerName('DataAnnotation')),
    );
  });

  test('content hashes ignore whitespace-only changes', () {
    expect(
      contentHash('A\n job   description'),
      contentHash('A job description'),
    );
  });
}
