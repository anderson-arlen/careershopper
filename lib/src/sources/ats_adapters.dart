import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../domain/job.dart';
import '../ingestion/normalization.dart';
import 'job_source_adapter.dart';
import 'source_http.dart';

const _boardCapabilities = <SourceCapability>{
  SourceCapability.title,
  SourceCapability.keywords,
  SourceCapability.location,
  SourceCapability.remoteStatus,
  SourceCapability.employmentType,
};

class GreenhouseSourceAdapter implements JobSourceAdapter {
  GreenhouseSourceAdapter(this._client);

  final http.Client _client;

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'greenhouse',
    adapterId: 'greenhouse_job_board_v1',
    displayName: 'Greenhouse',
    capabilities: _boardCapabilities,
    minimumPollInterval: Duration(hours: 1),
    policyTier: SourcePolicyTier.publicApi,
  );

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async {
    final messages = _requiredBoardConfigMessages(config, 'board_token');
    final token = config.values['board_token'];
    if (token is String && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
      messages.add('board_token contains unsupported characters.');
    }
    return SourceConfigCheck(valid: messages.isEmpty, messages: messages);
  }

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) =>
      QueryPlan(
        remoteParameters: {
          'board_token': config.values['board_token'],
          'employer_name': config.values['employer_name'],
        },
        residualQuery: search,
      );

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    final token = _requiredString(plan.remoteParameters, 'board_token');
    final uri = Uri.https(
      'boards-api.greenhouse.io',
      '/v1/boards/$token/jobs',
      {'content': 'true'},
    );
    final decoded = objectMap(
      await fetchJson(_client, uri),
      label: 'Greenhouse response',
    );
    final records = objectList(decoded['jobs'], label: 'Greenhouse jobs')
        .map(
          (record) => {
            ...record,
            '_careershopper_tenant': token,
            '_careershopper_employer': plan.remoteParameters['employer_name'],
          },
        )
        .toList(growable: false);
    yield RawSourcePage(records: records);
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final employer = _requiredString(record, '_careershopper_employer');
    final location = objectMap(
      record['location'],
      label: 'Greenhouse location',
    );
    final description = _plainText(record['content'] as String? ?? '');
    final sourceUrl = Uri.parse(_requiredString(record, 'absolute_url'));
    return NormalizedListing(
      sourceFamily: descriptor.sourceFamily,
      adapterId: descriptor.adapterId,
      providerJobId: record['id']?.toString(),
      tenantId: record['_careershopper_tenant'] as String?,
      requisitionId: record['requisition_id']?.toString(),
      title: _requiredString(record, 'title'),
      employerName: employer,
      normalizedEmployerName: normalizeEmployerName(employer),
      location: location['name']?.toString() ?? '',
      description: description,
      contentHash: contentHash(description),
      sourceUrl: canonicalizeJobUrl(sourceUrl),
      applicationUrl: canonicalizeJobUrl(sourceUrl),
      observedAt: _date(record['updated_at']) ?? DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode(record),
    );
  }

  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);
}

class LeverSourceAdapter implements JobSourceAdapter {
  LeverSourceAdapter(this._client);

  final http.Client _client;

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'lever',
    adapterId: 'lever_postings_v1',
    displayName: 'Lever',
    capabilities: _boardCapabilities,
    minimumPollInterval: Duration(hours: 1),
    policyTier: SourcePolicyTier.publicApi,
  );

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async =>
      SourceConfigCheck(
        valid: _requiredBoardConfigMessages(config, 'site').isEmpty,
        messages: _requiredBoardConfigMessages(config, 'site'),
      );

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) =>
      QueryPlan(
        remoteParameters: {
          'site': config.values['site'],
          'employer_name': config.values['employer_name'],
        },
        residualQuery: search,
      );

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    final site = _requiredString(plan.remoteParameters, 'site');
    final uri = Uri.https('api.lever.co', '/v0/postings/$site', {
      'mode': 'json',
    });
    final records =
        objectList(await fetchJson(_client, uri), label: 'Lever postings')
            .map(
              (record) => {
                ...record,
                '_careershopper_tenant': site,
                '_careershopper_employer':
                    plan.remoteParameters['employer_name'],
              },
            )
            .toList(growable: false);
    yield RawSourcePage(records: records);
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final employer = _requiredString(record, '_careershopper_employer');
    final categories = objectMap(
      record['categories'] ?? {},
      label: 'Lever categories',
    );
    final description = _leverDescription(record);
    return NormalizedListing(
      sourceFamily: descriptor.sourceFamily,
      adapterId: descriptor.adapterId,
      providerJobId: record['id']?.toString(),
      tenantId: record['_careershopper_tenant'] as String?,
      title: _requiredString(record, 'text'),
      employerName: employer,
      normalizedEmployerName: normalizeEmployerName(employer),
      location: categories['location']?.toString() ?? '',
      remoteStatus: record['workplaceType']?.toString(),
      employmentType: categories['commitment']?.toString(),
      description: description,
      contentHash: contentHash(description),
      sourceUrl: canonicalizeJobUrl(
        Uri.parse(_requiredString(record, 'hostedUrl')),
      ),
      applicationUrl: canonicalizeJobUrl(
        Uri.parse(_requiredString(record, 'applyUrl')),
      ),
      observedAt: DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode(record),
    );
  }

  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);
}

class AshbySourceAdapter implements JobSourceAdapter {
  AshbySourceAdapter(this._client);

  final http.Client _client;

  @override
  SourceDescriptor get descriptor => const SourceDescriptor(
    sourceFamily: 'ashby',
    adapterId: 'ashby_job_board_v1',
    displayName: 'Ashby',
    capabilities: {..._boardCapabilities, SourceCapability.compensation},
    minimumPollInterval: Duration(hours: 1),
    policyTier: SourcePolicyTier.publicApi,
  );

  @override
  Future<SourceConfigCheck> validateConfig(SourceConfig config) async =>
      SourceConfigCheck(
        valid: _requiredBoardConfigMessages(config, 'board_name').isEmpty,
        messages: _requiredBoardConfigMessages(config, 'board_name'),
      );

  @override
  QueryPlan compileQuery(SavedSearchQuery search, SourceConfig config) =>
      QueryPlan(
        remoteParameters: {
          'board_name': config.values['board_name'],
          'employer_name': config.values['employer_name'],
        },
        residualQuery: search,
      );

  @override
  Stream<RawSourcePage> fetch(QueryPlan plan, FetchContext context) async* {
    final board = _requiredString(plan.remoteParameters, 'board_name');
    final uri = Uri.https('api.ashbyhq.com', '/posting-api/job-board/$board', {
      'includeCompensation': 'true',
    });
    final decoded = objectMap(
      await fetchJson(_client, uri),
      label: 'Ashby response',
    );
    final records = objectList(decoded['jobs'], label: 'Ashby jobs')
        .map(
          (record) => {
            ...record,
            '_careershopper_tenant': board,
            '_careershopper_employer': plan.remoteParameters['employer_name'],
          },
        )
        .toList(growable: false);
    yield RawSourcePage(records: records);
  }

  @override
  NormalizedListing normalize(Map<String, Object?> record) {
    final employer = _requiredString(record, '_careershopper_employer');
    final description =
        (record['descriptionPlain'] as String?)?.trim().isNotEmpty == true
        ? (record['descriptionPlain'] as String).trim()
        : _plainText(record['descriptionHtml'] as String? ?? '');
    final compensation = record['compensation'] == null
        ? const <String, Object?>{}
        : objectMap(record['compensation'], label: 'Ashby compensation');
    return NormalizedListing(
      sourceFamily: descriptor.sourceFamily,
      adapterId: descriptor.adapterId,
      providerJobId: record['id']?.toString(),
      tenantId: record['_careershopper_tenant'] as String?,
      title: _requiredString(record, 'title'),
      employerName: employer,
      normalizedEmployerName: normalizeEmployerName(employer),
      location: record['location']?.toString() ?? '',
      remoteStatus:
          record['workplaceType']?.toString() ??
          (record['isRemote'] == true ? 'remote' : null),
      employmentType: record['employmentType']?.toString(),
      compensationMinimum: _intValue(compensation['minValue']),
      compensationMaximum: _intValue(compensation['maxValue']),
      compensationCurrency: compensation['currencyCode']?.toString(),
      description: description,
      contentHash: contentHash(description),
      sourceUrl: canonicalizeJobUrl(
        Uri.parse(_requiredString(record, 'jobUrl')),
      ),
      applicationUrl: canonicalizeJobUrl(
        Uri.parse(_requiredString(record, 'applyUrl')),
      ),
      observedAt: _date(record['publishedAt']) ?? DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode(record),
    );
  }

  @override
  Future<AvailabilityResult> checkAvailability(
    NormalizedListing observation,
  ) async => const AvailabilityResult(JobAvailability.unknown);
}

List<String> _requiredBoardConfigMessages(
  SourceConfig config,
  String tenantKey,
) {
  final messages = <String>[];
  if (config.values[tenantKey] is! String ||
      (config.values[tenantKey] as String).trim().isEmpty) {
    messages.add('$tenantKey is required.');
  }
  if (config.values['employer_name'] is! String ||
      (config.values['employer_name'] as String).trim().isEmpty) {
    messages.add('employer_name is required.');
  }
  return messages;
}

String _requiredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String _plainText(String markup) => (html.parseFragment(markup).text ?? '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _leverDescription(Map<String, Object?> record) {
  final sections = <String>[];
  final plain = record['descriptionPlain'];
  if (plain is String && plain.trim().isNotEmpty) sections.add(plain.trim());
  final lists = record['lists'];
  if (lists is List) {
    for (final item in lists) {
      final section = objectMap(item, label: 'Lever list');
      final heading = section['text']?.toString().trim();
      final content = _plainText(section['content']?.toString() ?? '');
      if (heading != null && heading.isNotEmpty) sections.add(heading);
      if (content.isNotEmpty) sections.add(content);
    }
  }
  return sections.join('\n\n');
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int? _intValue(Object? value) => value is num ? value.round() : null;
