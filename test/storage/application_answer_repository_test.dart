import 'dart:io';

import 'package:careershopper/src/domain/interview.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:careershopper/src/storage/application_answer_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/interview_mcp.dart';
import '../fixtures/interview_data.dart';

void main() {
  late CareerShopperDatabase db;
  late ApplicationAnswerRepository answers;
  late String job;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    answers = ApplicationAnswerRepository(db);
    job = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/job'));
  });
  tearDown(() => db.close());

  Map<String, Object?> input({int revision = 0, String status = 'draft'}) => {
    'job_id': job,
    'answer_id': 'answer-1',
    'expected_revision': revision,
    'question': 'Why this role?',
    'answer': 'A focused answer.\n\nWith an exact second paragraph.  ',
    'status': status,
    'confirmed': true,
  };

  test(
    'MCP saves exact text, isolates jobs, and rejects stale edits',
    () async {
      final tools = McpUiTools(db);
      final saved = mcpContent(
        await interviewMcp(db, 'application_answer_save', input()),
      );
      expect(saved['answer'], input()['answer']);
      expect(saved['revision'], 1);
      final listed = await tools.call('application_answers_list', {
        'job_id': job,
      });
      expect((listed['answers'] as List).single, saved);
      final other = await JobRepository(
        db,
      ).queueManualUrl(Uri.parse('https://example.test/other'));
      expect(await answers.list(other), isEmpty);
      await expectLater(
        tools.call('application_answer_save', {
          ...input(revision: 1),
          'job_id': other,
        }),
        throwsStateError,
      );
      await expectLater(
        tools.call('application_answer_save', input()),
        throwsStateError,
      );
      await expectLater(
        tools.call('application_answer_save', {
          ...input(revision: 1),
          'confirmed': false,
        }),
        throwsFormatException,
      );
      await expectLater(
        tools.call('application_answer_save', {
          ...input(),
          'answer_id': 'missing',
          'job_id': 'missing',
        }),
        throwsStateError,
      );
      await expectLater(
        tools.call('application_answer_save', {
          ...input(revision: 1),
          'answer': '   ',
        }),
        throwsFormatException,
      );
      final updated = await tools.call('application_answer_save', {
        ...input(revision: 1, status: 'submitted'),
        'answer': 'My final wording.',
      });
      expect(updated['revision'], 2);
      expect(updated['created_at'], saved['created_at']);
      expect((await answers.list(job)).single.answer, 'My final wording.');
      expect(
        (await JobRepository(db).getJob(job))!.applicationStatus,
        ApplicationStatus.notApplied,
      );
      expect(await db.select(db.careerFacts).get(), isEmpty);
      expect(await db.select(db.aiWorkOrders).get(), isEmpty);
    },
  );

  test(
    'submitted answers enter interview context and practice snapshots, drafts do not',
    () async {
      final tools = McpUiTools(db);
      final interviews = InterviewRepository(db);
      await tools.call('application_answer_save', input());
      expect((await interviews.get(job))['application_context'], isNull);
      await tools.call(
        'application_answer_save',
        input(revision: 1, status: 'submitted'),
      );
      await interviews.saveStages(job, 0, [
        newInterviewStage('screen', 'Screen'),
      ]);
      final context = mcpContent(
        await interviewMcp(db, 'interview_get', {'job_id': job}),
      );
      final payload = interviewMap(
        interviewMap(context['application_context'])['payload'],
      );
      expect(
        interviewMaps(payload['application_answers']).single['answer'],
        input()['answer'],
      );
      final practice = await interviews.startPractice(
        job,
        null,
        'practice-1',
        practiceSettings(),
      );
      final original = interviewMap(
        interviewMap(practice['snapshot'])['application_context'],
      );
      await tools.call('application_answer_save', {
        ...input(revision: 2, status: 'submitted'),
        'answer': 'Corrected text.',
      });
      final reloaded = await interviews.practice(
        practice['practice_id']! as String,
      );
      expect(
        interviewMap(interviewMap(reloaded['snapshot'])['application_context']),
        original,
      );
      expect(
        interviewMaps(
          interviewMap(original['payload'])['application_answers'],
        ).single['answer'],
        input()['answer'],
      );
    },
  );

  test(
    'writer and scoped work orders cannot save or read unrelated answers',
    () async {
      final tools = McpUiTools(db);
      for (final name in [
        'application_answer_save',
        'application_answers_list',
      ]) {
        final args = name.endsWith('_save') ? input() : {'job_id': job};
        await expectLater(
          tools.call(name, args, workOrderId: 'scoped'),
          throwsStateError,
        );
        expect(
          await interviewMcp(db, name, args, answerWriter: true),
          contains('error'),
        );
      }
      expect(await answers.list(job), isEmpty);
    },
  );

  test(
    'v20 migration preserves jobs and adds indexed persistent answers',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'careershopper-answer-migration-',
      );
      final file = File('${dir.path}/data.sqlite');
      var local = CareerShopperDatabase(NativeDatabase(file));
      try {
        final retained = await JobRepository(
          local,
        ).queueManualUrl(Uri.parse('https://example.test/retained'));
        await local.customStatement('DROP TABLE application_answers');
        await local.customStatement('PRAGMA user_version = 20');
        await local.close();
        local = CareerShopperDatabase(NativeDatabase(file));
        expect((await JobRepository(local).getJob(retained))!.id, retained);
        final repo = ApplicationAnswerRepository(local);
        await repo.save(
          jobId: retained,
          answerId: 'saved',
          expectedRevision: 0,
          question: 'Why?',
          answer: 'Exact text.',
          status: 'submitted',
        );
        final plan = await local
            .customSelect(
              "EXPLAIN QUERY PLAN SELECT * FROM application_answers WHERE job_id = 'id' ORDER BY created_at DESC",
            )
            .get();
        expect(
          plan.map((r) => r.data['detail']).join(),
          contains('application_answer_job'),
        );
        await local.close();
        local = CareerShopperDatabase(NativeDatabase(file));
        expect(
          (await ApplicationAnswerRepository(
            local,
          ).list(retained)).single.answer,
          'Exact text.',
        );
      } finally {
        await local.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
