import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/interview_mcp.dart';

void main() {
  late CareerShopperDatabase db;
  late JobRepository jobs;
  late String job, revision;
  const description =
      'Build production services. A bachelor degree is required.';
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(db);
    job = await jobs.queueManualUrl(Uri.parse('https://example.test/engineer'));
    await interviewMcp(db, 'job_import_submit', {
      'job_id': job,
      'source_url': 'https://example.test/engineer',
      'title': 'Engineer',
      'employer_name': 'Example',
      'description': description,
    });
    await ProfileRepository(db).saveCareerFact(
      CareerFactDraft(
        kind: 'resume_content',
        visibility: 'resume',
        value: {
          ...ResumeContent.empty(),
          'header': {'name': 'Alex Example', 'contact': ''},
          'education': [
            {
              'id': 'education',
              'enabled': true,
              'heading': 'Education',
              'details': 'No college degree.',
            },
          ],
        },
      ),
      actor: 'user',
    );
    revision = (await ProfileRepository(
      db,
    ).watchCareerFacts().first).single.revisionId;
  });
  tearDown(() => db.close());

  Map<String, Object?> blocker() => {
    'requirement': 'Bachelor degree',
    'posting_evidence': 'A bachelor degree is required.',
    'applicant_evidence': 'Confirmed profile states no college degree.',
    'fact_revision_ids': [revision],
  };
  Map<String, Object?> evaluation(List<Object?> unmet) => {
    'job_id': job,
    'personal_fit_score': 91,
    'attainability_score': 84,
    'confidence': 0.95,
    'summary': 'Strong work alignment but required education is not met.',
    'strengths': ['Production services experience'],
    'concerns': [],
    'unknowns': [],
    'unmet_requirements': unmet,
  };

  test(
    'mandatory qualification excludes an 88 score even with a zero threshold',
    () async {
      final now = DateTime.now().toUtc();
      await db
          .into(db.savedSearches)
          .insert(
            SavedSearchesCompanion.insert(
              id: 'search',
              name: 'All scores',
              queryJson: '{}',
              scoreThreshold: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.jobSearchMatches)
          .insert(
            JobSearchMatchesCompanion.insert(
              jobId: job,
              savedSearchId: 'search',
              firstMatchedAt: now,
              lastMatchedAt: now,
            ),
          );
      final result = mcpContent(
        await interviewMcp(
          db,
          'job_evaluation_submit',
          evaluation([blocker()]),
        ),
      );
      expect(result['overall_score'], 88);
      expect(result['threshold'], 0);
      expect(result['review_state'], 'hidden_low_score');
      expect(await jobs.watchInbox().first, isEmpty);
      final retained = (await jobs.watchAllJobs().first).single;
      expect(retained.unmetRequirements, [blocker()]);
      expect(retained.applicationStatus, ApplicationStatus.notApplied);
      expect(retained.availability, JobAvailability.unknown);
      final read = mcpContent(
        await interviewMcp(db, 'job_get', {'job_id': job}),
      );
      expect((read['job'] as Map)['unmet_requirements'], [blocker()]);
    },
  );

  test(
    'absence of a confirmed blocker uses normal score placement and clears stale blockers',
    () async {
      await interviewMcp(db, 'job_evaluation_submit', evaluation([blocker()]));
      final result = mcpContent(
        await interviewMcp(db, 'job_evaluation_submit', evaluation([])),
      );
      expect(result['review_state'], 'inbox');
      expect((await jobs.watchInbox().first).single.unmetRequirements, isEmpty);
    },
  );

  test(
    'explicit approval and discard survive eligibility re-evaluation',
    () async {
      for (final state in [ReviewState.approved, ReviewState.discarded]) {
        await jobs.setReviewState(job, state, actor: 'user', origin: 'test');
        final before = (await jobs.getJob(job))!.applicationStatus;
        final result = mcpContent(
          await interviewMcp(
            db,
            'job_evaluation_submit',
            evaluation([blocker()]),
          ),
        );
        expect(result['review_state'], state.persistedName);
        expect((await jobs.getJob(job))!.applicationStatus, before);
      }
    },
  );

  test(
    'requires explicit check and supported current evidence before saving',
    () async {
      for (final invalid in [
        evaluation([])..remove('unmet_requirements'),
        evaluation([])..['unmet_requirements'] = 'none',
        evaluation([{}]),
        evaluation([
          {...blocker(), 'posting_evidence': 'A doctorate is required.'},
        ]),
        evaluation([
          {...blocker(), 'fact_revision_ids': []},
        ]),
        evaluation([
          {
            ...blocker(),
            'fact_revision_ids': ['old-or-invented'],
          },
        ]),
      ]) {
        final result = await interviewMcp(db, 'job_evaluation_submit', invalid);
        expect(result, contains('error'));
        expect(await db.select(db.jobEvaluations).get(), isEmpty);
      }
    },
  );
}
