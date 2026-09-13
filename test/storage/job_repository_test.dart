import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/ingestion/normalization.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late JobRepository repository;

  setUp(() {
    database = CareerShopperDatabase(NativeDatabase.memory());
    repository = JobRepository(database);
  });

  tearDown(() => database.close());

  test('job list retains original source across later imports', () async {
    final first = await repository.ingest(_listing(sourceFamily: 'linkedin'));
    await repository.ingestIntoExistingJob(
      first.jobId,
      _listing(sourceFamily: 'manual'),
    );
    expect((await repository.getJob(first.jobId))!.sourceFamily, 'linkedin');
    expect(
      (await repository.watchAllJobs().first).single.sourceFamily,
      'linkedin',
    );
  });

  test(
    'job notes persist across ingestion and reject stale or unconfirmed saves',
    () async {
      final id = (await repository.ingest(_listing())).jobId;
      final mcp = McpUiTools(database);
      expect(await mcp.call('job_notes_get', {'job_id': id}), {
        'job_id': id,
        'notes': '',
      });
      await expectLater(
        mcp.call('job_notes_set', {
          'job_id': id,
          'notes': 'Ask about on-site work',
          'expected_notes': '',
        }),
        throwsFormatException,
      );
      await mcp.call('job_notes_set', {
        'job_id': id,
        'notes': 'Ask about on-site work',
        'expected_notes': '',
        'confirmed': true,
      });
      await repository.ingest(_listing());
      expect(
        await repository.watchJobNotes(id).first,
        'Ask about on-site work',
      );
      await expectLater(
        repository.saveJobNotes(id, 'Overwrite', expectedNotes: ''),
        throwsStateError,
      );
      expect(
        (await repository.getJob(id))!.reviewState,
        ReviewState.pendingEvaluation,
      );
      await mcp.call('job_notes_set', {
        'job_id': id,
        'notes': '',
        'expected_notes': 'Ask about on-site work',
        'confirmed': true,
      });
      expect(await repository.watchJobNotes(id).first, '');
    },
  );

  test(
    'records an existing application independently of review and availability',
    () async {
      final result = await repository.ingest(
        _listing(sourceFamily: 'greenhouse'),
      );
      final before = await repository.getJob(result.jobId);
      await repository.setApplicationStatus(
        result.jobId,
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'desktop_ui',
      );
      final after = await repository.getJob(result.jobId);
      expect(after!.applicationStatus, ApplicationStatus.applied);
      expect(after.reviewState, before!.reviewState);
      expect(after.availability, before.availability);
      final application = await database
          .select(database.applications)
          .getSingle();
      expect(application.approvedAt, isNull);
      expect(application.appliedAt, isNull);
      await repository.setReviewState(
        result.jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'desktop_ui',
      );
      final approved = await database.select(database.applications).getSingle();
      expect(approved.status, 'applied');
      expect(approved.approvedAt, isNotNull);
      await repository.setApplicationStatus(
        result.jobId,
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'desktop_ui',
      );
      expect(
        await database.select(database.applicationEvents).get(),
        hasLength(1),
      );
      await repository.setApplicationStatus(
        result.jobId,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'desktop_ui',
      );
      final events = await database.select(database.applicationEvents).get();
      expect(events.last.previousStatus, 'applied');
      expect(events.last.newStatus, 'interviewing');
      expect(events.last.origin, 'desktop_ui');
    },
  );

  test('repeated exact application URL augments one logical job', () async {
    final first = await repository.ingest(_listing(sourceFamily: 'greenhouse'));
    final second = await repository.ingest(_listing(sourceFamily: 'indeed'));

    expect(first.created, isTrue);
    expect(second.created, isFalse);
    expect(second.jobId, first.jobId);
    expect(await database.select(database.jobs).get(), hasLength(1));
    expect(await database.select(database.jobObservations).get(), hasLength(2));
  });

  test('blocking employer suppresses inbox but retains history', () async {
    final result = await repository.ingest(_listing());
    await repository.setReviewState(
      result.jobId,
      ReviewState.inbox,
      actor: 'test',
      origin: 'test',
    );
    final visible = await repository.watchInbox().first;
    expect(visible, hasLength(1));

    await repository.setEmployerBlocked(
      visible.single.employerId!,
      blocked: true,
      actor: 'test',
      origin: 'test',
    );

    expect(await repository.watchInbox().first, isEmpty);
    expect(await repository.watchAllJobs().first, hasLength(1));
    expect(await database.select(database.jobObservations).get(), hasLength(1));
  });

  test('approval creates application without changing availability', () async {
    final result = await repository.ingest(_listing());
    await repository.setReviewState(
      result.jobId,
      ReviewState.approved,
      actor: 'test',
      origin: 'test',
    );

    final job = await repository.getJob(result.jobId);
    expect(job?.reviewState, ReviewState.approved);
    expect(job?.availability, JobAvailability.unknown);
    expect(job?.applicationStatus, ApplicationStatus.notApplied);
  });
}

NormalizedListing _listing({String sourceFamily = 'test'}) {
  const description = 'Build reliable backend systems.';
  return NormalizedListing(
    sourceFamily: sourceFamily,
    adapterId: '${sourceFamily}_v1',
    providerJobId: null,
    title: 'Backend Engineer',
    employerName: 'Example, Inc.',
    normalizedEmployerName: normalizeEmployerName('Example, Inc.'),
    location: 'Remote',
    description: description,
    contentHash: contentHash(description),
    sourceUrl: Uri.parse('https://$sourceFamily.example/jobs/123'),
    applicationUrl: Uri.parse('https://jobs.example.com/apply/123'),
    observedAt: DateTime.utc(2026, 9, 4),
  );
}
