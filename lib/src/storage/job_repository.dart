import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/job.dart';
import '../domain/job_statistics.dart';
import '../ingestion/normalization.dart';
import 'database.dart';
import 'listing_availability_service.dart';

// Shared by the actionable Inbox and statistics so their eligibility cannot drift.
const _aiErrorSql =
    r'''(SELECT CASE WHEN o.status IN ('failed', 'interrupted') AND i.status != 'completed'
        THEN COALESCE(i.error, 'AI work failed. Retry to continue.') END
      FROM ai_work_items i JOIN ai_work_orders o ON o.id = i.work_order_id
      WHERE i.subject_id = jobs.id AND (
        (o.kind = 'application_materials' AND jobs.review_state = 'approved') OR
        (o.kind IN ('manual_job_import', 'search_analysis')
          AND jobs.current_evaluation_id IS NULL
          AND jobs.review_state IN ('pending_evaluation', 'inbox', 'hidden_low_score')))
      ORDER BY o.created_at DESC, o.id DESC LIMIT 1)''';
const _notAppliedSql =
    "(applications.status IS NULL OR applications.status IN ('not_applied', 'ready_to_apply'))";
const _activeApplicationSql =
    "(applications.outcome IS NULL OR applications.outcome = 'active')";
const _readyToApplySql =
    '''(
  jobs.review_state = 'approved' AND $_activeApplicationSql AND $_notAppliedSql
  AND EXISTS (SELECT 1 FROM material_sets m WHERE m.application_id = applications.id AND m.staged = 0)
  AND NOT EXISTS (SELECT 1 FROM ai_work_items i JOIN ai_work_orders o ON o.id = i.work_order_id
    WHERE i.subject_id = jobs.id AND o.kind = 'application_materials' AND o.status = 'running')
)''';
const _inboxEligibilitySql =
    '''(
  employers.blocked_at IS NULL AND $_activeApplicationSql AND (
    (jobs.review_state = 'inbox' AND $_notAppliedSql AND NOT EXISTS (
      SELECT 1 FROM ai_work_items i JOIN ai_work_orders o ON o.id = i.work_order_id
      WHERE i.subject_id = jobs.id AND i.status = 'running' AND o.status = 'running'
        AND o.kind IN ('manual_job_import', 'search_analysis')))
    OR $_readyToApplySql
    OR ($_aiErrorSql IS NOT NULL AND jobs.availability != 'closed')
  )
)''';

List<({InboxJob job, int score})> searchJobsByText(
  List<InboxJob> jobs,
  String query,
) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toSet();
  final matches = <({InboxJob job, int score, int index})>[];
  for (final (index, job) in jobs.indexed) {
    final fields = [
      job.title.toLowerCase(),
      job.description.toLowerCase(),
      job.employerName.toLowerCase(),
    ];
    final score = words.fold<int>(
      0,
      (total, word) =>
          total + fields.where((field) => field.contains(word)).length,
    );
    if (words.isEmpty || score > 0) {
      matches.add((job: job, score: score, index: index));
    }
  }
  if (words.isNotEmpty) {
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.index.compareTo(b.index);
    });
  }
  return [for (final match in matches) (job: match.job, score: match.score)];
}

class IngestResult {
  const IngestResult({
    required this.jobId,
    required this.created,
    required this.blockedEmployer,
  });

  final String jobId;
  final bool created;
  final bool blockedEmployer;
}

abstract interface class JobStore {
  Future<ListingAvailabilityResult> checkAvailability(String jobId);
  Future<void> clearAvailabilityBlock(String jobId);
  Stream<String> watchJobNotes(String jobId);
  Future<void> saveJobNotes(
    String jobId,
    String notes, {
    required String expectedNotes,
  });
  Stream<JobStatistics> watchStatistics({DateTime? changedSince});

  Stream<List<EmployerRow>> watchBlockedEmployers();

  Stream<List<InboxJob>> watchInbox();

  Stream<List<InboxJob>> watchAllJobs();

  Future<String> queueManualUrl(Uri url);

  Future<void> setApplicationStatus(
    String jobId,
    ApplicationStatus status, {
    required String actor,
    required String origin,
  });

  Future<void> setApplicationOutcome(
    String jobId,
    ApplicationOutcome outcome, {
    required String actor,
    required String origin,
  });

  Future<void> setReviewState(
    String jobId,
    ReviewState state, {
    required String actor,
    required String origin,
  });

  Future<void> setEmployerBlocked(
    String employerId, {
    required bool blocked,
    required String actor,
    required String origin,
    String? reason,
  });
}

class JobRepository implements JobStore {
  JobRepository(this.database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final CareerShopperDatabase database;

  @override
  Future<ListingAvailabilityResult> checkAvailability(String jobId) =>
      ListingAvailabilityService(database).check(jobId);
  @override
  Future<void> clearAvailabilityBlock(String jobId) =>
      ListingAvailabilityService(database).clearBlock(jobId);

  @override
  Stream<String> watchJobNotes(String jobId) =>
      (database.select(database.jobs)..where((row) => row.id.equals(jobId)))
          .watchSingle()
          .map((row) => row.notes);

  @override
  Future<void> saveJobNotes(
    String jobId,
    String notes, {
    required String expectedNotes,
  }) async {
    if (notes.length > 200000) {
      throw ArgumentError('Notes must be at most 200,000 characters.');
    }
    await database.transaction(() async {
      final job = await (database.select(
        database.jobs,
      )..where((row) => row.id.equals(jobId))).getSingleOrNull();
      if (job == null) throw ArgumentError('Job no longer exists.');
      if (job.notes != expectedNotes) {
        throw StateError('Notes changed elsewhere. Reload them before saving.');
      }
      await (database.update(database.jobs)
            ..where((row) => row.id.equals(jobId)))
          .write(JobsCompanion(notes: Value(notes)));
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: 'job_notes_saved',
              subjectType: 'job',
              subjectId: jobId,
              actor: 'user',
              occurredAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  final Uuid _uuid;

  @override
  Stream<List<EmployerRow>> watchBlockedEmployers() =>
      (database.select(database.employers)
            ..where((row) => row.blockedAt.isNotNull())
            ..orderBy([(row) => OrderingTerm.asc(row.displayName)]))
          .watch();

  @override
  Stream<JobStatistics> watchStatistics({DateTime? changedSince}) {
    // Filter by the last state change, including hidden/closed jobs. Stage
    // history preserves progress when the current status or outcome changes.
    return database
        .customSelect(
          '''
      WITH inbox AS (
        SELECT jobs.id FROM jobs
        JOIN job_snapshots ON job_snapshots.id = jobs.current_snapshot_id
        LEFT JOIN employers ON employers.id = jobs.employer_id
        LEFT JOIN applications ON applications.job_id = jobs.id
        WHERE $_inboxEligibilitySql
      ), stages AS (
        SELECT job_id, status FROM applications
        UNION ALL
        SELECT a.job_id, e.new_status FROM application_events e
          JOIN applications a ON a.id = e.application_id
        UNION ALL
        SELECT a.job_id, e.previous_status FROM application_events e
          JOIN applications a ON a.id = e.application_id
        UNION ALL
        SELECT job_id, 'applied' FROM applications WHERE applied_at IS NOT NULL
      ), progress AS (
        SELECT job_id, MAX(CASE status
          WHEN 'applied' THEN 1 WHEN 'interviewing' THEN 2
          WHEN 'offer' THEN 3 WHEN 'hired' THEN 4 ELSE 0 END) AS stage
        FROM stages GROUP BY job_id
      )
      SELECT COALESCE((SELECT NULLIF(LOWER(TRIM(o.source_family)), '')
        FROM job_observations o WHERE o.job_id = j.id
        ORDER BY o.observed_at, o.rowid LIMIT 1), 'unknown') AS source,
        COALESCE(p.stage, 0) AS stage,
        CASE
          WHEN COALESCE(p.stage, 0) = 0 THEN CASE
            WHEN a.outcome = 'expired' THEN 'expired'
            WHEN j.review_state = 'discarded' OR e.blocked_at IS NOT NULL
              OR a.outcome = 'withdrawn' THEN 'user_rejected'
            WHEN j.id IN (SELECT id FROM inbox) THEN 'inbox'
            WHEN a.outcome = 'rejected' THEN 'pre_application_rejected'
            WHEN j.review_state = 'hidden_low_score' THEN 'ai_rejected'
            WHEN j.review_state = 'hidden_by_search' THEN 'filtered_by_search'
            ELSE 'pending_processing' END
          WHEN p.stage = 1 THEN CASE a.outcome
            WHEN 'expired' THEN 'applied_expired'
            WHEN 'rejected' THEN 'applied_rejected'
            WHEN 'withdrawn' THEN 'applied_withdrawn'
            ELSE 'applied_waiting' END
          WHEN p.stage = 2 THEN CASE a.outcome
            WHEN 'expired' THEN 'interview_expired'
            WHEN 'rejected' THEN 'interview_rejected'
            WHEN 'withdrawn' THEN 'interview_withdrawn'
            ELSE 'interview_waiting' END
          ELSE CASE a.outcome
            WHEN 'expired' THEN 'offer_expired'
            WHEN 'rejected' THEN 'offer_withdrawn'
            WHEN 'withdrawn' THEN 'offer_rejected'
            ELSE CASE WHEN p.stage >= 4 THEN 'hired' ELSE 'offer_waiting' END END
        END AS ending,
        COUNT(*) AS count
      FROM jobs j LEFT JOIN progress p ON p.job_id = j.id
      LEFT JOIN applications a ON a.job_id = j.id
      LEFT JOIN employers e ON e.id = j.employer_id
      ${changedSince == null ? '' : 'WHERE COALESCE(j.state_changed_at, j.first_seen_at) >= ?'}
      GROUP BY source, stage, ending
      ''',
          variables: [
            if (changedSince != null) Variable<DateTime>(changedSince),
          ],
          readsFrom: {
            database.jobs,
            database.applications,
            database.applicationEvents,
            database.jobObservations,
            database.employers,
            database.jobSnapshots,
            database.materialSets,
            database.aiWorkItems,
            database.aiWorkOrders,
          },
        )
        .watch()
        .map((rows) {
          final sources = <String, int>{};
          final branches = <JobFlowBranch, int>{};
          var found = 0;
          var applied = 0;
          var interviewed = 0;
          var offers = 0;
          for (final row in rows) {
            final count = row.read<int>('count');
            final stage = row.read<int>('stage');
            final source = row.read<String>('source');
            final ending = JobFlowBranch.values.singleWhere(
              (e) => e.id == row.read<String>('ending'),
            );
            sources.update(source, (n) => n + count, ifAbsent: () => count);
            branches.update(ending, (n) => n + count, ifAbsent: () => count);
            found += count;
            if (stage >= 1) applied += count;
            if (stage >= 2) interviewed += count;
            if (stage >= 3) offers += count;
          }
          final sortedSources = sources.entries.toList()
            ..sort((a, b) {
              final byCount = b.value.compareTo(a.value);
              return byCount == 0 ? a.key.compareTo(b.key) : byCount;
            });
          return JobStatistics(
            found: found,
            applied: applied,
            interviewed: interviewed,
            offers: offers,
            sources: Map.fromEntries(sortedSources),
            branches: branches,
          );
        });
  }

  @override
  Future<void> setApplicationStatus(
    String jobId,
    ApplicationStatus status, {
    required String actor,
    required String origin,
    String? note,
  }) async {
    await database.transaction(() async {
      final job = await (database.select(
        database.jobs,
      )..where((row) => row.id.equals(jobId))).getSingleOrNull();
      if (job == null) throw ArgumentError('Unknown job: $jobId');
      final existing = await (database.select(
        database.applications,
      )..where((row) => row.jobId.equals(jobId))).getSingleOrNull();
      final previous =
          existing?.status ?? ApplicationStatus.notApplied.persistedName;
      if (previous == status.persistedName) return;
      final now = DateTime.now().toUtc();
      final id = existing?.id ?? _uuid.v7();
      if (existing == null) {
        await database
            .into(database.applications)
            .insert(
              ApplicationsCompanion.insert(
                id: id,
                jobId: jobId,
                status: Value(status.persistedName),
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.applications,
        )..where((row) => row.id.equals(id))).write(
          ApplicationsCompanion(
            status: Value(status.persistedName),
            updatedAt: Value(now),
          ),
        );
      }
      // Recording a past application does not establish its submission date.
      // Keep any known appliedAt value; do not invent one from today's date.
      await database
          .into(database.applicationEvents)
          .insert(
            ApplicationEventsCompanion.insert(
              id: _uuid.v7(),
              applicationId: id,
              previousStatus: Value(previous),
              newStatus: status.persistedName,
              actor: actor,
              origin: origin,
              note: Value(note),
              occurredAt: now,
            ),
          );
    });
  }

  @override
  Future<void> setApplicationOutcome(
    String jobId,
    ApplicationOutcome outcome, {
    required String actor,
    required String origin,
    String? note,
  }) async {
    await database.transaction(() async {
      final job = await (database.select(
        database.jobs,
      )..where((row) => row.id.equals(jobId))).getSingleOrNull();
      if (job == null) throw ArgumentError('Unknown job: $jobId');
      final existing = await (database.select(
        database.applications,
      )..where((row) => row.jobId.equals(jobId))).getSingleOrNull();
      final previous =
          existing?.outcome ?? ApplicationOutcome.active.persistedName;
      if (previous == outcome.persistedName) return;
      final now = DateTime.now().toUtc();
      final id = existing?.id ?? _uuid.v7();
      if (existing == null) {
        await database
            .into(database.applications)
            .insert(
              ApplicationsCompanion.insert(
                id: id,
                jobId: jobId,
                status: Value(ApplicationStatus.unknown.persistedName),
                outcome: Value(outcome.persistedName),
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.applications,
        )..where((row) => row.id.equals(id))).write(
          ApplicationsCompanion(
            outcome: Value(outcome.persistedName),
            updatedAt: Value(now),
          ),
        );
      }
      await _audit(
        eventType: 'application.outcome_changed',
        subjectType: 'application',
        subjectId: id,
        actor: actor,
        payload: {
          'previous_outcome': previous,
          'outcome': outcome.persistedName,
          'origin': origin,
          'note': ?note,
        },
      );
    });
  }

  @override
  Stream<List<InboxJob>> watchInbox() => _watchJobs(inboxOnly: true);

  @override
  Stream<List<InboxJob>> watchAllJobs() => _watchJobs(inboxOnly: false);

  Stream<List<InboxJob>> _watchJobs({required bool inboxOnly}) {
    final readyToApply = CustomExpression<bool>(
      _readyToApplySql,
      watchedTables: [
        database.materialSets,
        database.aiWorkOrders,
        database.aiWorkItems,
      ],
    );
    final aiError = CustomExpression<String>(
      _aiErrorSql,
      watchedTables: [database.aiWorkOrders, database.aiWorkItems],
    );
    final query = database.select(database.jobs).join([
      innerJoin(
        database.jobSnapshots,
        database.jobSnapshots.id.equalsExp(database.jobs.currentSnapshotId),
      ),
      leftOuterJoin(
        database.employers,
        database.employers.id.equalsExp(database.jobs.employerId),
      ),
      leftOuterJoin(
        database.jobEvaluations,
        database.jobEvaluations.id.equalsExp(database.jobs.currentEvaluationId),
      ),
      leftOuterJoin(
        database.applications,
        database.applications.jobId.equalsExp(database.jobs.id),
      ),
    ]);

    query.addColumns([readyToApply, aiError]);
    if (inboxOnly) {
      query.where(const CustomExpression<bool>(_inboxEligibilitySql));
    }
    query.orderBy([
      if (inboxOnly) OrderingTerm.desc(aiError.isNotNull()),
      if (inboxOnly) OrderingTerm.desc(database.jobEvaluations.overallScore),
      OrderingTerm.desc(database.jobs.lastSeenAt),
      OrderingTerm.asc(database.jobs.id),
    ]);

    return query.watch().map(
      (rows) => rows
          .map((row) {
            final job = row.readTable(database.jobs);
            final snapshot = row.readTable(database.jobSnapshots);
            final employer = row.readTableOrNull(database.employers);
            final evaluation = row.readTableOrNull(database.jobEvaluations);
            final application = row.readTableOrNull(database.applications);
            return InboxJob(
              id: job.id,
              employerId: employer?.id,
              employerLogoPng: employer?.logoPng,
              employerLogoSourceUrl: employer?.logoSourceUrl,
              title: snapshot.title,
              employerName: employer?.displayName ?? 'Employer not identified',
              location: snapshot.location,
              description: snapshot.description,
              applicationUrl: snapshot.applicationUrl == null
                  ? null
                  : Uri.tryParse(snapshot.applicationUrl!),
              availability: jobAvailabilityFromStorage(job.availability),
              reviewState: reviewStateFromStorage(job.reviewState),
              applicationStatus: applicationStatusFromStorage(
                application?.status ??
                    ApplicationStatus.notApplied.persistedName,
              ),
              observedAt: job.lastSeenAt,
              overallScore: evaluation?.overallScore,
              personalFitScore: evaluation?.personalFitScore,
              attainabilityScore: evaluation?.attainabilityScore,
              evaluationSummary: evaluation?.summary,
              readyToApply: row.read(readyToApply) ?? false,
              aiError: row.read(aiError),
              applicationOutcome: applicationOutcomeFromStorage(
                application?.outcome ?? 'active',
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Future<InboxJob?> getJob(String id) async {
    final jobs = await watchAllJobs().first;
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  Future<List<String>> searchAnalysisCandidates(
    Iterable<String> jobIds, {
    String? ignoringWorkOrderId,
  }) async {
    final ids = jobIds.toSet().toList();
    if (ids.isEmpty) return const [];
    final rows = await database
        .customSelect(
          '''
SELECT j.id FROM jobs j
LEFT JOIN employers e ON e.id = j.employer_id
WHERE j.id IN (${List.filled(ids.length, '?').join(',')})
AND j.current_evaluation_id IS NULL
AND j.review_state IN ('pending_evaluation', 'inbox', 'hidden_low_score', 'hidden_by_search')
AND j.availability != 'closed' AND e.blocked_at IS NULL
AND NOT EXISTS (SELECT 1 FROM applications a WHERE a.job_id = j.id
  AND (a.status NOT IN ('not_applied', 'ready_to_apply') OR a.outcome != 'active'))
AND NOT EXISTS (SELECT 1 FROM ai_work_items i
  JOIN ai_work_orders o ON o.id = i.work_order_id
  WHERE i.subject_id = j.id AND i.status IN ('queued', 'running')
  AND o.status IN ('queued', 'running')
  ${ignoringWorkOrderId == null ? '' : 'AND o.id != ?'}
  AND (o.leased_until IS NULL OR o.leased_until > ?))
ORDER BY j.first_seen_at, j.id
''',
          variables: [
            ...ids.map(Variable<String>.new),
            if (ignoringWorkOrderId != null)
              Variable<String>(ignoringWorkOrderId),
            Variable<DateTime>(DateTime.now().toUtc()),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('id')).toList();
  }

  Future<IngestResult> ingest(
    NormalizedListing listing, {
    String? savedSearchId,
    ReviewState initialReviewState = ReviewState.pendingEvaluation,
    String searchDisposition = 'match',
    List<String> searchReasons = const [],
  }) async {
    return database.transaction(() async {
      final now = DateTime.now().toUtc();
      final employer = await _resolveEmployer(listing, now);
      final identityKeys = _identityKeys(listing);
      final existingJobId = await _findJobByIdentityKeys(identityKeys);

      if (existingJobId != null) {
        final previous =
            await (database.select(database.jobObservations)
                  ..where(
                    (row) =>
                        row.jobId.equals(existingJobId) &
                        row.adapterId.equals(listing.adapterId) &
                        row.sourceUrl.equals(listing.sourceUrl.toString()),
                  )
                  ..orderBy([
                    (row) => OrderingTerm.desc(row.observedAt),
                    (row) => OrderingTerm.desc(row.id),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        // An unchanged search snippet must not replace the full posting fetched by AI.
        final unchangedSource =
            listing.rawPayloadJson != null &&
            previous?.payloadHash == contentHash(listing.rawPayloadJson!);
        await _recordObservation(existingJobId, listing);
        if (unchangedSource) {
          await (database.update(
            database.jobs,
          )..where((row) => row.id.equals(existingJobId))).write(
            JobsCompanion(
              lastSeenAt: Value(listing.observedAt),
              updatedAt: Value(now),
            ),
          );
        } else {
          await _refreshExistingJob(existingJobId, listing, employer?.id, now);
        }
        await _recordIdentityKeys(existingJobId, identityKeys, now);
        final existing = await (database.select(
          database.jobs,
        )..where((row) => row.id.equals(existingJobId))).getSingle();
        if (existing.reviewState == ReviewState.hiddenBySearch.persistedName &&
            initialReviewState == ReviewState.pendingEvaluation) {
          await (database.update(
            database.jobs,
          )..where((row) => row.id.equals(existingJobId))).write(
            JobsCompanion(
              reviewState: Value(initialReviewState.persistedName),
              updatedAt: Value(now),
            ),
          );
        }
        if (savedSearchId != null) {
          await _recordSearchMatch(
            existingJobId,
            savedSearchId,
            now,
            disposition: searchDisposition,
            reasons: searchReasons,
          );
        }
        return IngestResult(
          jobId: existingJobId,
          created: false,
          blockedEmployer: employer?.blockedAt != null,
        );
      }

      final jobId = _uuid.v7();
      final snapshotId = _uuid.v7();
      await database
          .into(database.jobs)
          .insert(
            JobsCompanion.insert(
              id: jobId,
              employerId: Value(employer?.id),
              currentSnapshotId: Value(snapshotId),
              reviewState: Value(initialReviewState.persistedName),
              firstSeenAt: listing.observedAt,
              lastSeenAt: listing.observedAt,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.jobSnapshots)
          .insert(
            JobSnapshotsCompanion.insert(
              id: snapshotId,
              jobId: jobId,
              revision: 1,
              title: listing.title,
              location: Value(listing.location),
              remoteStatus: Value(listing.remoteStatus),
              description: Value(listing.description),
              descriptionHash: listing.contentHash,
              applicationUrl: Value(listing.applicationUrl?.toString()),
              compensationJson: Value(_compensationJson(listing)),
              capturedAt: listing.observedAt,
            ),
          );
      await _recordObservation(jobId, listing);
      for (final key in identityKeys.entries) {
        await database
            .into(database.jobIdentityKeys)
            .insert(
              JobIdentityKeysCompanion.insert(
                id: _uuid.v7(),
                jobId: jobId,
                keyType: key.key,
                keyValue: key.value,
                createdAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      if (savedSearchId != null) {
        await _recordSearchMatch(
          jobId,
          savedSearchId,
          now,
          disposition: searchDisposition,
          reasons: searchReasons,
        );
      }
      await _audit(
        eventType: 'job.discovered',
        subjectType: 'job',
        subjectId: jobId,
        actor: 'system',
        payload: {
          'source_family': listing.sourceFamily,
          'blocked_employer': employer?.blockedAt != null,
        },
      );
      return IngestResult(
        jobId: jobId,
        created: true,
        blockedEmployer: employer?.blockedAt != null,
      );
    });
  }

  /// Refreshes the exact placeholder selected by a manual-import work order.
  ///
  /// A job page may link to a different application URL after it is opened.
  /// Normal discovery dedupe must not create a second logical job before the
  /// scoped import can validate that redirect.
  Future<IngestResult> ingestIntoExistingJob(
    String jobId,
    NormalizedListing listing,
  ) => database.transaction(() async {
    final target = await (database.select(
      database.jobs,
    )..where((row) => row.id.equals(jobId))).getSingleOrNull();
    if (target == null) throw ArgumentError('Job no longer exists: $jobId');

    final now = DateTime.now().toUtc();
    final identityKeys = _identityKeys(listing);
    final identityOwner = await _findJobByIdentityKeys(identityKeys);
    if (identityOwner != null && identityOwner != jobId) {
      throw StateError(
        'The imported listing already belongs to job $identityOwner. '
        'CareerShopper did not create or merge another record.',
      );
    }

    final employer = await _resolveEmployer(listing, now);
    await _recordObservation(jobId, listing);
    await _refreshExistingJob(jobId, listing, employer?.id, now);
    await _recordIdentityKeys(jobId, identityKeys, now);
    await _audit(
      eventType: 'job.manual_import_refreshed',
      subjectType: 'job',
      subjectId: jobId,
      actor: 'system',
      payload: {'source_family': listing.sourceFamily},
    );
    return IngestResult(
      jobId: jobId,
      created: false,
      blockedEmployer: employer?.blockedAt != null,
    );
  });

  @override
  Future<String> queueManualUrl(Uri url) async {
    final canonical = canonicalizeJobUrl(url);
    final listing = NormalizedListing(
      sourceFamily: 'manual',
      adapterId: 'manual_url_v1',
      providerJobId: null,
      title: 'Pending import from ${canonical.host}',
      employerName: 'Employer not identified',
      normalizedEmployerName: 'employer not identified',
      location: '',
      description: '',
      contentHash: contentHash('manual:${canonical.toString()}'),
      sourceUrl: canonical,
      applicationUrl: canonical,
      observedAt: DateTime.now().toUtc(),
      rawPayloadJson: jsonEncode({'url': canonical.toString()}),
    );
    return (await ingest(listing)).jobId;
  }

  @override
  Future<void> setReviewState(
    String jobId,
    ReviewState state, {
    required String actor,
    required String origin,
  }) async {
    await database.transaction(() async {
      final now = DateTime.now().toUtc();
      await (database.update(
        database.jobs,
      )..where((row) => row.id.equals(jobId))).write(
        JobsCompanion(
          reviewState: Value(state.persistedName),
          updatedAt: Value(now),
        ),
      );
      if (state == ReviewState.approved) {
        await database
            .into(database.applications)
            .insert(
              ApplicationsCompanion.insert(
                id: _uuid.v7(),
                jobId: jobId,
                approvedAt: Value(now),
                updatedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await (database.update(database.applications)..where(
              (row) => row.jobId.equals(jobId) & row.approvedAt.isNull(),
            ))
            .write(
              ApplicationsCompanion(
                approvedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
      await _audit(
        eventType: 'job.review_state_changed',
        subjectType: 'job',
        subjectId: jobId,
        actor: actor,
        payload: {'state': state.persistedName, 'origin': origin},
      );
    });
  }

  @override
  Future<void> setEmployerBlocked(
    String employerId, {
    required bool blocked,
    required String actor,
    required String origin,
    String? reason,
  }) async {
    await database.transaction(() async {
      final now = DateTime.now().toUtc();
      await (database.update(
        database.employers,
      )..where((row) => row.id.equals(employerId))).write(
        EmployersCompanion(
          blockedAt: Value(blocked ? now : null),
          blockReason: Value(blocked ? reason : null),
          updatedAt: Value(now),
        ),
      );
      final payload = <String, Object?>{'origin': origin};
      if (reason != null) payload['reason'] = reason;
      await _audit(
        eventType: blocked ? 'employer.blocked' : 'employer.unblocked',
        subjectType: 'employer',
        subjectId: employerId,
        actor: actor,
        payload: payload,
      );
    });
  }

  Future<EmployerRow?> _resolveEmployer(
    NormalizedListing listing,
    DateTime now,
  ) async {
    if (listing.normalizedEmployerName == 'employer not identified') {
      return null;
    }
    final existing =
        await (database.select(database.employers)
              ..where(
                (row) =>
                    row.normalizedName.equals(listing.normalizedEmployerName),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing;

    final id = _uuid.v7();
    await database
        .into(database.employers)
        .insert(
          EmployersCompanion.insert(
            id: id,
            displayName: listing.employerName,
            normalizedName: listing.normalizedEmployerName,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.employerAliases)
        .insert(
          EmployerAliasesCompanion.insert(
            id: _uuid.v7(),
            employerId: id,
            displayName: listing.employerName,
            normalizedName: listing.normalizedEmployerName,
            sourceFamily: Value(listing.sourceFamily),
            createdAt: now,
          ),
        );
    return (database.select(
      database.employers,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Map<String, String> _identityKeys(NormalizedListing listing) {
    return {
      if (listing.providerJobId != null)
        'provider_job_id':
            '${listing.sourceFamily}:${listing.tenantId ?? ''}:${listing.providerJobId}',
      if (listing.tenantId != null && listing.requisitionId != null)
        'ats_requisition': '${listing.tenantId}:${listing.requisitionId}',
      if (listing.applicationUrl != null)
        'application_url': listing.applicationUrl.toString(),
      'content_fingerprint': [
        listing.normalizedEmployerName,
        listing.title.trim().toLowerCase(),
        listing.location.trim().toLowerCase(),
        listing.contentHash,
      ].join('|'),
    };
  }

  Future<String?> _findJobByIdentityKeys(Map<String, String> keys) async {
    for (final key in keys.entries) {
      final match =
          await (database.select(database.jobIdentityKeys)
                ..where(
                  (row) =>
                      row.keyType.equals(key.key) &
                      row.keyValue.equals(key.value),
                )
                ..limit(1))
              .getSingleOrNull();
      if (match != null) return match.jobId;
    }
    return null;
  }

  Future<void> _recordIdentityKeys(
    String jobId,
    Map<String, String> keys,
    DateTime now,
  ) async {
    for (final key in keys.entries) {
      await database
          .into(database.jobIdentityKeys)
          .insert(
            JobIdentityKeysCompanion.insert(
              id: _uuid.v7(),
              jobId: jobId,
              keyType: key.key,
              keyValue: key.value,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<void> _refreshExistingJob(
    String jobId,
    NormalizedListing listing,
    String? employerId,
    DateTime now,
  ) async {
    final job = await (database.select(
      database.jobs,
    )..where((row) => row.id.equals(jobId))).getSingle();
    final snapshot = await (database.select(
      database.jobSnapshots,
    )..where((row) => row.id.equals(job.currentSnapshotId!))).getSingle();
    var currentSnapshotId = snapshot.id;
    if (snapshot.descriptionHash != listing.contentHash ||
        snapshot.title != listing.title ||
        snapshot.location != listing.location) {
      currentSnapshotId = _uuid.v7();
      await database
          .into(database.jobSnapshots)
          .insert(
            JobSnapshotsCompanion.insert(
              id: currentSnapshotId,
              jobId: jobId,
              revision: snapshot.revision + 1,
              title: listing.title,
              location: Value(listing.location),
              remoteStatus: Value(listing.remoteStatus),
              description: Value(listing.description),
              descriptionHash: listing.contentHash,
              applicationUrl: Value(listing.applicationUrl?.toString()),
              compensationJson: Value(_compensationJson(listing)),
              capturedAt: listing.observedAt,
            ),
          );
    }
    await (database.update(
      database.jobs,
    )..where((row) => row.id.equals(jobId))).write(
      JobsCompanion(
        employerId: Value(employerId ?? job.employerId),
        currentSnapshotId: Value(currentSnapshotId),
        currentEvaluationId: Value(
          currentSnapshotId == snapshot.id ? job.currentEvaluationId : null,
        ),
        lastSeenAt: Value(listing.observedAt),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _recordObservation(
    String jobId,
    NormalizedListing listing,
  ) async {
    final rawPayload = listing.rawPayloadJson ?? '{}';
    await database
        .into(database.jobObservations)
        .insert(
          JobObservationsCompanion.insert(
            id: _uuid.v7(),
            jobId: Value(jobId),
            sourceFamily: listing.sourceFamily,
            adapterId: listing.adapterId,
            providerJobId: Value(listing.providerJobId),
            tenantId: Value(listing.tenantId),
            requisitionId: Value(listing.requisitionId),
            sourceUrl: listing.sourceUrl.toString(),
            canonicalApplicationUrl: Value(listing.applicationUrl?.toString()),
            rawPayloadJson: Value(listing.rawPayloadJson),
            payloadHash: contentHash(rawPayload),
            observedAt: listing.observedAt,
          ),
        );
  }

  String? _compensationJson(NormalizedListing listing) {
    if (listing.compensationMinimum == null &&
        listing.compensationMaximum == null &&
        listing.compensationCurrency == null) {
      return null;
    }
    return jsonEncode({
      'minimum': listing.compensationMinimum,
      'maximum': listing.compensationMaximum,
      'currency': listing.compensationCurrency,
    });
  }

  Future<void> _recordSearchMatch(
    String jobId,
    String savedSearchId,
    DateTime now, {
    required String disposition,
    required List<String> reasons,
  }) async {
    await database
        .into(database.jobSearchMatches)
        .insert(
          JobSearchMatchesCompanion.insert(
            jobId: jobId,
            savedSearchId: savedSearchId,
            firstMatchedAt: now,
            lastMatchedAt: now,
            disposition: Value(disposition),
            reasonsJson: Value(jsonEncode(reasons)),
          ),
          onConflict: DoUpdate(
            (_) => JobSearchMatchesCompanion(
              lastMatchedAt: Value(now),
              disposition: Value(disposition),
              reasonsJson: Value(jsonEncode(reasons)),
            ),
          ),
        );
  }

  Future<void> _audit({
    required String eventType,
    required String subjectType,
    required String subjectId,
    required String actor,
    required Map<String, Object?> payload,
  }) async {
    await database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            id: _uuid.v7(),
            eventType: eventType,
            subjectType: subjectType,
            subjectId: subjectId,
            actor: actor,
            payloadJson: Value(jsonEncode(payload)),
            occurredAt: DateTime.now().toUtc(),
          ),
        );
  }
}
