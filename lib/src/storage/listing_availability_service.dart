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
    DateTime Function()? now,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;
  final CareerShopperDatabase database;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;

  DateTime _retryAt(SourceBackoffException error) {
    final delay = error.retryAfter ?? const Duration(hours: 1);
    return _now().toUtc().add(
      delay < const Duration(seconds: 1) ? const Duration(seconds: 1) : delay,
    );
  }

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

  Future<DateTime?> postingRetryAt(String jobId) async {
    final job = await JobRepository(database).getJob(jobId);
    if (job == null) return null;
    final uri = await _sourceUri(jobId, job.applicationUrl);
    if (uri == null) return null;
    return (await _providerAccess(uri)).retryAt;
  }

  Future<Map<String, Object?>> _fetchPosting(String jobId, Uri? uri) async {
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return {'error': 'No usable saved listing URL.', 'request_sent': false};
    }
    final access = await _providerAccess(uri);
    if (access.blocked || access.retryAt != null) {
      return {
        'error': access.blocked
            ? 'Provider previously blocked access; no request sent.'
            : 'Provider rate limit; no request sent. Retry after ${access.retryAt!.toIso8601String()}.',
        if (access.retryAt != null)
          'retry_at': access.retryAt!.toIso8601String(),
        'blocked': true,
        'request_sent': false,
        'source_url': uri.toString(),
      };
    }
    final client = _clientFactory();
    var blocked = false;
    DateTime? retryAt;
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
      retryAt = _retryAt(error);
      result = {
        'error': error.message,
        'blocked': true,
        'retry_after_seconds': error.retryAfter?.inSeconds ?? 3600,
        'retry_at': retryAt.toIso8601String(),
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
                if (blocked || retryAt != null) 'blocked_host': uri.host,
                if (retryAt != null) 'backoff_until': retryAt.toIso8601String(),
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
      final access = await _providerAccess(uri);
      if (access.blocked || access.retryAt != null) {
        result = ListingAvailabilityResult(
          'inconclusive',
          access.blocked
              ? 'Provider previously blocked access; no request sent. Document preparation may proceed.'
              : 'Provider rate limit until ${access.retryAt!.toIso8601String()}; no request sent. Document preparation may proceed.',
          uri.toString(),
        );
      } else {
        final client = _clientFactory();
        String? blockedHost;
        DateTime? retryAt;
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
        } on SourceBackoffException catch (error) {
          blockedHost = uri.host;
          retryAt = _retryAt(error);
          result = ListingAvailabilityResult(
            'inconclusive',
            'Provider rate limit until ${retryAt.toIso8601String()}; document preparation may proceed.',
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
        await _record(
          jobId,
          result,
          blockedHost: blockedHost,
          retryAt: retryAt,
        );
        return result;
      }
    }
    await _record(jobId, result);
    return result;
  }

  Future<({bool blocked, DateTime? retryAt})> _providerAccess(Uri uri) async {
    final now = _now().toUtc();
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
    DateTime? retryAt;
    for (final row in prior) {
      final payload = jsonDecode(row.payloadJson) as Map;
      if (payload['blocked_host'] != uri.host) continue;
      if (row.eventType == 'listing.block_cleared') break;
      var until = DateTime.tryParse(payload['backoff_until'] as String? ?? '');
      // Older posting fetches recorded 429 as a permanent host block and
      // discarded Retry-After. Only this exact rate-limit record is temporary.
      if (until == null &&
          payload['error'] == 'The source requested rate-limit backoff.') {
        until = row.occurredAt.toUtc().add(const Duration(hours: 1));
      }
      if (until == null) return (blocked: true, retryAt: null);
      if (until.isAfter(now) && (retryAt == null || until.isAfter(retryAt))) {
        retryAt = until;
      }
    }
    final sourceHealth = await database
        .customSelect(
          '''SELECT c.source_family, c.config_json, h.state, h.backoff_until
      FROM source_configs c JOIN source_health_records h ON h.source_config_id = c.id
      WHERE h.state IN ('unavailable', 'unavailable_blocked', 'unavailable_captcha', 'authentication_required')
        OR h.backoff_until > ?''',
          variables: [Variable(now)],
          readsFrom: {database.sourceConfigs, database.sourceHealthRecords},
        )
        .get();
    for (final row in sourceHealth) {
      final family = row.read<String>('source_family');
      if (!(uri.host == '$family.com' ||
          uri.host.endsWith('.$family.com') ||
          row.read<String>('config_json').contains(uri.host))) {
        continue;
      }
      if (const {
        'unavailable',
        'unavailable_blocked',
        'unavailable_captcha',
        'authentication_required',
      }.contains(row.read<String>('state'))) {
        return (blocked: true, retryAt: null);
      }
      final until = row.readNullable<DateTime>('backoff_until');
      if (until != null &&
          until.isAfter(now) &&
          (retryAt == null || until.isAfter(retryAt))) {
        retryAt = until;
      }
    }
    return (blocked: false, retryAt: retryAt);
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
    DateTime? retryAt,
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
              jsonEncode({
                ...result.toJson(),
                'blocked_host': ?blockedHost,
                if (retryAt != null) 'backoff_until': retryAt.toIso8601String(),
              }),
            ),
            occurredAt: DateTime.now().toUtc(),
          ),
        );
  });
}
