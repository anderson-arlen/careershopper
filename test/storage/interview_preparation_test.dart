import 'dart:async';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/interview_data.dart';

class _Runner implements AcpAgentRunner {
  final Future<void> Function(AcpRunRequest) action;
  _Runner(this.action);
  final calls = <AcpRunRequest>[];
  @override
  Future<void> run(AcpRunRequest request) async {
    calls.add(request);
    await request.onSessionStarted?.call('saved-interview-session');
    await action(request);
  }
}

Future<void> _eventually(Future<bool> Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for interview work.');
}

void main() {
  late CareerShopperDatabase db;
  late String job, agent;
  late AiHarnessRepository harness;
  late _Runner runner;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    job = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/job'));
    runner = _Runner((request) async {
      final repo = InterviewRepository(db);
      final current = await repo.get(job);
      await repo.submitPreparation(
        job,
        current['revision']! as int,
        interviewIntel(),
        interviewBank(),
        workOrderId: request.workOrderId,
      );
    });
    harness = AiHarnessRepository(db, runner: runner);
    agent = await harness.saveProfile(
      const AiHarnessProfileDraft(
        name: 'Test agent',
        executable: '/bin/true',
        arguments: [],
        isDefault: true,
      ),
    );
  });
  tearDown(() async {
    harness.stopInterviewPreparationMonitor();
    await db.close();
  });
  Future<bool> finished() =>
      (db.select(
        db.aiWorkOrders,
      )..where((r) => r.kind.equals('interview_preparation'))).get().then(
        (rows) =>
            rows.isNotEmpty &&
            rows.every((r) => !['queued', 'running'].contains(r.status)),
      );
  test(
    'saved packet remains busy until its ACP turn finishes, including duplicate dispatch',
    () async {
      final submitted = Completer<void>(), finish = Completer<void>();
      runner = _Runner((request) async {
        await InterviewRepository(db).submitPreparation(
          job,
          0,
          interviewIntel(),
          interviewBank(),
          workOrderId: request.workOrderId,
        );
        submitted.complete();
        await finish.future;
      });
      harness = AiHarnessRepository(db, runner: runner);
      final first = await harness.queueInterviewPreparation(job);
      await submitted.future;
      final duplicate = await harness.queueInterviewPreparation(job);
      expect(duplicate.workOrderId, first.workOrderId);
      expect(
        (await InterviewRepository(db).get(job))['preparation_state'],
        'running',
      );
      expect(
        (await db.select(db.interviewWorkspaces).getSingle()).preparationState,
        'ready',
      );
      expect((await InterviewRepository(db).get(job))['intel'], isNotNull);
      finish.complete();
      await _eventually(finished);
      expect(
        (await InterviewRepository(db).get(job))['preparation_state'],
        'ready',
      );
    },
  );
  test(
    'follow-up research stays in the same conversation and carries the user request',
    () async {
      final first = await harness.queueInterviewPreparation(job);
      await _eventually(finished);
      await harness.sendMessage(
        first.workOrderId,
        'Focus on the technical panel.',
      );
      await _eventually(
        () async => runner.calls.length == 2 && await finished(),
      );
      expect((await db.select(db.aiWorkOrders).get()), hasLength(1));
      expect(runner.calls.last.existingSessionId, 'saved-interview-session');
      expect(
        runner.calls.last.prompt,
        contains('Focus on the technical panel.'),
      );
    },
  );

  test(
    'Interviewing automatically researches with the default agent',
    () async {
      await JobRepository(db).setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      await harness.startInterviewPreparationMonitor();
      await _eventually(finished);
      expect(runner.calls, hasLength(1));
      expect((await db.select(db.aiWorkOrders).getSingle()).agentId, agent);
      expect(
        (await InterviewRepository(db).get(job))['preparation_state'],
        'ready',
      );
      expect(
        (await db.select(db.aiWorkOrders).getSingle()).title,
        startsWith('Prepare interviews:'),
      );
      await harness.startInterviewPreparationMonitor();
      expect(runner.calls, hasLength(1));
    },
  );
  test(
    'explicit off switch persists until automatic preparation is enabled',
    () async {
      await InterviewRepository(
        db,
      ).configureAutomaticPreparation(enabled: false);
      await JobRepository(db).setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      await harness.startInterviewPreparationMonitor();
      await harness.startInterviewPreparationMonitor();
      expect(runner.calls, isEmpty);
      expect((await InterviewRepository(db).settings())['auto_prepare'], false);
      await InterviewRepository(
        db,
      ).configureAutomaticPreparation(enabled: true);
      await harness.startInterviewPreparationMonitor();
      await _eventually(finished);
      expect(runner.calls, hasLength(1));
    },
  );
  test('missing agent stays pending and starts after setup', () async {
    await db.delete(db.aiHarnessProfiles).go();
    await JobRepository(db).setApplicationStatus(
      job,
      ApplicationStatus.interviewing,
      actor: 'user',
      origin: 'test',
    );
    await harness.startInterviewPreparationMonitor();
    expect(runner.calls, isEmpty);
    expect(await db.select(db.aiWorkOrders).get(), isEmpty);
    final pending = await InterviewRepository(db).get(job);
    expect(pending['preparation_state'], 'needed');
    expect(
      pending['preparation_error'],
      contains('Configure a default AI harness'),
    );
    await harness.saveProfile(
      const AiHarnessProfileDraft(
        name: 'Configured later',
        executable: '/bin/true',
        arguments: [],
        isDefault: true,
      ),
    );
    await harness.startInterviewPreparationMonitor();
    await _eventually(finished);
    expect(runner.calls, hasLength(1));
    expect(
      (await InterviewRepository(db).get(job))['preparation_error'],
      isNull,
    );
  });
  test('duplicate dispatch shares one work order and one runner', () async {
    final entered = Completer<void>(), finish = Completer<void>();
    runner = _Runner((request) async {
      entered.complete();
      await finish.future;
      final repo = InterviewRepository(db);
      await repo.submitPreparation(
        job,
        0,
        interviewIntel(),
        interviewBank(),
        workOrderId: request.workOrderId,
      );
    });
    harness = AiHarnessRepository(db, runner: runner);
    final first = await harness.queueInterviewPreparation(job);
    await entered.future;
    final second = await harness.queueInterviewPreparation(job);
    expect(first.workOrderId, second.workOrderId);
    expect(runner.calls, hasLength(1));
    finish.complete();
    await _eventually(finished);
  });
  test(
    'startup resumes authorized unfinished work in its saved ACP session',
    () async {
      final now = DateTime.now().toUtc();
      await InterviewRepository(db).ensure(job);
      await db
          .into(db.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'resume',
              jobId: Value(job),
              agentId: Value(agent),
              kind: 'interview_preparation',
              status: 'running',
              scopeJson: '{}',
              acpSessionId: const Value('prior-session'),
              promptVersion: 'interview-preparation-v1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.aiWorkItems)
          .insert(
            AiWorkItemsCompanion.insert(
              id: 'resume-item',
              workOrderId: 'resume',
              subjectId: job,
              status: 'running',
              idempotencyKey: 'resume-item',
              updatedAt: now,
            ),
          );
      await harness.startInterviewPreparationMonitor();
      await _eventually(finished);
      expect(runner.calls.single.existingSessionId, 'prior-session');
      expect((await db.select(db.aiWorkOrders).get()).length, 1);
    },
  );
  test(
    'failed refresh preserves packet and requires an explicit retry',
    () async {
      await InterviewRepository(
        db,
      ).submitPreparation(job, 0, interviewIntel(), interviewBank());
      final first = (await InterviewRepository(db).get(job))['intel'];
      runner = _Runner((_) async {});
      harness = AiHarnessRepository(db, runner: runner);
      await harness.queueInterviewPreparation(job);
      await _eventually(finished);
      final current = await InterviewRepository(db).get(job);
      expect(current['intel'], first);
      expect(current['preparation_state'], 'failed');
      await harness.startInterviewPreparationMonitor();
      expect(runner.calls, hasLength(1));
    },
  );
  test('explicit Stop stays paused on monitor restart', () async {
    final entered = Completer<void>();
    runner = _Runner((r) async {
      entered.complete();
      await r.control!.whenCancelled;
      r.control!.checkCancelled();
    });
    harness = AiHarnessRepository(db, runner: runner);
    final result = await harness.queueInterviewPreparation(job);
    await entered.future;
    await harness.interruptConversation(result.workOrderId);
    await _eventually(
      () async =>
          (await InterviewRepository(db).get(job))['preparation_state'] ==
          'paused',
    );
    await harness.startInterviewPreparationMonitor();
    expect(runner.calls, hasLength(1));
  });
}
