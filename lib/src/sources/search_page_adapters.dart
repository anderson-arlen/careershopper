import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../domain/job.dart';
import '../ingestion/normalization.dart';
import 'job_source_adapter.dart';
import 'source_http.dart';

const _searchCapabilities = <SourceCapability>{
  SourceCapability.title,
  SourceCapability.keywords,
  SourceCapability.location,
  SourceCapability.remoteStatus,
};

const _indeedSites = {
  'www.indeed.com',
  'ca.indeed.com',
  'uk.indeed.com',
  'au.indeed.com',
};

class IndeedSearchAdapter implements JobSourceAdapter {
  IndeedSearchAdapter(this._client);

  final http.Client _client;

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'indeed',
    adapterId: 'indeed_public_search_v1',
    displayName: 'Indeed',
    capabilities: _searchCapabilities,
    minimumPollInterval: Duration(hours: 2),
    policyTier: SourcePolicyTier.fragilePublicEndpoint,
  );

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async {
    final site = config.values['country_site'];
    if (site is! String || !_indeedSites.contains(site)) {
      return const SourceConfigCheck(
        valid: false,
        messages: ['country_site is not a supported Indeed site.'],
      );
    }
    return const SourceConfigCheck(valid: true);
  }

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) {
    return QueryPlan(
      remoteParameters: {
        'country_site': config.values['country_site'],
        'keywords': _searchTerms(search),
        'location': search.locations.firstOrNull,
        'remote_only': _remoteOnly(search),
        'sort': 'RELEVANCE',
        'page_size': 100,
        'result_limit': 100,
        'employment_keys': [
          if (search.employmentTypes.length == 1)
            ...switch (search.employmentTypes.single.toLowerCase()) {
              'full-time' => ['CF3CP'],
              'part-time' => ['75GKK'],
              'contract' => ['NJXCK'],
              'internship' => ['VDTG7'],
              _ => <String>[],
            },
        ],
      },
      residualQuery: search,
    );
  }

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    final site = _requiredString(plan.remoteParameters, 'country_site');
    final country = switch (site) {
      'www.indeed.com' => 'US',
      'uk.indeed.com' => 'GB',
      'ca.indeed.com' => 'CA',
      'au.indeed.com' => 'AU',
      _ => throw const FormatException('Unsupported Indeed country site.'),
    };
    final seen = <String>{};
    final keywords = plan.remoteParameters['keywords'] as String?;
    final location = plan.remoteParameters['location'] as String?;
    final filters = <String>[
      if (plan.remoteParameters['remote_only'] == true) 'DSQF7',
      ...?plan.remoteParameters['employment_keys'] as List<String>?,
    ];
    final query =
        '''query GetJobData {
        jobSearch(
          ${keywords == null || keywords.isEmpty ? '' : 'what: ${jsonEncode(keywords)}'}
          ${location == null || location.isEmpty ? '' : 'location: {where: ${jsonEncode(location)}, radius: 50, radiusUnit: MILES}'}
          limit: 100 sort: RELEVANCE
          ${filters.isEmpty ? '' : 'filters: {composite: {filters: [{keyword: {field: "attributes", keys: ${jsonEncode(filters)}}}]}}'}
        ) {
          pageInfo { nextCursor }
          results { job {
            key title datePublished description { html }
            location { city admin1Code countryCode formatted { long } }
            attributes { key label }
            employer { name }
            recruit { viewJobUrl }
            compensation {
              currencyCode baseSalary { unitOfWork range { ... on Range { min max } } }
              estimated { currencyCode baseSalary { unitOfWork range { ... on Range { min max } } } }
            }
          } }
        }
      }''';
    final data = objectMap(
      await fetchJson(
        _client,
        Uri.https('apis.indeed.com', '/graphql'),
        headers: {..._indeedApiHeaders, 'indeed-co': country},
        jsonBody: {'query': query},
      ),
      label: 'Indeed response',
    );
    if (data['errors'] case final List errors when errors.isNotEmpty) {
      final message = errors.map((e) => objectMap(e)['message']).join('; ');
      if (RegExp(
        r'access denied|unauth|forbidden|captcha|blocked',
        caseSensitive: false,
      ).hasMatch(message)) {
        throw SourceUnavailableException(
          'Indeed GraphQL: $message',
          reason: 'access_denied',
        );
      }
      throw FormatException('Indeed GraphQL: $message');
    }
    final search = objectMap(
      objectMap(data['data'], label: 'Indeed data')['jobSearch'],
      label: 'Indeed jobSearch',
    );
    final results = objectList(search['results'], label: 'Indeed results');
    final records = <Map<String, Object?>>[];
    for (final entry in results.take(100)) {
      final job = objectMap(entry['job'], label: 'Indeed job');
      final key = _requiredString(job, 'key');
      if (seen.add(key)) records.add({...job, '_country_site': site});
    }
    final next = objectMap(
      search['pageInfo'],
      label: 'Indeed pageInfo',
    )['nextCursor'];
    if (next != null && next is! String) {
      throw const FormatException('Invalid Indeed nextCursor.');
    }
    yield RawSourcePage(
      records: records,
      hasMoreResults:
          (next is String && next.isNotEmpty) || results.length > 100,
    );
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final key = _requiredString(record, 'key');
    final employer = _requiredString(objectMap(record['employer']), 'name');
    final location = objectMap(record['location']);
    final fragment = html.parseFragment(
      objectMap(record['description'])['html'] as String? ?? '',
    );
    for (final element in fragment.querySelectorAll(
      'p, div, li, br, h1, h2, h3',
    )) {
      element.append(Text('\n'));
    }
    final description = fragment.text?.trim() ?? '';
    final attributes = objectList(
      record['attributes'] ?? [],
    ).map((a) => a['label']?.toString() ?? '').toList();
    final locationText =
        objectMap(location['formatted'] ?? {})['long'] as String? ??
        [
          location['city'],
          location['admin1Code'],
          location['countryCode'],
        ].whereType<String>().join(', ');
    final compensation = objectMap(record['compensation'] ?? {});
    // The domain stores annual compensation. Keep other intervals in raw data
    // instead of comparing hourly amounts against an annual search floor.
    final salary = objectMap(compensation['baseSalary'] ?? {});
    final range = objectMap(salary['range'] ?? {});
    final sourceUrl = Uri.https(
      _requiredString(record, '_country_site'),
      '/viewjob',
      {'jk': key},
    );
    final direct = objectMap(record['recruit'] ?? {})['viewJobUrl'] as String?;
    final directUrl = direct == null ? null : Uri.tryParse(direct);
    return NormalizedListing(
      sourceFamily: descriptor.sourceFamily,
      adapterId: descriptor.adapterId,
      providerJobId: key,
      title: _requiredString(record, 'title'),
      employerName: employer,
      normalizedEmployerName: normalizeEmployerName(employer),
      location: locationText,
      description: description,
      contentHash: contentHash(description),
      remoteStatus:
          RegExp(
            r'remote|work from home|\bwfh\b',
            caseSensitive: false,
          ).hasMatch('$locationText $description ${attributes.join(' ')}')
          ? 'remote'
          : null,
      employmentType: attributes
          .where(
            (a) => const [
              'full-time',
              'part-time',
              'contract',
              'internship',
            ].contains(a.toLowerCase()),
          )
          .firstOrNull,
      compensationMinimum: salary['unitOfWork'] == 'YEAR'
          ? (range['min'] as num?)?.round()
          : null,
      compensationMaximum: salary['unitOfWork'] == 'YEAR'
          ? (range['max'] as num?)?.round()
          : null,
      compensationCurrency: compensation['currencyCode'] as String?,
      sourceUrl: sourceUrl,
      applicationUrl:
          directUrl != null &&
              directUrl.hasAuthority &&
              const ['http', 'https'].contains(directUrl.scheme)
          ? directUrl
          : sourceUrl,
      observedAt: DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode(record),
    );
  }

  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);
}

// Protocol headers from speedyapply/JobSpy, MIT; see assets/JobSpy-LICENSE.
// This is the public upstream client key, not a user credential. Never log headers.
const _indeedApiHeaders = {
  'content-type': 'application/json',
  'accept': 'application/json',
  'indeed-api-key':
      '161092c2017b5bbab13edb12461a62d5a833871e7cad6d9d475304573de67ac8',
  'indeed-locale': 'en-US',
  'accept-language': 'en-US,en;q=0.9',
  'user-agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Indeed App 193.1',
  'indeed-app-info':
      'appv=193.1; appid=com.indeed.jobsearch; osv=16.6.1; os=ios; dtype=phone',
};

class LinkedInSearchAdapter implements JobSourceAdapter {
  LinkedInSearchAdapter(this._client);

  final http.Client _client;

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'linkedin',
    adapterId: 'linkedin_guest_search_v1',
    displayName: 'LinkedIn',
    capabilities: _searchCapabilities,
    minimumPollInterval: Duration(hours: 6),
    policyTier: SourcePolicyTier.fragilePublicEndpoint,
  );

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async {
    final pages = config.values.containsKey('max_pages')
        ? config.values['max_pages']
        : 1;
    return SourceConfigCheck(
      valid: pages is int && pages >= 1 && pages <= 100,
      messages: pages is int && pages >= 1 && pages <= 100
          ? const []
          : const ['max_pages must be an integer from 1 through 100.'],
    );
  }

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) {
    return QueryPlan(
      remoteParameters: {
        'keywords': _searchTerms(search),
        'location': search.locations.firstOrNull,
        'remote_only': _remoteOnly(search),
        'max_pages': config.values['max_pages'] ?? 1,
      },
      residualQuery: search,
    );
  }

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    final parameters = <String, String>{
      if ((plan.remoteParameters['keywords'] as String?)?.isNotEmpty == true)
        'keywords': plan.remoteParameters['keywords']! as String,
      if ((plan.remoteParameters['location'] as String?)?.isNotEmpty == true)
        'location': plan.remoteParameters['location']! as String,
      if (plan.remoteParameters['remote_only'] == true) 'f_WT': '2',
      'f_TPR': 'r86400', // LinkedIn's past-24-hours posting filter.
    };
    final maxPages = plan.remoteParameters['max_pages'] ?? 1;
    if (maxPages is! int || maxPages < 1 || maxPages > 100) {
      throw const FormatException(
        'max_pages must be an integer from 1 through 100.',
      );
    }
    var start = 0;
    final seen = <String>{};
    for (var page = 0; page < maxPages; page++) {
      if (page > 0) await Future<void>.delayed(const Duration(seconds: 3));
      final uri = Uri.https(
        'www.linkedin.com',
        '/jobs-guest/jobs/api/seeMoreJobPostings/search',
        {...parameters, 'start': '$start'},
      );
      final markup = await fetchText(_client, uri);
      final document = html.parse(markup);
      final cardCount = document
          .querySelectorAll('div.base-search-card')
          .length;
      final records = _parseLinkedIn(document)
          .where((record) => seen.add(record['provider_job_id']! as String))
          .toList();
      final repeated = cardCount > 0 && records.isEmpty;
      final warning = repeated
          ? 'LinkedIn returned no new usable listings; pagination stopped.'
          : page > 0 && markup.trim().isEmpty
          ? null
          : _emptyPageWarning(markup, records);
      yield RawSourcePage(
        records: records,
        hasMoreResults: cardCount == 0 && warning == null ? false : null,
        warning: warning,
      );
      if (cardCount == 0 || repeated) break;
      // Count all returned cards, including duplicates or malformed listings.
      start += cardCount;
    }
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final description = record['description']?.toString() ?? '';
    final employer = _requiredString(record, 'employer_name');
    final sourceUrl = Uri.parse(_requiredString(record, 'source_url'));
    return NormalizedListing(
      sourceFamily: descriptor.sourceFamily,
      adapterId: descriptor.adapterId,
      providerJobId: _requiredString(record, 'provider_job_id'),
      title: _requiredString(record, 'title'),
      employerName: employer,
      normalizedEmployerName: normalizeEmployerName(employer),
      location: record['location']?.toString() ?? '',
      remoteStatus: _inferredRemoteStatus(
        record['title']?.toString(),
        record['location']?.toString(),
        description,
      ),
      description: description,
      contentHash: contentHash(description),
      sourceUrl: canonicalizeJobUrl(sourceUrl),
      applicationUrl: canonicalizeJobUrl(sourceUrl),
      observedAt:
          _publishedAt(record['published_at']) ?? DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode(record),
    );
  }

  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);
}

String? _emptyPageWarning(String markup, List<Map<String, Object?>> records) {
  if (records.isNotEmpty) return null;
  final document = html.parse(markup);
  for (final element in document.querySelectorAll('script, style')) {
    element.remove();
  }
  final text = document.body?.text.toLowerCase() ?? '';
  if (RegExp(
    r'no jobs found|no matching jobs|no results found|did not match any jobs',
  ).hasMatch(text)) {
    return null;
  }
  return 'No recognizable listing cards or explicit no-results message were found. '
      'The response may require JavaScript or use changed markup. Zero matches cannot be confirmed.';
}

List<Map<String, Object?>> _parseLinkedIn(Document document) {
  final records = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final card in document.querySelectorAll('div.base-search-card')) {
    final anchor = card.querySelector('a.base-card__full-link');
    final href = anchor?.attributes['href'];
    final urn = card.attributes['data-entity-urn'];
    final jobId = urn?.split(':').lastOrNull ?? _linkedInId(href);
    if (jobId == null || jobId.isEmpty || !seen.add(jobId)) continue;
    final title = _firstText(card, const [
      '.base-search-card__title',
      '.sr-only',
    ]);
    final employer = _firstText(card, const [
      '.base-search-card__subtitle a',
      '.base-search-card__subtitle',
    ]);
    if (title == null || employer == null) continue;
    final time = card.querySelector('time');
    records.add({
      'provider_job_id': jobId,
      'title': title,
      'employer_name': employer,
      'location': _firstText(card, const ['.job-search-card__location']),
      'description': _firstText(card, const ['.job-search-card__snippet']),
      'published_at': time?.attributes['datetime'],
      'source_url': Uri.https(
        'www.linkedin.com',
        '/jobs/view/$jobId',
      ).toString(),
    });
  }
  return records;
}

String _searchTerms(SavedSearchQuery search) => {
  ...search.includedTitles,
  ...search.includedKeywords,
}.map((value) => value.trim()).where((value) => value.isNotEmpty).join(' ');

bool _remoteOnly(SavedSearchQuery search) =>
    search.remoteStatuses.length == 1 &&
    search.remoteStatuses.single.toLowerCase() == 'remote';

String? _linkedInId(String? href) {
  if (href == null) return null;
  final match = RegExp(r'(\d{6,})(?:\D*$)').firstMatch(href);
  return match?.group(1);
}

String? _firstText(Element element, List<String> selectors) {
  for (final selector in selectors) {
    final value = _text(element.querySelector(selector));
    if (value != null) return value;
  }
  return null;
}

String? _text(Element? element) {
  final value = element?.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value == null || value.isEmpty ? null : value;
}

String? _inferredRemoteStatus(
  String? title,
  String? location,
  String? description,
) {
  final text = '$title $location $description'.toLowerCase();
  return RegExp(r'\bremote\b').hasMatch(text) ? 'remote' : null;
}

DateTime? _publishedAt(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final normalized = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
      ? '${value}T00:00:00Z'
      : value;
  return DateTime.tryParse(normalized)?.toUtc();
}

String _requiredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}
