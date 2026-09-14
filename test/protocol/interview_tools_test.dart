import 'package:careershopper/src/domain/interview.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/interview_data.dart';
import '../fixtures/interview_mcp.dart';

void main() {
  late CareerShopperDatabase db;
  late String job, other;
  late InterviewRepository repo;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    repo = InterviewRepository(db);
    job = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/one'));
    other = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/two'));
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> scope({
    String kind = 'interview_preparation',
    String status = 'running',
    bool expired = false,
  }) async {
    final now = DateTime.now().toUtc();
    await db
        .into(db.aiWorkOrders)
        .insert(
          AiWorkOrdersCompanion.insert(
            id: 'work',
            jobId: Value(job),
            kind: kind,
            status: status,
            scopeJson: '{}',
            promptVersion: 'test',
            leasedUntil: Value(now.add(Duration(minutes: expired ? -1 : 30))),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.aiWorkItems)
        .insert(
          AiWorkItemsCompanion.insert(
            id: 'item',
            workOrderId: 'work',
            subjectId: job,
            status: 'running',
            idempotencyKey: 'item',
            updatedAt: now,
          ),
        );
  }

  Map<String, Object?> packet(String id) => {
    'job_id': id,
    'expected_revision': 0,
    'intel': interviewIntel(),
    'question_bank': interviewBank(),
  };
  test(
    'MCP practice defaults to the current stage and progressive difficulty',
    () async {
      await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
      final settings = practiceSettings()..remove('difficulty');
      final response = mcpContent(
        await interviewMcp(db, 'interview_practice_start', {
          'job_id': job,
          'client_request_id': 'automatic',
          'settings': settings,
          'confirmed': true,
        }),
      );
      expect(response['stage_id'], 'technical');
      final snapshot = interviewMap(response['snapshot']);
      expect(interviewMap(snapshot['settings'])['difficulty'], 2);
      expect(
        interviewMap(snapshot['difficulty_progression'])['mode'],
        'automatic',
      );
      final retry = mcpContent(
        await interviewMcp(db, 'interview_practice_start', {
          'job_id': job,
          'client_request_id': 'automatic',
          'settings': settings,
          'confirmed': true,
        }),
      );
      expect(retry['practice_id'], response['practice_id']);
      final read = mcpContent(
        await interviewMcp(db, 'interview_get', {'job_id': job}),
      );
      expect(interviewMap(read['current_stage'])['id'], 'technical');
    },
  );

  test('MCP allows omitted stage proposals with an existing ladder', () async {
    await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
    final intel = interviewIntel()..remove('stage_proposals');
    final result = await interviewMcp(db, 'interview_preparation_submit', {
      'job_id': job,
      'expected_revision': 1,
      'confirmed': true,
      'intel': intel,
      'question_bank': interviewBank(),
      'employer_logo_url': 'https://example.test/logo.png',
    });
    final saved = mcpContent(result);
    expect(saved['revision'], 2);
    // An unlinked employer cannot receive a logo; the research still succeeds.
    expect(saved['logo_warning'], contains('No employer is linked'));
    final read = mcpContent(
      await interviewMcp(db, 'interview_get', {'job_id': job}),
    );
    expect(interviewMaps(read['ladder']).single['id'], 'technical');
    expect(interviewMap(read['company'])['has_logo'], false);
    expect(
      interviewMap(interviewMap(read['intel'])['payload'])['stage_proposals'],
      isEmpty,
    );
    final invalid = await interviewMcp(db, 'interview_preparation_submit', {
      'job_id': other,
      'expected_revision': 0,
      'confirmed': true,
      'intel': intel,
      'question_bank': interviewBank(),
    });
    expect(invalid, contains('error'));
    expect((await repo.get(other))['revision'], 0);
  });

  test('MCP exposes bank targets and validates dependency changes', () async {
    await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
    final read = mcpContent(
      await interviewMcp(db, 'interview_get', {'job_id': job}),
    );
    final targets = interviewMaps(
      interviewMap(read['questions'])['stage_targets'],
    );
    expect(targets.single['available'], 1);
    expect(targets.single['target'], greaterThanOrEqualTo(40));
    final bad = await interviewMcp(db, 'interview_question_save', {
      'job_id': job,
      'expected_revision': 1,
      'confirmed': true,
      'question': {
        ...interviewQuestion(),
        'depends_on': ['missing'],
      },
    });
    expect(bad, contains('error'));
    final good = await interviewMcp(db, 'interview_question_save', {
      'job_id': job,
      'expected_revision': 1,
      'confirmed': true,
      'question': {
        ...interviewQuestion(),
        'id': 'next',
        'prompt': 'Extend the design.',
        'depends_on': ['tradeoffs'],
      },
    });
    expect(good, isNot(contains('error')));
    final practice = mcpContent(
      await interviewMcp(db, 'interview_practice_start', {
        'job_id': job,
        'stage_id': 'technical',
        'client_request_id': 'randomized',
        'settings': practiceSettings(),
        'confirmed': true,
      }),
    );
    final questions = interviewMap(
      interviewMap(practice['snapshot'])['questions'],
    );
    expect(interviewMaps(questions['questions']).map((q) => q['id']), [
      'tradeoffs',
      'next',
    ]);
    expect(questions['selection_history'], hasLength(2));
  });

  test(
    'tool discovery includes interview data but no agent launch operations',
    () async {
      final response = await interviewMcp(db, '', {}, method: 'tools/list');
      final names = (((response['result'] as Map)['tools']) as List).map(
        (t) => (t as Map)['name'],
      );
      expect(
        names,
        containsAll([
          'interview_get',
          'interview_preparation_submit',
          'interview_practice_start',
          'interview_practice_exchange_save',
          'interview_statistics_get',
        ]),
      );
      expect(names, isNot(contains('interview_prepare_launch')));
      final writer = await interviewMcp(
        db,
        '',
        {},
        method: 'tools/list',
        answerWriter: true,
      );
      expect(
        (((writer['result'] as Map)['tools']) as List).any(
          (t) => (t as Map)['name'].toString().startsWith('interview_'),
        ),
        false,
      );
    },
  );
  test(
    'user writes need confirmation; nested invalid fields rejected',
    () async {
      expect(
        await interviewMcp(db, 'interview_preparation_submit', packet(job)),
        contains('error'),
      );
      expect(
        await interviewMcp(db, 'interview_preparation_submit', {
          ...packet(job),
          'confirmed': true,
        }),
        isNot(contains('error')),
      );
      expect(
        await interviewMcp(db, 'interview_stages_save', {
          'job_id': job,
          'expected_revision': 1,
          'confirmed': true,
          'stages': [
            {...interviewStage(), 'arbitrary': true},
          ],
        }),
        contains('error'),
      );
      expect((await repo.get(job))['revision'], 1);
    },
  );
  test('scoped packet submission completes only its own item', () async {
    await scope();
    expect(
      await interviewMcp(
        db,
        'interview_preparation_submit',
        packet(other),
        orderId: 'work',
      ),
      contains('error'),
    );
    expect(
      await interviewMcp(
        db,
        'interview_preparation_submit',
        packet(job),
        orderId: 'work',
      ),
      isNot(contains('error')),
    );
    expect((await db.select(db.aiWorkItems).getSingle()).status, 'completed');
    expect((await repo.get(other))['intel'], null);
  });
  test(
    'research scope cannot mutate profile, job outcomes, ladder, or start practice',
    () async {
      await scope();
      for (final name in [
        'profile_preferences_upsert',
        'application_status_set',
        'job_evaluation_submit',
        'interview_stages_save',
        'interview_practice_start',
        'application_answer_generate',
      ]) {
        expect(
          await interviewMcp(db, name, {
            'job_id': job,
            'confirmed': true,
          }, orderId: 'work'),
          contains('error'),
          reason: name,
        );
      }
      expect(
        await interviewMcp(db, 'job_get', {'job_id': other}, orderId: 'work'),
        contains('error'),
      );
      expect(
        await interviewMcp(
          db,
          '',
          {'uri': 'careershopper://jobs/$other'},
          method: 'resources/read',
          orderId: 'work',
        ),
        contains('error'),
      );
    },
  );
  for (final state in ['completed', 'expired', 'wrong_kind']) {
    test('$state work scope cannot save research', () async {
      await scope(
        status: state == 'completed' ? 'completed' : 'running',
        expired: state == 'expired',
        kind: state == 'wrong_kind'
            ? 'search_analysis'
            : 'interview_preparation',
      );
      expect(
        await interviewMcp(
          db,
          'interview_preparation_submit',
          packet(job),
          orderId: 'work',
        ),
        contains('error'),
      );
      expect(await db.select(db.interviewRevisions).get(), isEmpty);
    });
  }
  test(
    'practice MCP saves checkpoints without repeated confirmation and computes final score',
    () async {
      await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
      final started = mcpContent(
        await interviewMcp(db, 'interview_practice_start', {
          'job_id': job,
          'stage_id': 'technical',
          'client_request_id': 'request',
          'settings': practiceSettings(),
          'confirmed': true,
        }),
      );
      final id = started['practice_id'];
      final saved = await interviewMcp(db, 'interview_practice_exchange_save', {
        'practice_id': id,
        'exchange_id': 'one',
        'expected_revision': -1,
        'exchange': practiceExchange(score: 4),
      });
      expect(saved, isNot(contains('error')));
      final finished = mcpContent(
        await interviewMcp(db, 'interview_practice_state_set', {
          'practice_id': id,
          'expected_revision': 1,
          'status': 'completed',
          'debrief': 'Strong example; practice concise delivery.',
        }),
      );
      expect(interviewMap(finished['assessment'])['score'], 100);
      final stats = mcpContent(
        await interviewMcp(db, 'interview_statistics_get', {'job_id': job}),
      );
      expect(stats['groups'], hasLength(1));
      expect(
        await interviewMcp(db, 'interview_practice_context_get', {
          'practice_id': id,
        }, answerWriter: true),
        contains('error'),
      );
    },
  );
}
