import 'dart:io';
import 'package:careershopper/src/domain/job_statistics.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'conversion ratios use their respective application and interview counts',
    () {
      const stats = JobStatistics(
        found: 120,
        applied: 30,
        interviewed: 12,
        offers: 3,
      );
      expect(stats.jobsFoundPerApplication, 4);
      expect(stats.applicationsPerInterview, 2.5);
      const noApplications = JobStatistics(
        found: 100,
        applied: 0,
        interviewed: 0,
        offers: 0,
      );
      expect(noApplications.jobsFoundPerApplication, isNull);
      const uneven = JobStatistics(
        found: 10,
        applied: 5,
        interviewed: 3,
        offers: 0,
      );
      expect(uneven.conversionRatiosToJson(), {
        'jobs_found_per_application': 2.0,
        'applications_per_interview': 5 / 3,
      });
      for (final found in [0, 100]) {
        final noInterviews = JobStatistics(
          found: found,
          applied: found,
          interviewed: 0,
          offers: 0,
        );
        expect(noInterviews.conversionRatiosToJson(), {
          'jobs_found_per_application': found == 0 ? null : 1.0,
          'applications_per_interview': null,
        });
      }
    },
  );

  test('Sankey flows conserve jobs, including zero and uneven stages', () {
    for (final stats in [
      const JobStatistics(found: 0, applied: 0, interviewed: 0, offers: 0),
      const JobStatistics(found: 100, applied: 0, interviewed: 0, offers: 0),
      const JobStatistics(
        found: 100,
        applied: 100,
        interviewed: 100,
        offers: 100,
      ),
      const JobStatistics(found: 100000, applied: 3, interviewed: 2, offers: 1),
      const JobStatistics(found: 120, applied: 30, interviewed: 12, offers: 3),
    ]) {
      final nodes = stats.sankeyNodes;
      final links = stats.sankeyLinks;
      final accepted = nodes.singleWhere((node) => node.id == 'hired');
      expect(accepted.label, 'Accepted offer');
      expect(accepted.terminal, true);
      expect(links.every((link) => link.count >= 0), isTrue);
      for (final node in nodes) {
        final incoming = links.where((l) => l.target == node.id);
        final outgoing = links.where((l) => l.source == node.id);
        if (node.column != 0) {
          expect(incoming.fold<int>(0, (sum, l) => sum + l.count), node.count);
        }
        if (outgoing.isNotEmpty) {
          expect(outgoing.fold<int>(0, (sum, l) => sum + l.count), node.count);
        }
      }
      expect(
        nodes.where((n) => n.remainder).fold<int>(0, (sum, n) => sum + n.count),
        stats.found,
      );
    }
  });

  test(
    'pending branches precede terminal outcomes and ribbons follow their order',
    () {
      const stats = JobStatistics(
        found: 3,
        applied: 1,
        interviewed: 1,
        offers: 1,
        branches: {
          JobFlowBranch.inbox: 1,
          JobFlowBranch.pendingProcessing: 1,
          JobFlowBranch.hired: 1,
        },
      );
      final nodes = stats.sankeyNodes;
      final links = stats.sankeyLinks;
      expect(nodes.where((n) => n.column == 2).map((n) => n.id), [
        'applied',
        'inbox',
        'pending_processing',
        'ai_rejected',
        'user_rejected',
      ]);
      expect(nodes.where((n) => n.column == 3).map((n) => n.id), [
        'interviewed',
        'applied_waiting',
        'applied_rejected',
      ]);
      expect(nodes.where((n) => n.column == 4).map((n) => n.id), [
        'offers',
        'interview_waiting',
        'interview_rejected',
      ]);
      expect(nodes.where((n) => n.column == 5).map((n) => n.id), [
        'hired',
        'offer_waiting',
        'offer_withdrawn',
        'offer_rejected',
      ]);
      for (final node in nodes) {
        final targets = links
            .where((l) => l.source == node.id)
            .map((l) => nodes.indexWhere((n) => n.id == l.target))
            .toList();
        expect(targets, orderedEquals([...targets]..sort()));
      }
      expect(nodes.singleWhere((n) => n.id == 'hired').count, 1);
    },
  );

  late CareerShopperDatabase db;
  late JobRepository jobs;
  final now = DateTime(2030, 8, 15, 12);
  setUp(() {
    db = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed(
    String id,
    DateTime found,
    String stage, {
    String outcome = 'active',
    String review = 'pending_evaluation',
    DateTime? appliedAt,
  }) async {
    await db
        .into(db.jobs)
        .insert(
          JobsCompanion.insert(
            id: id,
            firstSeenAt: found,
            lastSeenAt: now,
            createdAt: found,
            updatedAt: found,
            reviewState: Value(review),
            availability: const Value('closed'),
          ),
        );
    await db
        .into(db.applications)
        .insert(
          ApplicationsCompanion.insert(
            id: id,
            jobId: id,
            status: Value(stage),
            outcome: Value(outcome),
            updatedAt: found,
            appliedAt: Value(appliedAt),
          ),
        );
  }

  test(
    'expired is terminal at each furthest stage without losing progress',
    () async {
      for (final stage in ['not_applied', 'applied', 'interviewing', 'offer']) {
        await seed(stage, now, stage, outcome: 'expired');
      }
      final stats = await jobs.watchStatistics().first;
      expect(stats.found, 4);
      expect(stats.applied, 3);
      expect(stats.interviewed, 2);
      expect(stats.offers, 1);
      final expired = stats.sankeyNodes
          .where((n) => n.label == 'Expired')
          .toList();
      expect(expired, hasLength(4));
      expect(expired.every((n) => n.terminal && n.count == 1), true);
    },
  );

  test(
    'funnel counts unique state-change cohorts and retained stage history',
    () async {
      await seed(
        'old',
        DateTime(2029, 12, 31, 23, 59),
        'offer',
        outcome: 'rejected',
      );
      await seed('year', DateTime(2030), 'hired');
      await seed('month', DateTime(2030, 8), 'applied');
      await seed(
        'today',
        DateTime(2030, 8, 15),
        'interviewing',
        outcome: 'withdrawn',
      );
      await seed('ready', now, 'ready_to_apply');
      await seed(
        'unknown',
        now,
        'unknown',
        review: 'discarded',
        outcome: 'rejected',
      );
      await seed('history', now, 'applied', review: 'hidden_low_score');
      for (var index = 0; index < 3; index++) {
        await db
            .into(db.applicationEvents)
            .insert(
              ApplicationEventsCompanion.insert(
                id: 'event-$index',
                applicationId: 'history',
                previousStatus: const Value('offer'),
                newStatus: 'applied',
                actor: 'user',
                origin: 'test',
                occurredAt: now,
              ),
            );
      }
      final expected = {
        StatisticsPeriod.today: [4, 2, 2, 1],
        StatisticsPeriod.thisMonth: [5, 3, 2, 1],
        StatisticsPeriod.thisYear: [6, 4, 3, 2],
        StatisticsPeriod.allTime: [7, 5, 4, 3],
      };
      for (final entry in expected.entries) {
        final stats = await jobs
            .watchStatistics(changedSince: entry.key.start(now))
            .first;
        expect(
          stats.toJson().values.toList(),
          entry.value,
          reason: entry.key.label,
        );
        expect(
          stats.sankeyLinks
              .where((l) => l.source == 'found')
              .fold<int>(0, (sum, l) => sum + l.count),
          stats.found,
        );
        expect(
          stats.sankeyNodes
              .where((n) => n.remainder)
              .fold<int>(0, (sum, n) => sum + n.count),
          stats.found,
        );
      }
    },
  );

  test('Sankey splits each furthest stage by review and outcome', () async {
    final cases = [
      (
        'ai',
        'not_applied',
        'active',
        'hidden_low_score',
        JobFlowBranch.aiRejected,
      ),
      (
        'user',
        'not_applied',
        'active',
        'discarded',
        JobFlowBranch.userRejected,
      ),
      (
        'not-applied',
        'ready_to_apply',
        'active',
        'approved',
        JobFlowBranch.pendingProcessing,
      ),
      (
        'filtered',
        'not_applied',
        'active',
        'hidden_by_search',
        JobFlowBranch.filteredBySearch,
      ),
      (
        'pre-withdrawn',
        'not_applied',
        'withdrawn',
        'hidden_low_score',
        JobFlowBranch.userRejected,
      ),
      (
        'applied-waiting',
        'applied',
        'active',
        'hidden_low_score',
        JobFlowBranch.appliedWaiting,
      ),
      (
        'applied-rejected',
        'applied',
        'rejected',
        'approved',
        JobFlowBranch.appliedRejected,
      ),
      (
        'applied-withdrawn',
        'applied',
        'withdrawn',
        'approved',
        JobFlowBranch.appliedWithdrawn,
      ),
      (
        'interview-waiting',
        'interviewing',
        'active',
        'approved',
        JobFlowBranch.interviewWaiting,
      ),
      (
        'interview-rejected',
        'interviewing',
        'rejected',
        'approved',
        JobFlowBranch.interviewRejected,
      ),
      (
        'interview-withdrawn',
        'interviewing',
        'withdrawn',
        'approved',
        JobFlowBranch.interviewWithdrawn,
      ),
      (
        'offer-waiting',
        'offer',
        'active',
        'approved',
        JobFlowBranch.offerWaiting,
      ),
      (
        'offer-withdrawn',
        'offer',
        'rejected',
        'approved',
        JobFlowBranch.offerWithdrawn,
      ),
      (
        'offer-rejected',
        'offer',
        'withdrawn',
        'approved',
        JobFlowBranch.offerRejected,
      ),
      ('hired', 'hired', 'active', 'approved', JobFlowBranch.hired),
    ];
    final expected = <JobFlowBranch, int>{};
    for (final c in cases) {
      await seed(c.$1, now, c.$2, outcome: c.$3, review: c.$4);
      expected.update(c.$5, (n) => n + 1, ifAbsent: () => 1);
    }
    final stats = await jobs.watchStatistics().first;
    expect(stats.branches, expected);
    expect(stats.toJson(), {
      'found': 15,
      'applied': 10,
      'interviewed': 7,
      'offers': 4,
    });
    for (final node in stats.sankeyNodes) {
      final incoming = stats.sankeyLinks.where((l) => l.target == node.id);
      final outgoing = stats.sankeyLinks.where((l) => l.source == node.id);
      if (node.column != 0) {
        expect(incoming.fold<int>(0, (n, l) => n + l.count), node.count);
      }
      if (outgoing.isNotEmpty) {
        expect(outgoing.fold<int>(0, (n, l) => n + l.count), node.count);
      }
    }
    expect(stats.branches.values.fold<int>(0, (n, c) => n + c), stats.found);
    await seed('older', DateTime(2029), 'offer', outcome: 'rejected');
    expect(
      (await jobs
              .watchStatistics(changedSince: StatisticsPeriod.today.start(now))
              .first)
          .branches,
      expected,
    );
    final values = <JobStatistics>[];
    final subscription = jobs.watchStatistics().listen(values.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    await db
        .update(db.applications)
        .replace(
          ApplicationsCompanion.insert(
            id: 'offer-waiting',
            jobId: 'offer-waiting',
            status: const Value('offer'),
            outcome: const Value('rejected'),
            updatedAt: now,
          ),
        );
    await pumpEventQueue();
    expect(values.last.branches[JobFlowBranch.offerWaiting] ?? 0, 0);
    expect(values.last.branches[JobFlowBranch.offerWithdrawn], 3);
    expect(values.last.offers, 5);
  });

  test(
    'rejection uses retained progress and blocking is a user decision',
    () async {
      await seed('history', now, 'applied', outcome: 'rejected');
      await db
          .into(db.applicationEvents)
          .insert(
            ApplicationEventsCompanion.insert(
              id: 'offer-event',
              applicationId: 'history',
              previousStatus: const Value('offer'),
              newStatus: 'applied',
              actor: 'user',
              origin: 'test',
              occurredAt: now,
            ),
          );
      await seed('blocked', now, 'not_applied', review: 'hidden_low_score');
      await db
          .into(db.employers)
          .insert(
            EmployersCompanion.insert(
              id: 'employer',
              displayName: 'Blocked employer',
              normalizedName: 'blocked employer',
              blockedAt: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(db.jobs)..where((j) => j.id.equals('blocked'))).write(
        const JobsCompanion(employerId: Value('employer')),
      );
      final stats = await jobs.watchStatistics().first;
      expect(stats.branches, {
        JobFlowBranch.offerWithdrawn: 1,
        JobFlowBranch.userRejected: 1,
      });
    },
  );

  test(
    'statistics Inbox uses the actionable queue including failed AI work',
    () async {
      final ready = await jobs.queueManualUrl(
        Uri.parse('https://example.test/ready'),
      );
      final pending = await jobs.queueManualUrl(
        Uri.parse('https://example.test/pending'),
      );
      final failed = await jobs.queueManualUrl(
        Uri.parse('https://example.test/failed'),
      );
      final filtered = await jobs.queueManualUrl(
        Uri.parse('https://example.test/filtered'),
      );
      await jobs.setReviewState(
        ready,
        ReviewState.inbox,
        actor: 'user',
        origin: 'test',
      );
      await jobs.setReviewState(
        pending,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      await (db.update(db.jobs)..where((j) => j.id.equals(filtered))).write(
        const JobsCompanion(reviewState: Value('hidden_by_search')),
      );
      await db
          .into(db.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'failed-order',
              kind: 'search_analysis',
              status: 'failed',
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
              id: 'failed-item',
              workOrderId: 'failed-order',
              subjectId: failed,
              status: 'failed',
              idempotencyKey: 'failed',
              updatedAt: now,
            ),
          );
      final queue = await jobs.watchInbox().first;
      final stats = await jobs.watchStatistics().first;
      expect(queue.map((j) => j.id), unorderedEquals([ready, failed]));
      expect(stats.branches[JobFlowBranch.inbox], queue.length);
      expect(stats.branches[JobFlowBranch.pendingProcessing], 1);
      expect(stats.branches[JobFlowBranch.filteredBySearch], 1);
      final inboxUpdates = <List<InboxJob>>[];
      final inboxSub = jobs.watchInbox().listen(inboxUpdates.add);
      addTearDown(inboxSub.cancel);
      final updates = <JobStatistics>[];
      final sub = jobs.watchStatistics().listen(updates.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await (db.update(db.aiWorkOrders)
            ..where((o) => o.id.equals('failed-order')))
          .write(const AiWorkOrdersCompanion(status: Value('running')));
      await (db.update(db.aiWorkItems)
            ..where((i) => i.id.equals('failed-item')))
          .write(const AiWorkItemsCompanion(status: Value('running')));
      await pumpEventQueue();
      expect(
        updates.last.branches[JobFlowBranch.inbox],
        (await jobs.watchInbox().first).length,
      );
      expect(inboxUpdates.last.length, 1);
      expect(updates.last.branches[JobFlowBranch.inbox], 1);
      expect(updates.last.branches[JobFlowBranch.pendingProcessing], 2);
      expect(
        updates.last.sankeyNodes
            .singleWhere((n) => n.id == 'pending_processing')
            .terminal,
        false,
      );
    },
  );

  test(
    'source inputs count first discovery once and follow the date cohort',
    () async {
      Future<int> observe(String id, String job, String source, DateTime at) =>
          db
              .into(db.jobObservations)
              .insert(
                JobObservationsCompanion.insert(
                  id: id,
                  jobId: Value(job),
                  sourceFamily: source,
                  adapterId: 'test',
                  sourceUrl: 'https://example.test/$id',
                  payloadHash: id,
                  observedAt: at,
                ),
              );
      await seed('manual', now, 'applied');
      await seed('indeed', now, 'interviewing');
      await seed('old', DateTime(2029), 'offer');
      await seed('unknown', now, 'not_applied');
      await observe('z-first', 'manual', 'manual', now);
      await observe('a-same-time', 'manual', 'indeed', now);
      await observe(
        'later',
        'manual',
        'ashby',
        now.add(const Duration(hours: 1)),
      );
      await observe('indeed-first', 'indeed', 'Indeed', now);
      await observe('indeed-repeat', 'indeed', 'indeed', now);
      await observe('old-first', 'old', 'manual', DateTime(2029));
      final all = await jobs.watchStatistics().first;
      expect(all.sources, {'manual': 2, 'indeed': 1, 'unknown': 1});
      expect(all.sankeyNodes.first.label, 'Manual entry');
      final today = await jobs
          .watchStatistics(changedSince: StatisticsPeriod.today.start(now))
          .first;
      expect(today.sources, {'manual': 1, 'indeed': 1, 'unknown': 1});
      expect(
        today.sankeyLinks
            .where((l) => l.target == 'found')
            .fold<int>(0, (sum, l) => sum + l.count),
        today.found,
      );
      final values = <JobStatistics>[];
      final subscription = jobs.watchStatistics().listen(values.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      await observe('new-source', 'unknown', 'lever', now);
      await pumpEventQueue();
      expect(values.last.sources, {'manual': 2, 'indeed': 1, 'lever': 1});
      expect(values.last.found, all.found);
    },
  );

  test(
    'known application date counts but undated unknown outcome does not',
    () async {
      await seed('known', now, 'unknown', appliedAt: DateTime(2030, 8, 14));
      await seed('unknown', now, 'unknown', outcome: 'withdrawn');
      expect((await jobs.watchStatistics().first).toJson(), {
        'found': 2,
        'applied': 1,
        'interviewed': 0,
        'offers': 0,
      });
    },
  );

  test(
    'empty aggregates are zero and local writes update the stream',
    () async {
      final values = <JobStatistics>[];
      final subscription = jobs.watchStatistics().listen(values.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(values.last.toJson().values, everyElement(0));
      await seed('new', now, 'applied');
      await pumpEventQueue();
      expect(values.last.found, 1);
      expect(values.last.applied, 1);
      await db
          .into(db.applicationEvents)
          .insert(
            ApplicationEventsCompanion.insert(
              id: 'offer',
              applicationId: 'new',
              newStatus: 'offer',
              actor: 'user',
              origin: 'test',
              occurredAt: now,
            ),
          );
      await pumpEventQueue();
      expect(values.last.offers, 1);
    },
  );

  test(
    'last state change excludes content refreshes and no-op writes',
    () async {
      final old = DateTime(2020);
      final since = DateTime.now().subtract(const Duration(days: 1));
      await seed('old-applied', old, 'applied');
      expect((await jobs.watchStatistics(changedSince: since).first).found, 0);
      await (db.update(
        db.jobs,
      )..where((j) => j.id.equals('old-applied'))).write(
        JobsCompanion(
          updatedAt: Value(DateTime.now()),
          lastSeenAt: Value(DateTime.now()),
        ),
      );
      await jobs.saveJobNotes('old-applied', 'A note', expectedNotes: '');
      await jobs.setApplicationStatus(
        'old-applied',
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'test',
      );
      await jobs.setReviewState(
        'old-applied',
        ReviewState.pendingEvaluation,
        actor: 'user',
        origin: 'test',
      );
      expect((await jobs.watchStatistics(changedSince: since).first).found, 0);

      await jobs.setApplicationOutcome(
        'old-applied',
        ApplicationOutcome.rejected,
        actor: 'user',
        origin: 'test',
      );
      final changed = await jobs.watchStatistics(changedSince: since).first;
      expect(changed.found, 1);
      expect(changed.applied, 1);
      expect(changed.branches[JobFlowBranch.appliedRejected], 1);

      await seed('old-review', old, 'not_applied');
      await jobs.setReviewState(
        'old-review',
        ReviewState.discarded,
        actor: 'user',
        origin: 'test',
      );
      expect((await jobs.watchStatistics(changedSince: since).first).found, 2);
      await seed('old-availability', old, 'not_applied');
      await (db.update(db.jobs)..where((j) => j.id.equals('old-availability')))
          .write(const JobsCompanion(availability: Value('open')));
      expect((await jobs.watchStatistics(changedSince: since).first).found, 3);
      await seed('old-stage', old, 'applied');
      await jobs.setApplicationStatus(
        'old-stage',
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      expect(
        (await jobs.watchStatistics(changedSince: since).first).interviewed,
        1,
      );

      await seed('old-block', old, 'not_applied');
      await db
          .into(db.employers)
          .insert(
            EmployersCompanion.insert(
              id: 'blocked-state',
              displayName: 'Example employer',
              normalizedName: 'example employer',
              createdAt: old,
              updatedAt: old,
            ),
          );
      await (db.update(db.jobs)..where((j) => j.id.equals('old-block'))).write(
        const JobsCompanion(employerId: Value('blocked-state')),
      );
      await jobs.setEmployerBlocked(
        'blocked-state',
        blocked: true,
        actor: 'user',
        origin: 'test',
        reason: 'User choice',
      );
      expect(
        (await jobs.watchBlockedEmployers().first).single.blockReason,
        'User choice',
      );
      expect((await jobs.watchStatistics(changedSince: since).first).found, 5);
      await jobs.setEmployerBlocked(
        'blocked-state',
        blocked: false,
        actor: 'user',
        origin: 'test',
      );
      expect(await jobs.watchBlockedEmployers().first, isEmpty);
      expect((await jobs.watchStatistics(changedSince: since).first).found, 5);
    },
  );

  test(
    'v16 migration restores historical state dates without refresh dates',
    () async {
      final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning,
      );

      final directory = await Directory.systemTemp.createTemp(
        'careershopper-state-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');
      var legacy = CareerShopperDatabase(NativeDatabase(file));
      final old = DateTime(2020);
      final changed = DateTime(2021);
      await legacy
          .into(legacy.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'legacy',
              firstSeenAt: old,
              lastSeenAt: DateTime.now(),
              createdAt: old,
              updatedAt: DateTime.now(),
            ),
          );
      await legacy
          .into(legacy.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: 'review',
              eventType: 'job.review_state_changed',
              subjectType: 'job',
              subjectId: 'legacy',
              actor: 'user',
              occurredAt: changed,
            ),
          );
      for (final name in [
        'job_state_changed',
        'application_state_created',
        'application_state_changed',
        'employer_block_state_changed',
      ]) {
        await legacy.customStatement('DROP TRIGGER $name');
      }
      await legacy.customStatement(
        'ALTER TABLE jobs DROP COLUMN state_changed_at',
      );
      await legacy.customStatement('PRAGMA user_version = 15');
      await legacy.close();
      legacy = CareerShopperDatabase(NativeDatabase(file));
      try {
        final restored = await legacy.select(legacy.jobs).getSingle();
        expect(restored.stateChangedAt, changed);
        final migratedJobs = JobRepository(legacy);
        expect(
          (await migratedJobs
                  .watchStatistics(changedSince: DateTime(2022))
                  .first)
              .found,
          0,
        );
        await migratedJobs.setReviewState(
          'legacy',
          ReviewState.discarded,
          actor: 'user',
          origin: 'test',
        );
        expect(
          (await migratedJobs
                  .watchStatistics(changedSince: DateTime(2022))
                  .first)
              .found,
          1,
        );
      } finally {
        await legacy.close();
      }
    },
  );

  test('period starts use local calendar boundaries across year rollover', () {
    final january = DateTime(2031, 1, 1, 0, 30);
    for (final period in StatisticsPeriod.values.where(
      (p) => p != StatisticsPeriod.allTime,
    )) {
      expect(period.start(january), DateTime(2031));
      expect(period.start(january)!.isUtc, isFalse);
    }
    expect(StatisticsPeriod.allTime.start(january), isNull);
  });
}
