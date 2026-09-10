import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/ingestion/normalization.dart';
import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase db;
  late JobRepository jobs;
  final now = DateTime.utc(2026, 9, 7);
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(db);
    await db
        .into(db.profileSnapshots)
        .insert(
          ProfileSnapshotsCompanion.insert(
            id: 'profile',
            manifestJson: '{}',
            manifestHash: 'profile',
            createdAt: now,
          ),
        );
  });
  tearDown(() => db.close());

  Future<String> addJob(
    String name, {
    ReviewState review = ReviewState.inbox,
    ApplicationStatus? status,
    ApplicationOutcome outcome = ApplicationOutcome.active,
    bool documents = false,
    bool staged = false,
    bool running = false,
    bool failed = false,
    String workKind = 'application_materials',
    bool blocked = false,
    int? score,
    DateTime? seen,
    String? title,
    String? employer,
    String? description,
  }) async {
    final id = (await jobs.ingest(
      NormalizedListing(
        sourceFamily: 'test',
        adapterId: 'test',
        providerJobId: name,
        title: title ?? name,
        employerName: employer ?? name,
        normalizedEmployerName: (employer ?? name).toLowerCase(),
        location: 'Remote',
        description: description ?? name,
        contentHash: contentHash(description ?? name),
        sourceUrl: Uri.parse('https://example.test/$name'),
        applicationUrl: Uri.parse('https://example.test/$name'),
        observedAt: seen ?? now,
      ),
      initialReviewState: review,
    )).jobId;
    final row = await (db.select(
      db.jobs,
    )..where((r) => r.id.equals(id))).getSingle();
    if (status != null || documents || outcome != ApplicationOutcome.active) {
      await db
          .into(db.applications)
          .insert(
            ApplicationsCompanion.insert(
              id: 'app-$name',
              jobId: id,
              status: Value(
                (status ?? ApplicationStatus.notApplied).persistedName,
              ),
              updatedAt: now,
              outcome: Value(outcome.persistedName),
            ),
          );
    }
    if (documents) {
      await db
          .into(db.materialSets)
          .insert(
            MaterialSetsCompanion.insert(
              id: 'docs-$name',
              applicationId: 'app-$name',
              jobSnapshotId: row.currentSnapshotId!,
              profileSnapshotId: 'profile',
              resumeMarkdown: 'Resume',
              coverLetterMarkdown: const Value('Letter'),
              rendererVersion: 'test',
              templateId: 'test',
              createdAt: now,
              staged: Value(staged),
            ),
          );
    }
    if (running || failed) {
      await db
          .into(db.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'order-$name',
              kind: workKind,
              status: failed ? 'failed' : 'running',
              scopeJson: '{}',
              promptVersion: 'test',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.aiWorkItems)
          .insert(
            AiWorkItemsCompanion.insert(
              id: 'item-$name',
              workOrderId: 'order-$name',
              subjectId: id,
              status: failed ? 'failed' : 'running',
              error: failed
                  ? const Value('AI run interrupted. Retry required.')
                  : const Value.absent(),
              idempotencyKey: 'item-$name',
              updatedAt: now,
            ),
          );
    }
    if (score != null) {
      await db
          .into(db.jobEvaluations)
          .insert(
            JobEvaluationsCompanion.insert(
              id: 'eval-$name',
              jobSnapshotId: row.currentSnapshotId!,
              profileSnapshotId: 'profile',
              personalFitScore: score,
              attainabilityScore: score,
              overallScore: score,
              confidence: 1,
              dimensionsJson: '{}',
              strengthsJson: '[]',
              concernsJson: '[]',
              unknownsJson: '[]',
              summary: 'Fit',
              evidenceJson: '[]',
              promptVersion: 'test',
              agentJson: '{}',
              createdAt: now,
            ),
          );
      await (db.update(db.jobs)..where((r) => r.id.equals(id))).write(
        JobsCompanion(currentEvaluationId: Value('eval-$name')),
      );
    }
    if (blocked) {
      await jobs.setEmployerBlocked(
        row.employerId!,
        blocked: true,
        actor: 'test',
        origin: 'test',
      );
    }
    return id;
  }

  test(
    'word scores count matching fields once and outrank AI scores with stable ties',
    () async {
      final first = await addJob(
        'first',
        title: 'Rust Developer',
        employer: 'Acme',
        description: 'Build API API API',
        score: 90,
        seen: now.add(const Duration(seconds: 2)),
      );
      final best = await addJob(
        'best',
        title: 'Rust API Engineer',
        employer: 'Rust API Labs',
        description: 'Rust API',
        score: 10,
      );
      final tied = await addJob(
        'tied',
        title: 'Rust Programmer',
        employer: 'Other',
        description: 'Maintain APIs',
        score: 80,
        seen: now.add(const Duration(seconds: 1)),
      );
      for (final view in ['inbox', 'all']) {
        final source =
            await (view == 'inbox' ? jobs.watchInbox() : jobs.watchAllJobs())
                .first;
        for (final query in ['rust API', ' RUST\tapi rust API ']) {
          final matches = searchJobsByText(source, query);
          expect(matches.map((m) => m.job.id), [best, first, tied]);
          expect(matches.map((m) => m.score), [6, 2, 2]);
          final response = await rpc(db, 'tools/call', {
            'name': 'jobs_search',
            'arguments': {'view': view, 'query': query, 'limit': 2},
          });
          final data = (response['result'] as Map)['structuredContent'] as Map;
          expect(data['total_count'], 3);
          expect((data['jobs'] as List).map((j) => j['id']), [best, first]);
          expect((data['jobs'] as List).map((j) => j['search_score']), [6, 2]);
        }
        expect(
          searchJobsByText(source, '').map((m) => m.job.id),
          source.map((j) => j.id),
        );
      }
      expect((await jobs.getJob(best))!.overallScore, 10);
    },
  );

  test(
    'live list search and MCP match title, body, and employer within each view',
    () async {
      final title = await addJob('title', title: 'Backend Engineer', score: 90);
      final body = await addJob(
        'body',
        description: 'Maintain PostgreSQL with 100%_coverage.',
        score: 80,
      );
      final employer = await addJob('employer', employer: 'Coral', score: 70);
      final hidden = await addJob(
        'hidden',
        title: 'Backend Engineer',
        review: ReviewState.discarded,
      );
      for (final view in ['inbox', 'all']) {
        final source =
            await (view == 'inbox' ? jobs.watchInbox() : jobs.watchAllJobs())
                .first;
        for (final (term, expected) in [
          (' BACKEND ', view == 'inbox' ? [title] : [title, hidden]),
          ('postgre', [body]),
          ('CORAL', [employer]),
          ('%_', [body]),
          ('no such job', <String>[]),
          ('remote', <String>[]),
          ('  ', source.map((j) => j.id).toList()),
        ]) {
          final matches = searchJobsByText(source, term);
          final local = matches.map((match) => match.job).toList();
          expect(local.map((j) => j.id).toSet(), expected.toSet());
          final response = await rpc(db, 'tools/call', {
            'name': 'jobs_search',
            'arguments': {'view': view, 'query': term},
          });
          final data = (response['result'] as Map)['structuredContent'] as Map;
          expect(
            (data['jobs'] as List).map((j) => j['id']),
            local.map((j) => j.id),
          );
          expect(data['total_count'], local.length);
        }
      }
    },
  );

  test(
    'queue includes only review and apply actions across independent states',
    () async {
      final expected = <String>{};
      for (final review in ReviewState.values) {
        for (final status in ApplicationStatus.values) {
          for (final outcome in ApplicationOutcome.values) {
            final id = await addJob(
              '${review.name}-${status.name}-${outcome.name}',
              review: review,
              status: status,
              outcome: outcome,
              documents: true,
            );
            if (outcome == ApplicationOutcome.active &&
                [ReviewState.inbox, ReviewState.approved].contains(review) &&
                [
                  ApplicationStatus.notApplied,
                  ApplicationStatus.readyToApply,
                ].contains(status)) {
              expected.add(id);
            }
          }
        }
      }
      expected.add(await addJob('unreviewed-no-application'));
      await addJob('approved-no-documents', review: ReviewState.approved);
      await addJob(
        'status-without-documents',
        review: ReviewState.approved,
        status: ApplicationStatus.readyToApply,
      );
      await addJob(
        'staged',
        review: ReviewState.approved,
        documents: true,
        staged: true,
      );
      await addJob(
        'regenerating',
        review: ReviewState.approved,
        documents: true,
        running: true,
      );
      await addJob(
        'blocked-ready',
        review: ReviewState.approved,
        documents: true,
        blocked: true,
      );
      final queue = await jobs.watchInbox().first;
      expect(queue.map((job) => job.id).toSet(), expected);
      expect(
        queue
            .where((job) => job.reviewState == ReviewState.approved)
            .every((job) => job.readyToApply),
        isTrue,
      );
      expect(
        await jobs.watchAllJobs().first,
        hasLength(
          ReviewState.values.length *
                  ApplicationStatus.values.length *
                  ApplicationOutcome.values.length +
              6,
        ),
      );
      expect(await db.select(db.applicationEvents).get(), isEmpty);
      expect(
        (await db.select(db.jobs).get()).every(
          (job) => job.availability == 'unknown',
        ),
        isTrue,
      );
    },
  );

  test(
    'AI failures return to the ranked inbox with errors and leave on retry',
    () async {
      final draft = await addJob(
        'failed-draft',
        review: ReviewState.approved,
        failed: true,
        score: 85,
      );
      final imported = await addJob(
        'failed-import',
        review: ReviewState.pendingEvaluation,
        failed: true,
        workKind: 'manual_job_import',
      );
      await addJob(
        'declined-failure',
        review: ReviewState.discarded,
        failed: true,
      );
      await addJob(
        'blocked-failure',
        review: ReviewState.approved,
        failed: true,
        blocked: true,
      );
      await addJob(
        'ended-failure',
        review: ReviewState.approved,
        failed: true,
        outcome: ApplicationOutcome.withdrawn,
      );
      final stream = StreamIterator(jobs.watchInbox());
      addTearDown(stream.cancel);
      await stream.moveNext();
      expect(stream.current.map((j) => j.id), [draft, imported]);
      expect(
        stream.current.every(
          (j) => j.aiError == 'AI run interrupted. Retry required.',
        ),
        isTrue,
      );
      final response = await rpc(db, 'tools/call', {
        'name': 'jobs_search',
        'arguments': {'view': 'inbox'},
      });
      final results = (response['result'] as Map)['structuredContent'] as Map;
      expect(
        (results['jobs'] as List).map((j) => (j as Map)['ai_error']),
        everyElement('AI run interrupted. Retry required.'),
      );
      await db
          .into(db.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'retry',
              kind: 'application_materials',
              status: 'running',
              scopeJson: '{}',
              promptVersion: 'test',
              createdAt: now.add(const Duration(minutes: 1)),
              updatedAt: now,
            ),
          );
      await db
          .into(db.aiWorkItems)
          .insert(
            AiWorkItemsCompanion.insert(
              id: 'retry-item',
              workOrderId: 'retry',
              subjectId: draft,
              status: 'running',
              idempotencyKey: 'retry-item',
              updatedAt: now,
            ),
          );
      while (stream.current.any((j) => j.id == draft)) {
        await stream.moveNext().timeout(const Duration(seconds: 3));
      }
      expect(stream.current.single.id, imported);
      await (db.update(db.aiWorkOrders)..where((r) => r.id.equals('retry')))
          .write(const AiWorkOrdersCompanion(status: Value('completed')));
      await (db.update(db.aiWorkItems)..where((r) => r.id.equals('retry-item')))
          .write(const AiWorkItemsCompanion(status: Value('completed')));
      expect((await jobs.getJob(draft))!.aiError, isNull);
      expect((await jobs.watchInbox().first).map((j) => j.id), [imported]);
    },
  );

  test(
    'inbox prioritizes AI failures before fit scores in both UI and MCP',
    () async {
      final normalHigh = await addJob(
        'normal-high',
        score: 98,
        seen: now.add(const Duration(days: 1)),
      );
      final normalLow = await addJob('normal-low', score: 75);
      final failedLow = await addJob(
        'failed-low',
        review: ReviewState.approved,
        failed: true,
        score: 40,
      );
      final failedUnscored = await addJob(
        'failed-unscored',
        review: ReviewState.pendingEvaluation,
        failed: true,
        workKind: 'search_analysis',
      );
      final failedHigh = await addJob(
        'failed-high',
        review: ReviewState.approved,
        failed: true,
        score: 85,
      );
      final expected = [
        failedHigh,
        failedLow,
        failedUnscored,
        normalHigh,
        normalLow,
      ];
      expect((await jobs.watchInbox().first).map((j) => j.id), expected);
      final response = await rpc(db, 'tools/call', {
        'name': 'jobs_search',
        'arguments': {'view': 'inbox'},
      });
      final results = (response['result'] as Map)['structuredContent'] as Map;
      expect((results['jobs'] as List).map((j) => (j as Map)['id']), expected);
      expect((await jobs.watchAllJobs().first).first.id, normalHigh);
    },
  );

  test(
    'queue reacts to document publication and generation completion',
    () async {
      final id = await addJob(
        'release',
        review: ReviewState.approved,
        documents: true,
        staged: true,
      );
      final stream = StreamIterator(jobs.watchInbox());
      addTearDown(stream.cancel);
      await stream.moveNext();
      expect(stream.current, isEmpty);
      await (db.update(db.materialSets)
            ..where((r) => r.id.equals('docs-release')))
          .write(const MaterialSetsCompanion(staged: Value(false)));
      await stream.moveNext().timeout(const Duration(seconds: 5));
      expect(stream.current.single.id, id);
      expect(stream.current.single.readyToApply, isTrue);

      final other = await addJob(
        'regenerate',
        review: ReviewState.approved,
        documents: true,
        running: true,
      );
      final generationStream = StreamIterator(jobs.watchInbox());
      addTearDown(generationStream.cancel);
      await generationStream.moveNext();
      expect(generationStream.current.map((job) => job.id), [id]);
      await (db.update(db.aiWorkOrders)
            ..where((r) => r.id.equals('order-regenerate')))
          .write(const AiWorkOrdersCompanion(status: Value('completed')));
      await generationStream.moveNext().timeout(const Duration(seconds: 5));
      expect(generationStream.current.map((job) => job.id), contains(other));
      await jobs.setApplicationStatus(
        id,
        ApplicationStatus.applied,
        actor: 'test',
        origin: 'test',
      );
      expect((await jobs.watchInbox().first).map((job) => job.id), [other]);
      expect(await jobs.watchAllJobs().first, hasLength(2));
    },
  );

  test(
    'MCP discovers and returns the same ranked queue, filtering before limits',
    () async {
      final high = await addJob(
        'high-ready',
        review: ReviewState.approved,
        documents: true,
        score: 95,
        seen: now.subtract(const Duration(days: 4)),
      );
      final newer = await addJob('new-review', score: 80);
      final older = await addJob(
        'old-review',
        score: 80,
        seen: now.subtract(const Duration(days: 1)),
      );
      final unscored = await addJob(
        'unscored',
        seen: now.add(const Duration(days: 1)),
      );
      await addJob(
        'awaiting-documents',
        review: ReviewState.approved,
        score: 100,
      );
      final queue = await jobs.watchInbox().first;
      expect(queue.map((job) => job.id), [high, newer, older, unscored]);

      final discovery = await rpc(db, 'tools/list', {});
      final tool = ((discovery['result'] as Map)['tools'] as List)
          .cast<Map>()
          .singleWhere((tool) => tool['name'] == 'jobs_search');
      expect(((tool['inputSchema'] as Map)['properties'] as Map)['view'], {
        'type': 'string',
        'enum': ['all', 'inbox'],
        'default': 'all',
      });
      Future<Map> search(Map<String, Object?> arguments) async {
        final response = await rpc(db, 'tools/call', {
          'name': 'jobs_search',
          'arguments': arguments,
        });
        return (response['result'] as Map)['structuredContent'] as Map;
      }

      final inbox = await search({'view': 'inbox'});
      expect(inbox['total_count'], queue.length);
      final limited = await search({'view': 'inbox', 'limit': 1});
      expect(limited['count'], 1);
      expect(limited['total_count'], queue.length);
      expect(
        (inbox['jobs'] as List).map((job) => job['id']),
        queue.map((job) => job.id),
      );
      expect((inbox['jobs'] as List).first['ready_to_apply'], true);
      final filtered = await search({
        'view': 'inbox',
        'query': 'review',
        'limit': 1,
      });
      expect((filtered['jobs'] as List).single['id'], newer);
      final all = await search({});
      expect(all['count'], 5);
      expect((all['jobs'] as List).first['id'], unscored);
      final invalid = await rpc(db, 'tools/call', {
        'name': 'jobs_search',
        'arguments': {'view': 'invalid'},
      });
      expect(invalid['error'], isNotNull);
    },
  );

  test(
    'stage and outcome writes preserve each other through UI service and MCP',
    () async {
      final id = await addJob(
        'progress',
        review: ReviewState.approved,
        status: ApplicationStatus.interviewing,
        documents: true,
      );
      await jobs.setApplicationOutcome(
        id,
        ApplicationOutcome.rejected,
        actor: 'user',
        origin: 'desktop_ui',
      );
      var job = (await jobs.getJob(id))!;
      expect(job.applicationStatus, ApplicationStatus.interviewing);
      expect(job.applicationOutcome, ApplicationOutcome.rejected);
      expect(job.reviewState, ReviewState.approved);
      expect(job.availability, JobAvailability.unknown);
      expect(await jobs.watchInbox().first, isEmpty);

      Future<Map> change(String tool, Map<String, Object?> arguments) async {
        final response = await rpc(db, 'tools/call', {
          'name': tool,
          'arguments': {'job_id': id, 'confirmed': true, ...arguments},
        });
        return (response['result'] as Map)['structuredContent'] as Map;
      }

      final updated = await change('application_status_set', {
        'application_status': 'offer',
      });
      expect(updated['application_status'], 'offer');
      expect(updated['application_outcome'], 'rejected');
      final withdrawn = await change('application_outcome_set', {
        'application_outcome': 'withdrawn',
        'note': 'Accepted another role.',
      });
      expect(withdrawn['application_status'], 'offer');
      expect(withdrawn['application_outcome'], 'withdrawn');
      final legacy = await change('application_status_set', {
        'application_status': 'rejected',
      });
      expect(legacy['application_status'], 'offer');
      expect(legacy['application_outcome'], 'rejected');
      await change('application_outcome_set', {
        'application_outcome': 'active',
      });
      job = (await jobs.getJob(id))!;
      expect(job.applicationStatus, ApplicationStatus.offer);
      expect(job.applicationOutcome, ApplicationOutcome.active);
      final events = await db.select(db.applicationEvents).get();
      expect(events.single.previousStatus, 'interviewing');
      expect(events.single.newStatus, 'offer');
      final audit = await (db.select(
        db.auditEvents,
      )..where((r) => r.eventType.equals('application.outcome_changed'))).get();
      expect(audit, hasLength(4));
      expect(
        audit.any(
          (event) => event.payloadJson.contains('Accepted another role.'),
        ),
        isTrue,
      );
      expect((await db.select(db.applications).getSingle()).appliedAt, isNull);

      for (final arguments in [
        {'application_outcome': 'withdrawn', 'confirmed': false},
        {'application_outcome': 'invalid', 'confirmed': true},
      ]) {
        final response = await rpc(db, 'tools/call', {
          'name': 'application_outcome_set',
          'arguments': {'job_id': id, ...arguments},
        });
        expect(response['error'], isNotNull);
      }
      final scoped = await rpc(db, 'tools/call', {
        'name': 'application_outcome_set',
        'arguments': {
          'job_id': id,
          'application_outcome': 'withdrawn',
          'confirmed': true,
        },
      }, workOrderId: 'work-order');
      expect(scoped['error'], isNotNull);
      expect(
        (await jobs.getJob(id))!.applicationOutcome,
        ApplicationOutcome.active,
      );
    },
  );

  test(
    'v11 migration retains terminal outcome, recorded stage, and original events',
    () async {
      final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning,
      );
      final interviewing = await addJob(
        'interview-history',
        status: ApplicationStatus.applied,
      );
      await jobs.setApplicationStatus(
        interviewing,
        ApplicationStatus.interviewing,
        actor: 'test',
        origin: 'test',
      );
      final offer = await addJob(
        'offer-history',
        status: ApplicationStatus.offer,
      );
      await db
          .into(db.applicationEvents)
          .insert(
            ApplicationEventsCompanion.insert(
              id: 'terminal-event',
              applicationId: 'app-offer-history',
              previousStatus: const Value('offer'),
              newStatus: 'withdrawn',
              actor: 'user',
              origin: 'test',
              occurredAt: now,
            ),
          );
      final unknown = await addJob(
        'no-history',
        status: ApplicationStatus.notApplied,
      );
      final dated = await addJob('dated', status: ApplicationStatus.applied);
      final hired = await addJob('hired', status: ApplicationStatus.hired);
      await (db.update(db.applications)
            ..where((r) => r.jobId.isIn([interviewing, unknown, dated])))
          .write(const ApplicationsCompanion(status: Value('rejected')));
      await (db.update(db.applications)..where((r) => r.jobId.equals(offer)))
          .write(const ApplicationsCompanion(status: Value('withdrawn')));
      await (db.update(db.applications)..where((r) => r.jobId.equals(dated)))
          .write(ApplicationsCompanion(appliedAt: Value(now)));
      final originalEvents = (await db.select(db.applicationEvents).get())
          .map((e) => e.toJson())
          .toList();
      final dir = await Directory.systemTemp.createTemp('inbox-migration-');
      final file = File('${dir.path}/legacy.sqlite3');
      await db.customStatement('VACUUM INTO ?', [file.path]);
      var migrated = CareerShopperDatabase(NativeDatabase(file));
      try {
        await migrated.customSelect('SELECT * FROM applications').get();
        // Reconstruct the legacy schema, before state-change tracking existed.
        for (final name in [
          'job_state_changed',
          'application_state_created',
          'application_state_changed',
          'employer_block_state_changed',
        ]) {
          await migrated.customStatement('DROP TRIGGER $name');
        }
        await migrated.customStatement(
          'ALTER TABLE jobs DROP COLUMN state_changed_at',
        );
        await migrated.customStatement(
          'ALTER TABLE applications DROP COLUMN outcome',
        );
        await migrated.customStatement('PRAGMA user_version = 11');
        await migrated.close();
        migrated = CareerShopperDatabase(NativeDatabase(file));
        final rows = await migrated.select(migrated.applications).get();
        final byJob = {for (final row in rows) row.jobId: row};
        expect(byJob[interviewing]!.status, 'interviewing');
        expect(byJob[interviewing]!.outcome, 'rejected');
        expect(byJob[offer]!.status, 'offer');
        expect(byJob[offer]!.outcome, 'withdrawn');
        expect(byJob[unknown]!.status, 'unknown');
        expect(byJob[dated]!.status, 'applied');
        expect(byJob[dated]!.appliedAt?.toUtc(), now);
        expect(byJob[hired]!.status, 'hired');
        expect(byJob[hired]!.outcome, 'active');
        expect(
          (await migrated.select(migrated.applicationEvents).get()).map(
            (e) => e.toJson(),
          ),
          originalEvents,
        );
      } finally {
        await migrated.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

Future<Map<String, dynamic>> rpc(
  CareerShopperDatabase db,
  String method,
  Map<String, Object?> params, {
  String? workOrderId,
}) async {
  final controller = StreamController<List<int>>();
  final sink = IOSink(controller.sink);
  final output = controller.stream.transform(utf8.decoder).join();
  await McpServer(db, workOrderId: workOrderId).serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params})}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return jsonDecode(await output) as Map<String, dynamic>;
}
