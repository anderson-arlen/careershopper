import 'dart:convert';

import 'package:careershopper/src/sources/ats_adapters.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/sources/source_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Greenhouse fetches public board JSON and normalizes provenance',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'boards-api.greenhouse.io');
        expect(request.url.path, '/v1/boards/example/jobs');
        expect(request.url.queryParameters['content'], 'true');
        return http.Response(
          jsonEncode({
            'jobs': [
              {
                'id': 123,
                'requisition_id': 'REQ-7',
                'title': 'Platform Engineer',
                'location': {'name': 'Remote, US'},
                'content': '<p>Build <strong>reliable</strong> systems.</p>',
                'absolute_url':
                    'https://boards.greenhouse.io/example/jobs/123?utm_source=test',
                'updated_at': '2026-09-04T12:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final adapter = GreenhouseSourceAdapter(client);
      const config = SourceConfig({
        'board_token': 'example',
        'employer_name': 'Example, Inc.',
      });
      final validation = await adapter.validateConfig(config);
      expect(validation.valid, isTrue);

      final plan = adapter.compileQuery(
        const SavedSearchQuery(name: 'Backend'),
        config,
      );
      final page = await adapter
          .fetch(plan, FetchContext(startedAt: DateTime.utc(2026, 9, 4)))
          .single;
      final listing = adapter.normalize(page.records.single);

      expect(listing.providerJobId, '123');
      expect(listing.requisitionId, 'REQ-7');
      expect(listing.employerName, 'Example, Inc.');
      expect(listing.description, 'Build reliable systems.');
      expect(
        listing.applicationUrl.toString(),
        'https://boards.greenhouse.io/example/jobs/123',
      );
    },
  );

  test('Lever preserves hosted and application provenance', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'id': 'lever-1',
            'text': 'Backend Engineer',
            'categories': {'location': 'Remote', 'commitment': 'Full-time'},
            'descriptionPlain': 'Build APIs.',
            'lists': [
              {'text': 'What you will do', 'content': '<li>Own services</li>'},
            ],
            'workplaceType': 'remote',
            'hostedUrl': 'https://jobs.lever.co/example/lever-1',
            'applyUrl': 'https://jobs.lever.co/example/lever-1/apply',
          },
        ]),
        200,
      ),
    );
    final adapter = LeverSourceAdapter(client);
    const config = SourceConfig({
      'site': 'example',
      'employer_name': 'Example',
    });
    final page = await adapter
        .fetch(
          adapter.compileQuery(const SavedSearchQuery(name: 'Backend'), config),
          FetchContext(startedAt: DateTime.utc(2026, 9, 4)),
        )
        .single;
    final listing = adapter.normalize(page.records.single);

    expect(listing.sourceFamily, 'lever');
    expect(listing.applicationUrl!.path, '/example/lever-1/apply');
    expect(listing.description, contains('Own services'));
    expect(listing.remoteStatus, 'remote');
  });

  test('Ashby keeps compensation and remote metadata', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'jobs': [
            {
              'id': 'ashby-1',
              'title': 'Senior Engineer',
              'location': 'United States',
              'descriptionPlain': 'Build product infrastructure.',
              'isRemote': true,
              'employmentType': 'FullTime',
              'compensation': {
                'minValue': 150000,
                'maxValue': 190000,
                'currencyCode': 'USD',
              },
              'jobUrl': 'https://jobs.ashbyhq.com/example/ashby-1',
              'applyUrl':
                  'https://jobs.ashbyhq.com/example/ashby-1/application',
              'publishedAt': '2026-09-01T12:00:00Z',
            },
          ],
        }),
        200,
      ),
    );
    final adapter = AshbySourceAdapter(client);
    const config = SourceConfig({
      'board_name': 'example',
      'employer_name': 'Example',
    });
    final page = await adapter
        .fetch(
          adapter.compileQuery(const SavedSearchQuery(name: 'Backend'), config),
          FetchContext(startedAt: DateTime.utc(2026, 9, 4)),
        )
        .single;
    final listing = adapter.normalize(page.records.single);

    expect(listing.remoteStatus, 'remote');
    expect(listing.compensationMinimum, 150000);
    expect(listing.compensationMaximum, 190000);
    expect(listing.compensationCurrency, 'USD');
  });

  test('429 stops acquisition and reports provider backoff', () async {
    final client = MockClient(
      (_) async => http.Response('', 429, headers: {'retry-after': '120'}),
    );

    await expectLater(
      fetchJson(client, Uri.parse('https://example.com/jobs')),
      throwsA(
        isA<SourceBackoffException>().having(
          (error) => error.retryAfter,
          'retryAfter',
          const Duration(minutes: 2),
        ),
      ),
    );
  });

  test('CAPTCHA response makes a source unavailable', () async {
    final client = MockClient(
      (_) async => http.Response('<html>Verify you are human</html>', 403),
    );

    await expectLater(
      fetchJson(client, Uri.parse('https://example.com/jobs')),
      throwsA(isA<SourceUnavailableException>()),
    );
  });
}
