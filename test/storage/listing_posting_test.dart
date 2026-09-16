import 'dart:convert';

import 'package:careershopper/src/domain/job.dart';
import 'package:drift/drift.dart' show Value;
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/listing_availability_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late CareerShopperDatabase db;
  late JobRepository jobs;
  late String id;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(db);
    id = await jobs.queueManualUrl(
      Uri.parse('https://www.linkedin.com/jobs/view/123'),
    );
  });
  tearDown(() => db.close());

  test(
    'local posting fetch preserves text and ignores inert CAPTCHA code',
    () async {
      final service = ListingAvailabilityService(
        db,
        clientFactory: () => MockClient((request) async {
          expect(
            request.url.toString(),
            'https://www.linkedin.com/jobs/view/123',
          );
          expect(request.headers['user-agent'], contains('Chrome/'));
          expect(request.headers, isNot(contains('cookie')));
          return http.Response('''<html><head><title>Engineer | LinkedIn</title>
        <script>captcha; access denied; verify you are human;</script></head>
        <body data-recaptcha-v3-integration-lix-value="control">
        <nav>Navigation</nav><main><h1>Engineer</h1><p>Example Co.</p>
        <div class="show-more-less-html__markup"><h2>Responsibilities</h2>
        <p>Build <strong>reliable</strong> APIs &amp; tools.</p>
        <h2>Qualifications</h2><ul><li>Dart</li><li>SQL</li></ul>
        <h2>Benefits</h2><p>Health insurance.</p><h2>Legal notice</h2><p>Equal opportunity.</p>
        </div></main><footer>Unrelated footer</footer></body></html>''', 200);
        }),
      );
      final result = await service.fetchPosting(id);
      expect(result, isNot(contains('error')));
      expect(result['untrusted_content'], true);
      expect(
        result['text'],
        'Engineer\nExample Co.\nResponsibilities\nBuild reliable APIs & tools.\nQualifications\nDart\nSQL\nBenefits\nHealth insurance.\nLegal notice\nEqual opportunity.',
      );
      final saved = (await jobs.getJob(id))!;
      expect(saved.description, isEmpty);
      expect(saved.availability, JobAvailability.unknown);
      expect(await db.select(db.jobSnapshots).get(), hasLength(1));
      expect(
        (await db.select(db.auditEvents).get()).last.eventType,
        'listing.posting_fetched',
      );
    },
  );

  for (final (status, body) in [
    (403, 'Forbidden'),
    (999, 'Request denied'),
    (200, '<main>Verify you are human</main>'),
    (200, '<title>Sign In | LinkedIn</title><main>Sign in to continue</main>'),
  ]) {
    test(
      'HTTP $status $body blocks later posting and availability requests',
      () async {
        var requests = 0;
        final service = ListingAvailabilityService(
          db,
          clientFactory: () => MockClient((_) async {
            requests++;
            return http.Response(body, status);
          }),
        );
        expect((await service.fetchPosting(id))['blocked'], true);
        final other = await jobs.queueManualUrl(
          Uri.parse('https://www.linkedin.com/jobs/view/456'),
        );
        expect((await service.fetchPosting(other))['request_sent'], false);
        expect(
          (await service.check(other)).detail,
          contains('no request sent'),
        );
        expect(requests, 1);
        await service.clearBlock(id);
        expect(requests, 1);
        await service.fetchPosting(id);
        expect(requests, 2);
      },
    );
  }

  test(
    '429 persists a temporary host-wide deadline across service instances',
    () async {
      var now = DateTime.now().toUtc();
      var requests = 0;
      ListingAvailabilityService service() => ListingAvailabilityService(
        db,
        now: () => now,
        clientFactory: () => MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('', 429, headers: {'retry-after': '120'})
              : http.Response('<main>Job details</main>', 200);
        }),
      );
      final result = await service().fetchPosting(id);
      expect(result['blocked'], true);
      expect(
        DateTime.parse(result['retry_at'] as String),
        now.add(const Duration(seconds: 120)),
      );
      final other = await jobs.queueManualUrl(
        Uri.parse('https://www.linkedin.com/jobs/view/456'),
      );
      now = now.add(const Duration(seconds: 119));
      expect((await service().fetchPosting(other))['request_sent'], false);
      expect(
        (await service().check(other)).detail,
        contains('no request sent'),
      );
      expect(requests, 1);
      now = now.add(const Duration(seconds: 1));
      expect((await service().fetchPosting(other))['text'], 'Job details');
      expect(requests, 2);
    },
  );

  test(
    'availability 429 shares the posting cooldown and defaults to one hour',
    () async {
      var now = DateTime.now().toUtc();
      var requests = 0;
      final service = ListingAvailabilityService(
        db,
        now: () => now,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('', 429);
        }),
      );
      await service.check(id);
      expect(
        await service.postingRetryAt(id),
        now.add(const Duration(hours: 1)),
      );
      expect((await service.fetchPosting(id))['request_sent'], false);
      expect(requests, 1);
      now = now.add(const Duration(hours: 1));
      expect((await service.fetchPosting(id))['request_sent'], true);
      expect(requests, 2);
    },
  );

  test('legacy 429 expires without clearing an actual access denial', () async {
    final now = DateTime.now().toUtc();
    Future<void> event(String eventId, String error) async {
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: eventId,
              eventType: 'listing.posting_fetched',
              subjectType: 'job',
              subjectId: id,
              actor: 'system',
              occurredAt: now.subtract(const Duration(hours: 2)),
              payloadJson: Value(
                jsonEncode({
                  'blocked_host': 'www.linkedin.com',
                  'error': error,
                }),
              ),
            ),
          );
    }

    var requests = 0;
    final service = ListingAvailabilityService(
      db,
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response('<main>Job details</main>', 200);
      }),
    );
    await event('legacy-rate', 'The source requested rate-limit backoff.');
    expect((await service.fetchPosting(id))['request_sent'], true);
    await event('denied', 'The source denied access with HTTP 403.');
    await event('newer-rate', 'The source requested rate-limit backoff.');
    expect((await service.fetchPosting(id))['request_sent'], false);
    expect(requests, 1);
  });

  test(
    'Indeed fetch uses saved source and clearing its block preserves apply URL',
    () async {
      final source = Uri.parse('https://www.indeed.com/viewjob?jk=42');
      final application = Uri.parse('https://external.test/apply/42');
      await jobs.ingestIntoExistingJob(
        id,
        NormalizedListing(
          sourceFamily: 'indeed',
          adapterId: 'indeed_public_search_v1',
          providerJobId: '42',
          title: 'Engineer',
          employerName: 'Example',
          normalizedEmployerName: 'example',
          location: 'Remote',
          description: '',
          contentHash: 'empty',
          sourceUrl: source,
          applicationUrl: application,
          observedAt: DateTime.now().toUtc(),
        ),
      );
      var requests = 0;
      final service = ListingAvailabilityService(
        db,
        clientFactory: () => MockClient((request) async {
          expect(request.url, source);
          requests++;
          return http.Response('Forbidden', 403);
        }),
      );
      await service.fetchPosting(id);
      expect((await service.fetchPosting(id))['request_sent'], false);
      await service.clearBlock(id);
      await service.fetchPosting(id);
      expect(requests, 2);
      expect((await jobs.getJob(id))!.applicationUrl, application);
    },
  );

  test(
    'transport failure and empty page are errors, without changing a job',
    () async {
      for (final client in [
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient(
          (_) async =>
              http.Response('<main></main><script>app()</script>', 200),
        ),
      ]) {
        final service = ListingAvailabilityService(
          db,
          clientFactory: () => client,
        );
        final result = await service.fetchPosting(id);
        expect(result, contains('error'));
        expect(result['blocked'], false);
        expect(result, isNot(contains('text')));
        expect((await jobs.getJob(id))!.description, isEmpty);
      }
    },
  );
}
