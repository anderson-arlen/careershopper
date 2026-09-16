import 'dart:convert';
import 'dart:io';
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

  test(
    'terms survive imports and update without description changes',
    () async {
      final id = (await repository.ingest(
        _listing(
          employmentType: 'PartTime',
          compensationText: 'USD 65 – 85 per hour',
        ),
      )).jobId;
      final first = (await repository.getJob(id))!;
      expect(first.employmentType, 'Part-time');
      expect(first.compensationText, 'USD 65 – 85 per hour');
      await repository.ingestIntoExistingJob(id, _listing());
      expect(
        (await repository.getJob(id))!.compensationText,
        first.compensationText,
      );
      expect((await repository.getJob(id))!.employmentType, 'Part-time');
      await repository.ingestIntoExistingJob(
        id,
        _listing(
          employmentType: 'Contract',
          compensationText: 'USD 90 per hour',
        ),
      );
      final updated = (await repository.watchAllJobs().first).single;
      expect(updated.compensationText, 'USD 90 per hour');
      expect(updated.employmentType, 'Contract');
      expect(await database.select(database.jobSnapshots).get(), hasLength(2));
    },
  );

  test(
    'v19 upgrade recovers saved source terms without changing annual filters',
    () async {
      final dir = await Directory.systemTemp.createTemp('careershopper-terms-');
      final file = File('${dir.path}/db.sqlite');
      var db = CareerShopperDatabase(NativeDatabase(file));
      try {
        final id = (await JobRepository(db).ingest(
          _listing(
            sourceFamily: 'indeed',
            rawPayloadJson: jsonEncode({
              'attributes': [
                {'label': 'Part-time'},
                {'label': 'Contract'},
              ],
              'compensation': {
                'currencyCode': 'USD',
                'baseSalary': {
                  'unitOfWork': 'HOUR',
                  'range': {'min': 65.5, 'max': 85},
                },
              },
            }),
          ),
        )).jobId;
        await db.customStatement(
          'ALTER TABLE job_snapshots DROP COLUMN employment_type',
        );
        await db.customStatement('PRAGMA user_version = 19');
        await db.close();
        db = CareerShopperDatabase(NativeDatabase(file));
        final job = (await JobRepository(db).getJob(id))!;
        expect(job.employmentType, 'Part-time · Contract');
        expect(job.compensationText, 'USD 65.5 – 85 · per hour');
        final snapshot = await db.select(db.jobSnapshots).getSingle();
        expect(jsonDecode(snapshot.compensationJson!)['maximum'], isNull);
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

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

NormalizedListing _listing({
  String sourceFamily = 'test',
  String? employmentType,
  String? compensationText,
  String? rawPayloadJson,
}) {
  const description = 'Build reliable backend systems.';
  return NormalizedListing(
    sourceFamily: sourceFamily,
    employmentType: employmentType,
    compensationText: compensationText,
    rawPayloadJson: rawPayloadJson,
    adapterId: sourceFamily == 'indeed'
        ? 'indeed_public_search_v1'
        : '${sourceFamily}_v1',
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
