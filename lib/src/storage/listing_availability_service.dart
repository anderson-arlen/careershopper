import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/job.dart';
import '../sources/source_http.dart';
import 'database.dart';
import 'job_repository.dart';

class ListingAvailabilityResult {
  const ListingAvailabilityResult(this.result, this.detail, this.url);
  final String result;
  final String detail;
  final String url;
  bool get expired => result == 'expired';
  Map<String, Object?> toJson() => {
    'result': result,
    'detail': detail,
    'url': url,
    'proceed': !expired,
  };
}

class ListingAvailabilityService {
  ListingAvailabilityService(
    this.database, {
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final CareerShopperDatabase database;
  final http.Client Function() _clientFactory;

  /// Fetches source text for import; the agent still extracts structured fields.
  Future<Map<String, Object?>> fetchPosting(String jobId) async {
    final job = await JobRepository(database).getJob(jobId);
    if (job == null) throw ArgumentError('Unknown job.');
    final uri = await _sourceUri(jobId, job.applicationUrl);
    return _fetchPosting(jobId, uri);
  }

  Future<Uri?> _sourceUri(String jobId, Uri? applicationUrl) async {
    final observations =
        await (database.select(database.jobObservations)
              ..where((row) => row.jobId.equals(jobId))
              ..orderBy([(row) => OrderingTerm.desc(row.observedAt)]))
            .get();
    final observation =
        observations.where((row) => row.sourceFamily == 'indeed').firstOrNull ??
        observations.firstOrNull;
    return observation == null
        ? applicationUrl
        : Uri.tryParse(observation.sourceUrl);
  }

  Future<Map<String, Object?>> _fetchPosting(String jobId, Uri? uri) async {
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return {'error': 'No usable saved listing URL.', 'request_sent': false};
    }
    if (await _providerBlocked(uri)) {
      return {
        'error': 'Provider previously blocked access; no request sent.',
        'blocked': true,
        'request_sent': false,
        'source_url': uri.toString(),
      };
    }
    final client = _clientFactory();
    var blocked = false;
    late Map<String, Object?> result;
    try {
      final body = await fetchText(
        client,
        uri,
        headers: const {
          'user-agent':
              'Mozilla/5.0 (X11; Linux x86_64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/143.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 20));
      final document = html.parse(body);
      final title = document.querySelector('title')?.text.trim() ?? '';
      if (RegExp(
        r'^(sign in|log in|login|authwall)\b',
        caseSensitive: false,
      ).hasMatch(title)) {
        throw const SourceUnavailableException(
          'The listing requires authentication.',
          reason: 'authentication_required',
        );
      }
      for (final element in document.querySelectorAll(
        'script, style, template, noscript, nav, footer, aside, '
        '[hidden], [aria-hidden="true"]',
      )) {
        element.remove();
      }
      final root = document.querySelector('main') ?? document.body;
      // Keep all posting sections; a collapsed description is still in the HTML.
      for (final element
          in root?.querySelectorAll(
                'p, div, section, article, li, br, h1, h2, h3, h4, h5, h6, tr',
              ) ??
              <Element>[]) {
        element.append(Text('\n'));
      }
      final text = (root?.text ?? '')
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
      result = text.isEmpty
          ? {
              'error': 'The page contained no readable posting text.',
              'blocked': false,
            }
          : {'title': title, 'text': text, 'untrusted_content': true};
    } on SourceUnavailableException catch (error) {
      blocked = true;
      result = {'error': error.message, 'blocked': true};
    } on SourceBackoffException catch (error) {
      blocked = true;
      result = {
        'error': error.message,
        'blocked': true,
        'retry_after_seconds': error.retryAfter?.inSeconds,
      };
    } on Object catch (error) {
      result = {'error': 'Posting retrieval failed: $error', 'blocked': false};
    } finally {
      client.close();
    }
    result = {...result, 'source_url': uri.toString(), 'request_sent': true};
    await database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: const Uuid().v7(),
            eventType: 'listing.posting_fetched',
            subjectType: 'job',
            subjectId: jobId,
            actor: 'system',
            payloadJson: Value(
              jsonEncode({
                'source_url': uri.toString(),
                'error': result['error'],
                if (blocked) 'blocked_host': uri.host,
              }),
            ),
            occurredAt: DateTime.now().toUtc(),
          ),
        );
    return result;
  }

  Future<ListingAvailabilityResult> check(String jobId) async {
    final job = await JobRepository(database).getJob(jobId);
    if (job == null) throw ArgumentError('Unknown job.');
    final uri = job.applicationUrl;
    var result = ListingAvailabilityResult(
      'inconclusive',
      'No usable listing URL.',
      job.applicationUrl?.toString() ?? '',
    );
    if (uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty) {
      if (await _providerBlocked(uri)) {
        result = ListingAvailabilityResult(
          'inconclusive',
          'Provider previously blocked access; no request sent. Document preparation may proceed.',
          uri.toString(),
        );
      } else {
        final client = _clientFactory();
        String? blockedHost;
        try {
          final body = await fetchText(
            client,
            uri,
          ).timeout(const Duration(seconds: 15));
          final document = html.parse(body);
          for (final element in document.querySelectorAll(
            'script, style, template, noscript, nav, footer, aside, [hidden], [aria-hidden="true"]',
          )) {
            element.remove();
          }
          final text =
              (document.querySelector('main') ?? document.body)?.text
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .toLowerCase() ??
              '';
          final closed = RegExp(
            r'\b(?:(?:this |the )?(?:job|position|listing|vacancy) (?:is |has been |has )?(?:no longer available|no longer open|closed|expired|filled|not found)|(?:we are |we.re |is )?no longer accepting applications(?: for this (?:job|position))?)\b',
          ).firstMatch(text);
          result = ListingAvailabilityResult(
            closed == null ? 'inconclusive' : 'expired',
            closed == null
                ? 'No explicit closure message found; document preparation may proceed.'
                : 'Listing reports: ${closed.group(0)}.',
            uri.toString(),
          );
        } on SourceResponseException catch (error) {
          result = ListingAvailabilityResult(
            {404, 410}.contains(error.statusCode) ? 'expired' : 'inconclusive',
            error.message,
            uri.toString(),
          );
        } on SourceUnavailableException catch (error) {
          blockedHost = uri.host;
          result = ListingAvailabilityResult(
            'inconclusive',
            error.message,
            uri.toString(),
          );
        } on Object catch (error) {
          result = ListingAvailabilityResult(
            'inconclusive',
            'Availability could not be confirmed: $error',
            uri.toString(),
          );
        } finally {
          client.close();
        }
        await _record(jobId, result, blockedHost: blockedHost);
        return result;
      }
    }
    await _record(jobId, result);
    return result;
  }

  Future<bool> _providerBlocked(Uri uri) async {
    final prior =
        await (database.select(database.auditEvents)
              ..where(
                (r) => r.eventType.isIn([
                  'listing.availability_checked',
                  'listing.posting_fetched',
                  'listing.block_cleared',
                ]),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.sequence)]))
            .get();
    final hostEvents = prior.where(
      (row) => (jsonDecode(row.payloadJson) as Map)['blocked_host'] == uri.host,
    );
    final blocked =
        hostEvents.isNotEmpty &&
        hostEvents.first.eventType != 'listing.block_cleared';
    final sourceHealth = await database
        .customSelect(
          '''
        SELECT c.source_family, c.config_json FROM source_configs c
        JOIN source_health_records h ON h.source_config_id = c.id
        WHERE h.state IN ('unavailable_blocked', 'unavailable_captcha', 'authentication_required')
          OR h.backoff_until > ?
      ''',
          variables: [Variable(DateTime.now().toUtc())],
          readsFrom: {database.sourceConfigs, database.sourceHealthRecords},
        )
        .get();
    final sourceBlocked = sourceHealth.any((row) {
      final family = row.read<String>('source_family');
      return uri.host == '$family.com' ||
          uri.host.endsWith('.$family.com') ||
          row.read<String>('config_json').contains(uri.host);
    });
    return blocked || sourceBlocked;
  }

  Future<void> clearBlock(String jobId) async {
    final job = await JobRepository(database).getJob(jobId);
    if (job == null) throw ArgumentError('Unknown job.');
    final hosts = {
      ?job.applicationUrl?.host,
      ?(await _sourceUri(jobId, job.applicationUrl))?.host,
    };
    for (final host in hosts) {
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: const Uuid().v7(),
              eventType: 'listing.block_cleared',
              subjectType: 'job',
              subjectId: jobId,
              actor: 'user',
              payloadJson: Value(jsonEncode({'blocked_host': host})),
              occurredAt: DateTime.now().toUtc(),
            ),
          );
    }
  }

  Future<void> _record(
    String jobId,
    ListingAvailabilityResult result, {
    String? blockedHost,
  }) => database.transaction(() async {
    if (result.expired) {
      await (database.update(database.jobs)..where((r) => r.id.equals(jobId)))
          .write(const JobsCompanion(availability: Value('closed')));
      final job = await JobRepository(database).getJob(jobId);
      // A closed posting must not end an application already submitted,
      // or erase a recorded rejection or withdrawal.
      if (job?.applicationOutcome == ApplicationOutcome.active &&
          {
            ApplicationStatus.unknown,
            ApplicationStatus.notApplied,
            ApplicationStatus.readyToApply,
          }.contains(job?.applicationStatus)) {
        await JobRepository(database).setApplicationOutcome(
          jobId,
          ApplicationOutcome.expired,
          actor: 'system',
          origin: 'listing_preflight',
          note: result.detail,
        );
      }
    }
    await database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: const Uuid().v7(),
            eventType: 'listing.availability_checked',
            subjectType: 'job',
            subjectId: jobId,
            actor: 'system',
            payloadJson: Value(
              jsonEncode({...result.toJson(), 'blocked_host': ?blockedHost}),
            ),
            occurredAt: DateTime.now().toUtc(),
          ),
        );
  });
}
