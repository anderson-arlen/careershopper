import 'package:careershopper/src/domain/job.dart';
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
    id = await jobs.queueManualUrl(Uri.parse('https://jobs.example.test/123'));
  });
  tearDown(() => db.close());

  for (final (status, body, expired) in [
    (404, 'Not found', true),
    (410, 'Gone', true),
    (200, '<main>This position has been filled.</main>', true),
    (200, '<main>This job is no longer available.</main>', true),
    (200, '<main>Job not found</main>', true),
    (200, '<main>We are no longer accepting applications</main>', true),
    (200, '<main>Engineer <button>Apply</button></main>', false),
    (200, '<main></main><script>this job is closed</script>', false),
    (200, '<main>Engineer <div hidden>This job is closed</div></main>', false),
    (200, '<main>Engineer</main><footer>This job is closed</footer>', false),
    (403, 'Access denied', false),
    (429, 'Slow down', false),
    (500, 'Server error', false),
    (200, 'Verify you are human', false),
  ]) {
    test('$status $body', () async {
      final service = ListingAvailabilityService(
        db,
        clientFactory: () => MockClient((request) async {
          expect(request.url.toString(), 'https://jobs.example.test/123');
          return http.Response(body, status);
        }),
      );
      final result = await service.check(id);
      expect(result.expired, expired);
      final job = (await jobs.getJob(id))!;
      expect(
        job.applicationOutcome,
        expired ? ApplicationOutcome.expired : ApplicationOutcome.active,
      );
      expect(
        job.availability,
        expired ? JobAvailability.closed : JobAvailability.unknown,
      );
      expect(result.toJson()['proceed'], !expired);
    });
  }

  test(
    'transport failures pass; blocked hosts are not retried until explicitly cleared',
    () async {
      var calls = 0;
      final service = ListingAvailabilityService(
        db,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response('CAPTCHA', 403);
        }),
      );
      expect((await service.check(id)).expired, false);
      expect((await service.check(id)).detail, contains('no request sent'));
      expect(calls, 1);
      await service.clearBlock(id);
      expect(calls, 1);
      await service.check(id);
      expect(calls, 2);
      await service.clearBlock(id);
      final offline = ListingAvailabilityService(
        db,
        clientFactory: () =>
            MockClient((_) async => throw http.ClientException('offline')),
      );
      expect((await offline.check(id)).expired, false);
    },
  );

  test('expiration preserves an existing employer rejection', () async {
    await jobs.setApplicationStatus(
      id,
      ApplicationStatus.interviewing,
      actor: 'user',
      origin: 'test',
    );
    await jobs.setApplicationOutcome(
      id,
      ApplicationOutcome.rejected,
      actor: 'user',
      origin: 'test',
    );
    final service = ListingAvailabilityService(
      db,
      clientFactory: () => MockClient((_) async => http.Response('Gone', 410)),
    );
    await service.check(id);
    final job = (await jobs.getJob(id))!;
    expect(job.applicationStatus, ApplicationStatus.interviewing);
    expect(job.applicationOutcome, ApplicationOutcome.rejected);
    expect(job.availability, JobAvailability.closed);
  });
}
