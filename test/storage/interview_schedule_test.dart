import 'dart:convert';

import 'package:careershopper/src/domain/interview.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/interview_mcp.dart';

void main() {
  late CareerShopperDatabase db;
  late InterviewRepository interviews;
  late JobRepository jobs;
  late String job;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    interviews = InterviewRepository(db);
    jobs = JobRepository(db);
    job = await jobs.queueManualUrl(
      Uri.parse('https://example.test/interview'),
    );
  });
  tearDown(() => db.close());

  Map<String, Object?> scheduled(String id, DateTime time) => {
    ...newInterviewStage(id, id),
    'status': 'scheduled',
    'scheduled_at': time.toIso8601String(),
    'duration_minutes': 30,
  };

  test(
    'completion waits until the end, survives reopening, and preserves manual states',
    () async {
      final start = DateTime.now().toUtc().add(const Duration(days: 2));
      final stages = [
        scheduled('first', start),
        scheduled('second', start.add(const Duration(hours: 2))),
        for (final status in ['planned', 'completed', 'skipped', 'cancelled'])
          {...scheduled(status, start), 'status': status},
        {...scheduled('archived', start), 'archived': true},
      ];
      await interviews.saveStages(job, 0, stages);
      expect(
        await interviews.completeScheduledStages(
          now: start.add(const Duration(minutes: 29)),
        ),
        0,
      );
      final reopened = InterviewRepository(db);
      expect(
        await reopened.completeScheduledStages(
          now: start.add(const Duration(minutes: 30)),
        ),
        1,
      );
      final workspace = await reopened.get(job);
      expect(workspace['revision'], 2);
      expect(interviewMap(workspace['current_stage'])['id'], 'second');
      final saved = interviewMaps(workspace['ladder']);
      expect(saved.map((s) => s['status']), [
        'completed',
        'scheduled',
        'planned',
        'completed',
        'skipped',
        'cancelled',
        'scheduled',
      ]);
      expect(
        await reopened.completeScheduledStages(
          now: start.add(const Duration(minutes: 30)),
        ),
        0,
      );
      expect(
        (await jobs.getJob(job))!.applicationStatus,
        ApplicationStatus.notApplied,
      );
      expect(
        (await db.select(db.auditEvents).get()).where(
          (r) => r.eventType == 'interview.scheduled_stages_completed',
        ),
        hasLength(1),
      );
      await expectLater(reopened.saveStages(job, 1, stages), throwsStateError);
    },
  );

  test(
    'elapsed appointments reconcile before MCP reads and default practice',
    () async {
      await interviews.ensure(job);
      final now = DateTime.now().toUtc();
      await (db.update(
        db.interviewWorkspaces,
      )..where((w) => w.jobId.equals(job))).write(
        InterviewWorkspacesCompanion(
          ladderJson: Value(
            jsonEncode([
              scheduled('elapsed', now.subtract(const Duration(hours: 2))),
              newInterviewStage('next', 'Next stage'),
            ]),
          ),
        ),
      );
      final practice = await interviews
          .startPractice(job, null, 'schedule-practice', {
            'personality': 'neutral',
            'personality_instructions': '',
            'minutes': 30,
            'coaching': false,
            'harness': 'Test',
            'model': 'test',
          });
      expect(
        interviewMap(interviewMap(practice['snapshot'])['stage'])['id'],
        'next',
      );
      final read = mcpContent(
        await interviewMcp(db, 'interview_get', {'job_id': job}),
      );
      expect(interviewMaps(read['ladder']).first['status'], 'completed');
      expect(read['revision'], 1);
    },
  );

  test(
    'MCP schedules and reschedules with offset normalization and chronological pagination',
    () async {
      final second = await jobs.queueManualUrl(
        Uri.parse('https://example.test/second'),
      );
      final unscheduled = await jobs.queueManualUrl(
        Uri.parse('https://example.test/unscheduled'),
      );
      for (final id in [job, second, unscheduled]) {
        await jobs.setApplicationStatus(
          id,
          ApplicationStatus.interviewing,
          actor: 'user',
          origin: 'test',
        );
      }
      final save = mcpContent(
        await interviewMcp(db, 'interview_stages_save', {
          'job_id': job,
          'expected_revision': 0,
          'confirmed': true,
          'stages': [
            newInterviewStage('planned', 'Unscheduled earlier step'),
            {
              ...newInterviewStage('call', 'Technical interview'),
              'status': 'scheduled',
              'scheduled_at': '2099-04-01T09:00:00-04:00',
            },
          ],
        }),
      );
      expect(interviewMap(save['current_stage'])['id'], 'call');
      expect(
        interviewMap(save['next_scheduled_stage'])['scheduled_at'],
        '2099-04-01T13:00:00.000Z',
      );
      await interviews.saveStages(second, 0, [
        scheduled('earlier', DateTime.utc(2099, 4, 1, 12)),
      ]);
      final firstPage = mcpContent(
        await interviewMcp(db, 'jobs_search', {
          'view': 'interviewing',
          'limit': 1,
        }),
      );
      expect(interviewMaps(firstPage['jobs']).single['id'], second);
      final secondPage = mcpContent(
        await interviewMcp(db, 'jobs_search', {
          'view': 'interviewing',
          'offset': 1,
          'limit': 1,
        }),
      );
      expect(interviewMaps(secondPage['jobs']).single['id'], job);
      expect(
        interviewMap(
          interviewMaps(secondPage['jobs']).single['next_interview'],
        )['name'],
        'Technical interview',
      );
      final moved = interviewMaps(save['ladder']);
      moved.last['scheduled_at'] = '2099-04-01T11:00:00Z';
      await interviews.saveStages(job, 1, moved);
      expect(
        (await jobs.watchJobs(view: 'interviewing').first).map((j) => j.id),
        [job, second, unscheduled],
      );
      moved.last['status'] = 'cancelled';
      await interviews.saveStages(job, 2, moved);
      expect(
        (await jobs.watchJobs(view: 'interviewing').first).first.id,
        second,
      );
      expect((await jobs.getJob(job))!.nextInterviewStage, isNull);
    },
  );
}
