import 'dart:convert';

import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/sources/search_page_adapters.dart';
import 'package:careershopper/src/sources/source_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'LinkedIn advances by raw card count and respects the page budget',
    () async {
      final offsets = <String?>[];
      final adapter = LinkedInSearchAdapter(
        MockClient((request) async {
          offsets.add(request.url.queryParameters['start']);
          expect(request.url.queryParameters['f_TPR'], 'r86400');
          return http.Response(
            offsets.length == 1
                ? '${_linkedInCard('1')}${_linkedInCard('1')}${_linkedInCard('2')}'
                : '${_linkedInCard('2')}${_linkedInCard('3')}',
            200,
          );
        }),
      );
      final pages = await adapter
          .fetch(
            adapter.compileQuery(
              const SavedSearchQuery(name: 'Engineer'),
              const SourceConfig({'max_pages': 2}),
            ),
            FetchContext(startedAt: DateTime.now()),
          )
          .toList();
      expect(offsets, ['0', '3']);
      expect(pages.expand((p) => p.records).map((r) => r['provider_job_id']), [
        '1',
        '2',
        '3',
      ]);
      expect(pages.last.hasMoreResults, isNull);
    },
  );

  for (final ending in ['empty', 'repeated', 'blocked']) {
    test('LinkedIn stops early on $ending pages', () async {
      var calls = 0;
      final adapter = LinkedInSearchAdapter(
        MockClient((_) async {
          calls++;
          return calls == 1 || ending == 'repeated'
              ? http.Response(_linkedInCard('1'), 200)
              : ending == 'blocked'
              ? http.Response('Access denied', 403)
              : http.Response('', 200);
        }),
      );
      final records = <Map<String, Object?>>[];
      Future<void> fetch() async {
        await for (final page in adapter.fetch(
          adapter.compileQuery(
            const SavedSearchQuery(name: 'Engineer'),
            const SourceConfig({'max_pages': 5}),
          ),
          FetchContext(startedAt: DateTime.now()),
        )) {
          records.addAll(page.records);
        }
      }

      if (ending == 'blocked') {
        await expectLater(fetch(), throwsA(isA<SourceUnavailableException>()));
      } else {
        await fetch();
      }
      expect(calls, 2);
      expect(records, hasLength(1));
    });
  }

  test('LinkedIn validates integer page limits', () async {
    final adapter = LinkedInSearchAdapter(
      MockClient((_) async => throw StateError('No fetch')),
    );
    for (final value in [0, -1, 101, 1.5, '2', null]) {
      expect(
        (await adapter.validateConfig(
          SourceConfig({'max_pages': value}),
        )).valid,
        false,
      );
    }
    for (final value in [1, 100]) {
      expect(
        (await adapter.validateConfig(
          SourceConfig({'max_pages': value}),
        )).valid,
        true,
      );
    }
  });

  test('Indeed uses JobSpy GraphQL and reads only the first page', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://apis.indeed.com/graphql');
      expect(request.headers['indeed-co'], 'US');
      expect(request.headers['indeed-api-key'], isNotEmpty);
      final query = (jsonDecode(request.body) as Map)['query'] as String;
      expect(query, contains('limit: 100 sort: RELEVANCE'));
      expect(query, contains('DSQF7'));
      expect(query, contains('CF3CP'));
      expect(query, contains('radius: 50'));
      expect(query, isNot(contains('cursor:')));
      return http.Response(
        jsonEncode({
          'data': {
            'jobSearch': {
              'pageInfo': {'nextCursor': requests == 1 ? 'next-page' : null},
              'results': [
                {'job': _indeedJob('one')},
                {'job': _indeedJob('one')},
              ],
            },
          },
        }),
        200,
      );
    });
    final adapter = IndeedSearchAdapter(client);
    final pages = await adapter
        .fetch(
          adapter.compileQuery(
            const SavedSearchQuery(
              name: 'Backend',
              includedTitles: ['Backend Engineer'],
              locations: ['Denver'],
              remoteStatuses: ['remote'],
              employmentTypes: ['full-time'],
            ),
            const SourceConfig({'country_site': 'www.indeed.com'}),
          ),
          FetchContext(startedAt: DateTime.now()),
        )
        .toList();
    expect(requests, 1);
    expect(pages.single.records, hasLength(1));
    expect(pages.single.hasMoreResults, true);
    expect(pages.single.warning, isNull);
    final listing = adapter.normalize(pages.first.records.single);
    expect(listing.title, 'Senior Backend Engineer');
    expect(listing.employerName, 'Example, Inc.');
    expect(listing.description, contains('Complete requirements.'));
    expect(listing.description, contains('\n'));
    expect(listing.remoteStatus, 'remote');
    expect(listing.employmentType, 'Full-time');
    expect(listing.compensationMinimum, 120000);
    expect(listing.applicationUrl.toString(), 'https://example.test/apply/one');
  });

  for (final response in [
    http.Response(
      jsonEncode({
        'errors': [
          {'message': 'Invalid query'},
        ],
      }),
      200,
    ),
    http.Response(jsonEncode({'data': {}}), 200),
    http.Response('<html>Verify you are human</html>', 403),
    http.Response('rate limited', 429),
  ]) {
    test(
      'Indeed does not turn errors into empty success: ${response.statusCode} ${response.body}',
      () async {
        var requests = 0;
        final adapter = IndeedSearchAdapter(
          MockClient((_) async {
            requests++;
            return response;
          }),
        );
        await expectLater(
          adapter
              .fetch(
                adapter.compileQuery(
                  const SavedSearchQuery(name: 'test'),
                  const SourceConfig({'country_site': 'www.indeed.com'}),
                ),
                FetchContext(startedAt: DateTime.now()),
              )
              .toList(),
          throwsException,
        );
        expect(requests, 1);
      },
    );
  }

  test('Indeed caps an oversized response at the first 100 results', () async {
    var requests = 0;
    final adapter = IndeedSearchAdapter(
      MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'data': {
              'jobSearch': {
                'results': [
                  for (var index = 0; index < 105; index++)
                    {'job': _indeedJob('$index')},
                ],
                'pageInfo': {'nextCursor': 'same'},
              },
            },
          }),
          200,
        );
      }),
    );
    final pages = await adapter
        .fetch(
          adapter.compileQuery(
            const SavedSearchQuery(name: 'test'),
            const SourceConfig({'country_site': 'uk.indeed.com'}),
          ),
          FetchContext(startedAt: DateTime.now()),
        )
        .toList();
    expect(requests, 1);
    expect(pages.single.records, hasLength(100));
    expect(pages.single.records.last['key'], '99');
    expect(pages.single.hasMoreResults, true);
  });

  test('Indeed recognizes a structured empty result', () async {
    final adapter = IndeedSearchAdapter(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'jobSearch': {
                'results': [],
                'pageInfo': {'nextCursor': null},
              },
            },
          }),
          200,
        ),
      ),
    );
    final page = await adapter
        .fetch(
          adapter.compileQuery(
            const SavedSearchQuery(name: 'test'),
            const SourceConfig({'country_site': 'ca.indeed.com'}),
          ),
          FetchContext(startedAt: DateTime.now()),
        )
        .single;
    expect(page.records, isEmpty);
    expect(page.warning, isNull);
  });

  test(
    'LinkedIn searches the past 24 hours on one guest page without login or detail requests',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(
          request.url.path,
          '/jobs-guest/jobs/api/seeMoreJobPostings/search',
        );
        expect(request.url.queryParameters['start'], '0');
        expect(request.url.queryParameters['f_WT'], '2');
        expect(request.url.queryParameters['f_TPR'], 'r86400');
        expect(request.headers['user-agent'], startsWith('CareerShopper/'));
        expect(request.headers, isNot(contains('cookie')));
        return http.Response('''
        <div class="base-search-card" data-entity-urn="urn:li:jobPosting:4462184161">
          <a class="base-card__full-link"
             href="https://www.linkedin.com/jobs/view/platform-engineer-4462184161?trackingId=x"></a>
          <h3 class="base-search-card__title">Platform Engineer</h3>
          <h4 class="base-search-card__subtitle"><a>Example Corp</a></h4>
          <span class="job-search-card__location">Remote, United States</span>
          <time datetime="2026-09-03"></time>
        </div>
      ''', 200);
      });
      final adapter = LinkedInSearchAdapter(client);
      final plan = adapter.compileQuery(
        const SavedSearchQuery(
          name: 'Platform',
          includedTitles: ['Platform Engineer'],
          locations: ['United States'],
          remoteStatuses: ['remote'],
        ),
        const SourceConfig({}),
      );
      final page = await adapter
          .fetch(plan, FetchContext(startedAt: DateTime.utc(2026, 9, 4)))
          .single;
      final listing = adapter.normalize(page.records.single);

      expect(requests, 1);
      expect(listing.providerJobId, '4462184161');
      expect(listing.employerName, 'Example Corp');
      expect(listing.location, 'Remote, United States');
      expect(
        listing.applicationUrl.toString(),
        'https://www.linkedin.com/jobs/view/4462184161',
      );
      expect(listing.observedAt, DateTime.utc(2026, 9, 3));
    },
  );

  test('fragile search adapters propagate explicit provider blocks', () async {
    final client = MockClient(
      (_) async => http.Response('<html>Verify you are human</html>', 403),
    );
    final adapter = LinkedInSearchAdapter(client);
    final pages = adapter.fetch(
      adapter.compileQuery(
        const SavedSearchQuery(name: 'Backend'),
        const SourceConfig({}),
      ),
      FetchContext(startedAt: DateTime.utc(2026, 9, 4)),
    );

    await expectLater(
      pages.toList(),
      throwsA(isA<SourceUnavailableException>()),
    );
  });
}

String _linkedInCard(String id) =>
    '''
<div class="base-search-card" data-entity-urn="urn:li:jobPosting:$id">
<h3 class="base-search-card__title">Engineer</h3>
<h4 class="base-search-card__subtitle">Example</h4>
</div>''';

Map<String, Object?> _indeedJob(String key) => {
  'key': key,
  'title': 'Senior Backend Engineer',
  'employer': {'name': 'Example, Inc.'},
  'description': {
    'html':
        '<p>Build APIs and captcha detection.</p><p>Complete requirements.</p>',
  },
  'location': {
    'formatted': {'long': 'Remote, Denver, CO'},
  },
  'attributes': [
    {'label': 'Full-time'},
    {'label': 'Remote'},
  ],
  'recruit': {'viewJobUrl': 'https://example.test/apply/$key'},
  'compensation': {
    'currencyCode': 'USD',
    'baseSalary': {
      'unitOfWork': 'YEAR',
      'range': {'min': 120000, 'max': 150000},
    },
  },
};
