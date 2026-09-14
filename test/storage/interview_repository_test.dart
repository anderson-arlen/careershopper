import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:careershopper/src/storage/employer_logo_repository.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:careershopper/src/domain/interview.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/interview_data.dart';

void main() {
  late CareerShopperDatabase db;
  late InterviewRepository repo;
  late JobRepository jobs;
  late String job;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = CareerShopperDatabase(NativeDatabase.memory());
    repo = InterviewRepository(db);
    jobs = JobRepository(db);
    job = await jobs.queueManualUrl(Uri.parse('https://example.test/job'));
  });
  tearDown(() async {
    await db.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  Future<void> prepare() async {
    await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
  }

  Future<Map<String, Object?>> start({
    String request = 'start',
    int difficulty = 3,
  }) async => repo.startPractice(
    job,
    'technical',
    request,
    practiceSettings(difficulty: difficulty),
  );

  test(
    'automatic difficulty progresses only on completed practices and pins retries',
    () async {
      await prepare();
      final automatic = practiceSettings()..remove('difficulty');
      for (final status in ['paused', 'abandoned']) {
        final p = await repo.startPractice(job, null, status, automatic);
        await repo.setPracticeState(p['practice_id']! as String, 0, status, '');
      }
      Map<String, Object?>? first;
      for (var i = 0; i < 8; i++) {
        final p = await repo.startPractice(
          job,
          null,
          'automatic-$i',
          automatic,
        );
        first ??= p;
        final snapshot = interviewMap(p['snapshot']);
        expect(
          interviewMap(snapshot['settings'])['difficulty'],
          [2, 2, 3, 3, 4, 4, 5, 5][i],
        );
        expect(
          interviewMap(
            snapshot['difficulty_progression'],
          )['completed_practices'],
          i,
        );
        expect(p['stage_id'], 'technical');
        final id = p['practice_id']! as String;
        await repo.saveExchange(id, 'line', -1, practiceExchange());
        await repo.setPracticeState(id, 1, 'completed', 'Debrief.');
      }
      final retry = await repo.startPractice(
        job,
        null,
        'automatic-0',
        automatic,
      );
      expect(retry['practice_id'], first!['practice_id']);
      expect(retry['snapshot'], first['snapshot']);
      final fixed = await repo.startPractice(
        job,
        null,
        'fixed',
        practiceSettings(difficulty: 1),
      );
      expect(
        interviewMap(interviewMap(fixed['snapshot'])['settings'])['difficulty'],
        1,
      );
      expect(
        interviewMap(
          interviewMap(fixed['snapshot'])['difficulty_progression'],
        )['mode'],
        'fixed',
      );
      expect(
        interviewMap((await repo.get(job))['current_stage'])['id'],
        'technical',
      );
      final other = await jobs.queueManualUrl(
        Uri.parse('https://example.test/other-practice'),
      );
      await repo.submitPreparation(other, 0, interviewIntel(), interviewBank());
      final fresh = await repo.startPractice(other, null, 'other', automatic);
      expect(
        interviewMap(interviewMap(fresh['snapshot'])['settings'])['difficulty'],
        2,
      );
    },
  );

  test(
    'current stage skips finished stages and retries retain the original stage',
    () async {
      await prepare();
      final automatic = practiceSettings()..remove('difficulty');
      final original = await repo.startPractice(
        job,
        null,
        'original-stage',
        automatic,
      );
      await repo.saveStages(job, 1, [
        {...interviewStage(), 'status': 'completed'},
        {...interviewStage(), 'id': 'cancelled', 'status': 'cancelled'},
        {...interviewStage(), 'id': 'archived', 'archived': true},
        {...interviewStage(), 'id': 'skipped', 'status': 'skipped'},
        {
          ...interviewStage(),
          'id': 'manager',
          'name': 'Manager',
          'status': 'scheduled',
        },
      ]);
      expect(
        interviewMap((await repo.get(job))['current_stage'])['id'],
        'manager',
      );
      expect(
        (await repo.startPractice(
          job,
          null,
          'original-stage',
          automatic,
        ))['snapshot'],
        original['snapshot'],
      );
      final current = await repo.startPractice(
        job,
        null,
        'manager-practice',
        automatic,
      );
      expect(current['stage_id'], 'manager');
      expect(
        interviewMap(
          interviewMap(current['snapshot'])['settings'],
        )['difficulty'],
        2,
      );
      await repo.saveStages(job, 2, [
        {...interviewStage(), 'status': 'completed'},
      ]);
      expect((await repo.get(job))['current_stage'], isNull);
      await expectLater(
        repo.startPractice(job, null, 'no-current', automatic),
        throwsStateError,
      );
      expect(
        (await repo.startPractice(
          job,
          'technical',
          'revisit',
          automatic,
        ))['stage_id'],
        'technical',
      );
    },
  );

  test(
    'research caches a logo after saving and retries do not refetch',
    () async {
      final now = DateTime.utc(2026);
      await db
          .into(db.employers)
          .insert(
            EmployersCompanion.insert(
              id: 'company',
              displayName: 'Example Company',
              normalizedName: 'example company',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(db.jobs)..where((r) => r.id.equals(job))).write(
        const JobsCompanion(employerId: Value('company')),
      );
      var fetches = 0;
      repo = InterviewRepository(
        db,
        logos: EmployerLogoRepository(
          db,
          fetch: (_) async {
            fetches++;
            return Uint8List.fromList(
              img.encodePng(img.Image(width: 32, height: 16)),
            );
          },
        ),
      );
      const url = 'https://example.test/logo.png';
      final saved = await repo.submitPreparation(
        job,
        0,
        interviewIntel(),
        interviewBank(),
        employerLogoUrl: url,
      );
      expect(saved, isNot(contains('logo_warning')));
      expect(fetches, 1);
      expect((await repo.company(job))!.logoPng, isNotNull);
      final company = interviewMap((await repo.get(job))['company']);
      expect(company, {
        'name': 'Example Company',
        'has_logo': true,
        'logo_source_url': url,
      });
      expect(
        await repo.submitPreparation(
          job,
          0,
          interviewIntel(),
          interviewBank(),
          employerLogoUrl: url,
        ),
        saved,
      );
      expect(fetches, 1);

      repo = InterviewRepository(
        db,
        logos: EmployerLogoRepository(
          db,
          fetch: (_) async {
            fetches++;
            throw const HttpException('HTTP 403; no retries');
          },
        ),
      );
      final partial = await repo.submitPreparation(
        job,
        1,
        interviewIntel(),
        interviewBank(),
        employerLogoUrl: 'https://example.test/blocked.png',
      );
      expect(partial['logo_warning'], contains('Research saved'));
      expect((await repo.get(job))['revision'], 2);
      expect((await repo.get(job))['preparation_state'], 'ready');
      expect((await repo.company(job))!.logoSourceUrl, url);
      await repo.submitPreparation(
        job,
        1,
        interviewIntel(),
        interviewBank(),
        employerLogoUrl: 'https://example.test/blocked.png',
      );
      expect(fetches, 2);
    },
  );

  test('rejected research never downloads a logo', () async {
    var fetched = false;
    repo = InterviewRepository(
      db,
      logos: EmployerLogoRepository(
        db,
        fetch: (_) async {
          fetched = true;
          return Uint8List(0);
        },
      ),
    );
    await expectLater(
      repo.submitPreparation(
        job,
        0,
        {},
        interviewBank(),
        employerLogoUrl: 'https://example.test/logo.png',
      ),
      throwsFormatException,
    );
    expect(fetched, isFalse);
    expect((await repo.get(job))['intel'], isNull);
  });

  test(
    'latest saved documents are automatic and practice snapshots remain stable',
    () async {
      await jobs.setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      final app = await db.select(db.applications).getSingle();
      final snapshot =
          (await db.select(db.jobs).getSingle()).currentSnapshotId!;
      await db
          .into(db.profileSnapshots)
          .insert(
            ProfileSnapshotsCompanion.insert(
              id: 'profile',
              manifestJson: '{}',
              manifestHash: 'profile',
              createdAt: DateTime.utc(2026),
            ),
          );
      Future<void> add(String id, int day, {bool staged = false}) => db
          .into(db.materialSets)
          .insert(
            MaterialSetsCompanion.insert(
              id: id,
              applicationId: app.id,
              jobSnapshotId: snapshot,
              profileSnapshotId: 'profile',
              resumeMarkdown: 'Resume $id',
              coverLetterMarkdown: Value('Letter $id'),
              rendererVersion: 'test',
              templateId: 'test',
              createdAt: DateTime.utc(2026, 1, day),
              staged: Value(staged),
            ),
          )
          .then((_) {});
      Map<String, Object?> payload(Map<String, Object?> value) =>
          interviewMap(interviewMap(value['application_context'])['payload']);
      await add('old', 1);
      await add('latest', 2);
      await add('unfinished', 3, staged: true);
      expect(payload(await repo.get(job))['resume_markdown'], 'Resume latest');
      expect(
        payload(await repo.get(job))['attribution'],
        'latest_application_documents',
      );
      await prepare();
      final practice = await start();
      expect(
        payload(interviewMap(practice['snapshot']))['cover_letter_markdown'],
        'Letter latest',
      );
      await add('newer', 4);
      expect(payload(await repo.get(job))['resume_markdown'], 'Resume newer');
      expect(
        payload(
          interviewMap(
            (await repo.practice(
              practice['practice_id']! as String,
            ))['snapshot'],
          ),
        )['resume_markdown'],
        'Resume latest',
      );
      final bankId =
          (await db.select(db.interviewWorkspaces).getSingle()).questionsId;
      final bank = interviewMap((await repo.revision(job, bankId))!['payload']);
      expect(payload(bank)['resume_markdown'], 'Resume latest');
      await repo.saveContext(
        job,
        1,
        materialSetId: 'old',
        attribution: 'selected_for_practice',
      );
      expect(payload(await repo.get(job))['resume_markdown'], 'Resume old');
    },
  );

  test(
    'practice rotation counts asked questions, preserves retries and survives bank refresh',
    () async {
      final extra = {
        ...interviewQuestion(),
        'id': 'other',
        'prompt': 'Explain a second topic.',
      };
      await repo.submitPreparation(job, 0, interviewIntel(), {
        ...interviewBank(),
        'questions': [interviewQuestion(), extra],
      });
      final first = await start();
      final id = first['practice_id']! as String;
      Map<String, Object?> bank(Map<String, Object?> p) =>
          interviewMap(interviewMap(p['snapshot'])['questions']);
      final retry = await start();
      expect(bank(retry), bank(first));
      await repo.saveExchange(
        id,
        'asked',
        -1,
        practiceExchange(complete: false),
      );
      await repo.saveExchange(
        id,
        'asked',
        -1,
        practiceExchange(complete: false),
      );
      final second = await start(request: 'second');
      expect(interviewMaps(bank(second)['questions']).first['id'], 'other');
      expect(
        interviewMaps(bank(second)['selection_history']).singleWhere(
          (q) => q['question_id'] == 'tradeoffs',
        )['prior_practice_count'],
        1,
      );
      // A planned but unasked session does not consume questions.
      final third = await start(request: 'third');
      expect(interviewMaps(bank(third)['questions']).first['id'], 'other');
      await repo.submitPreparation(job, 1, interviewIntel(), {
        ...interviewBank(),
        'questions': [
          {...interviewQuestion(), 'id': 'renamed'},
          extra,
        ],
      });
      final refreshed = bank(await start(request: 'refreshed'));
      expect(interviewMaps(refreshed['questions']).first['id'], 'other');
      expect(
        interviewMaps(refreshed['selection_history']).singleWhere(
          (q) => q['question_id'] == 'renamed',
        )['prior_practice_count'],
        1,
      );
      expect(bank(await repo.practice(id)), bank(first));
    },
  );

  test(
    'dependencies remain valid through question edits and refreshes',
    () async {
      final dependent = {
        ...interviewQuestion(),
        'id': 'dependent',
        'prompt': 'Extend the previous design.',
        'depends_on': ['tradeoffs'],
      };
      await repo.submitPreparation(job, 0, interviewIntel(), {
        ...interviewBank(),
        'questions': [interviewQuestion(), dependent],
      });
      await expectLater(
        repo.saveQuestion(job, 1, {...interviewQuestion(), 'archived': true}),
        throwsFormatException,
      );
      await expectLater(
        repo.saveQuestion(job, 1, {
          ...interviewQuestion(),
          'depends_on': ['dependent'],
        }),
        throwsFormatException,
      );
      await repo.saveQuestion(job, 1, dependent);
      await expectLater(
        repo.submitPreparation(job, 2, interviewIntel(), {
          ...interviewBank(),
          'questions': <Object?>[],
        }),
        throwsFormatException,
      );
      final ordered = interviewMaps(
        interviewMap(
          interviewMap((await start())['snapshot'])['questions'],
        )['questions'],
      );
      expect(ordered.map((q) => q['id']), ['tradeoffs', 'dependent']);
    },
  );

  test('identical packet retry does not create duplicate revisions', () async {
    final first = await repo.submitPreparation(
      job,
      0,
      interviewIntel(),
      interviewBank(),
    );
    final again = await repo.submitPreparation(
      job,
      0,
      interviewIntel(),
      interviewBank(),
    );
    expect(again, first);
    expect(await db.select(db.interviewRevisions).get(), hasLength(2));
  });
  test(
    'archived questions remain in history but are not offered in new practices',
    () async {
      await prepare();
      await repo.saveQuestion(job, 1, {
        ...interviewQuestion(),
        'archived': true,
      });
      final snapshot = interviewMap((await start())['snapshot']);
      expect(interviewMap(snapshot['questions'])['questions'], isEmpty);
      expect((await repo.questions(job))['questions'], hasLength(1));
      await expectLater(
        repo.saveQuestion(job, 2, {
          ...interviewQuestion(),
          'source_ids': ['foreign'],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'Interviewing initializes once; re-entry preserves edits and outcomes',
    () async {
      expect((await repo.get(job))['preparation_state'], 'not_started');
      await jobs.setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      expect((await repo.get(job))['preparation_state'], 'needed');
      expect((await repo.settings())['auto_prepare'], true);
      await repo.saveStages(job, 0, [interviewStage()]);
      await jobs.setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      await jobs.setApplicationStatus(
        job,
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'test',
      );
      await jobs.setApplicationStatus(
        job,
        ApplicationStatus.interviewing,
        actor: 'user',
        origin: 'test',
      );
      expect((await repo.get(job))['revision'], 1);
      expect(await db.select(db.interviewWorkspaces).get(), hasLength(1));
    },
  );
  test(
    'ladder edits survive regeneration; removed stages are archived',
    () async {
      await prepare();
      await repo.saveStages(job, 1, [
        {...interviewStage(), 'name': 'My actual round'},
      ]);
      await repo.submitPreparation(job, 2, interviewIntel(), interviewBank());
      expect(
        interviewMaps((await repo.get(job))['ladder']).single['name'],
        'My actual round',
      );
      await repo.saveStages(job, 3, []);
      expect(
        interviewMaps((await repo.get(job))['ladder']).single['archived'],
        true,
      );
      await expectLater(
        repo.saveStages(job, 3, [interviewStage()]),
        throwsStateError,
      );
    },
  );
  test('question overrides and old revisions survive refresh', () async {
    await prepare();
    final initial = await repo.get(job);
    await repo.saveQuestion(job, 1, {
      ...interviewQuestion(),
      'prompt': 'My custom question',
      'kind': 'user',
    });
    await repo.submitPreparation(job, 2, interviewIntel(), interviewBank());
    expect(
      interviewMaps((await repo.questions(job))['questions']).single['prompt'],
      'My custom question',
    );
    final old = await repo.revision(
      job,
      interviewMap(initial['intel'])['id']! as String,
    );
    expect(interviewMap(old!['payload'])['assertions'], hasLength(1));
    expect(await db.select(db.interviewRevisions).get(), hasLength(4));
  });
  test(
    'reject malformed citations, duplicate IDs, foreign stages, and unknown fields atomically',
    () async {
      final invalid = [
        {
          ...interviewIntel(),
          'assertions': [
            {
              'id': 'a',
              'section': 'company',
              'text': 'Claim',
              'evidence': 'reported',
              'source_ids': <String>[],
            },
          ],
        },
        {
          ...interviewIntel(),
          'sources': [
            ...interviewIntel()['sources'] as List,
            ...interviewIntel()['sources'] as List,
          ],
        },
        {...interviewIntel(), 'extra': 'bad'},
      ];
      for (final packet in invalid) {
        await expectLater(
          repo.submitPreparation(job, 0, packet, interviewBank()),
          throwsFormatException,
        );
      }
      await expectLater(
        repo.submitPreparation(job, 0, interviewIntel(), {
          'questions': [
            {...interviewQuestion(), 'stage_id': 'foreign'},
          ],
          'coverage_gaps': [],
        }),
        throwsFormatException,
      );
      expect(await db.select(db.interviewRevisions).get(), isEmpty);
    },
  );
  test('practice start is retry-safe and pins context against edits', () async {
    await prepare();
    await repo.saveContext(
      job,
      1,
      submittedText: 'The actual submitted answer.',
      attribution: 'user_confirmed_submitted',
    );
    final first = await start(), again = await start();
    expect(first['practice_id'], again['practice_id']);
    await expectLater(start(difficulty: 4), throwsStateError);
    await repo.saveContext(
      job,
      2,
      submittedText: 'New selection.',
      attribution: 'selected_for_practice',
    );
    await repo.saveStages(job, 3, [
      {...interviewStage(), 'name': 'Changed stage'},
    ]);
    final saved = await repo.practice(first['practice_id']! as String),
        snapshot = interviewMap(saved['snapshot']);
    expect(interviewMap(snapshot['stage'])['name'], 'Technical interview');
    expect(
      interviewMap(
        interviewMap(snapshot['application_context'])['payload'],
      )['submitted_text'],
      'The actual submitted answer.',
    );
  });
  test('foreign materials and revision IDs are rejected', () async {
    await prepare();
    final other = await jobs.queueManualUrl(
      Uri.parse('https://example.test/other'),
    );
    final intel = interviewMap((await repo.get(job))['intel']);
    await expectLater(
      repo.revision(other, intel['id']! as String),
      throwsStateError,
    );
    await expectLater(
      repo.saveContext(
        job,
        1,
        materialSetId: 'missing',
        attribution: 'selected_for_practice',
      ),
      throwsStateError,
    );
    expect((await repo.get(job))['revision'], 1);
  });
  test(
    'checkpoints are idempotent, retain corrections, and require expected revision',
    () async {
      await prepare();
      final id = (await start())['practice_id']! as String;
      final first = await repo.saveExchange(id, 'line', -1, practiceExchange());
      expect(
        await repo.saveExchange(id, 'line', -1, practiceExchange()),
        first,
      );
      await expectLater(
        repo.saveExchange(id, 'line', -1, practiceExchange(score: 4)),
        throwsStateError,
      );
      await repo.saveExchange(id, 'line', 0, practiceExchange(score: 4));
      final p = await repo.practice(id),
          e = interviewMaps(p['exchanges']).single;
      expect(e['previous_revisions'], hasLength(1));
      expect(p['revision'], 2);
      expect(interviewMap(p['assessment'])['score'], 100);
    },
  );
  test(
    'partial transcript supports ungraded checkpoint and cannot silently complete',
    () async {
      await prepare();
      final id = (await start())['practice_id']! as String;
      await repo.saveExchange(id, 'line', -1, {
        ...practiceExchange(complete: false),
        'transcript_kind': 'partial',
      });
      expect(
        interviewMap((await repo.practice(id))['assessment'])['score'],
        null,
      );
      await expectLater(
        repo.setPracticeState(id, 1, 'completed', 'Finished.'),
        throwsStateError,
      );
      await repo.setPracticeState(id, 1, 'paused', '');
      await expectLater(
        repo.saveExchange(id, 'line', 0, practiceExchange()),
        throwsStateError,
      );
      await repo.setPracticeState(id, 2, 'active', '');
      await repo.saveExchange(id, 'line', 0, practiceExchange());
      final p = await repo.setPracticeState(
        id,
        4,
        'completed',
        'Improve evidence detail.',
      );
      expect(interviewMap(p['assessment'])['score'], 75);
      await expectLater(
        repo.saveExchange(id, 'line', 1, practiceExchange(score: 4)),
        throwsStateError,
      );
      await expectLater(
        repo.setPracticeState(id, 5, 'active', ''),
        throwsStateError,
      );
    },
  );
  test(
    'feedback rejects fabricated turn references, duplicate criteria, and out-of-range scores',
    () async {
      await prepare();
      final id = (await start())['practice_id']! as String;
      for (final payload in [
        practiceExchange(score: 5),
        {
          ...practiceExchange(),
          'assessments': [
            {
              'dimension': 'evidence',
              'score': 2,
              'reason': 'Claim',
              'turn_ids': ['missing'],
            },
          ],
        },
        {
          ...practiceExchange(),
          'assessments': [
            ...practiceExchange()['assessments'] as List,
            ...practiceExchange()['assessments'] as List,
          ],
        },
        {...practiceExchange(), 'question_id': 'foreign'},
      ]) {
        await expectLater(
          repo.saveExchange(id, 'line', -1, payload),
          throwsFormatException,
        );
      }
      expect((await repo.practice(id))['exchanges'], isEmpty);
    },
  );
  test('weights use dimension means and omit unassessed criteria', () {
    final one = practiceExchange(score: 4);
    final two = {
      ...practiceExchange(score: 2),
      'assessments': [
        ...practiceExchange(score: 2)['assessments'] as List,
        {
          'dimension': 'clarity',
          'score': 1,
          'reason': 'Unclear',
          'turn_ids': ['a'],
        },
      ],
    };
    final score = scoreInterview(
      [one, two],
      {
        'relevance': 1,
        'correctness': 1,
        'evidence': 3,
        'clarity': 1,
        'depth': 1,
      },
    );
    expect(score['score'], 62.5);
    expect(score['graded_questions'], 2);
    expect(interviewMap(score['dimension_counts']), {
      'evidence': 2,
      'clarity': 1,
    });
  });
  test('trends separate difficulty and exclude unfinished practices', () async {
    await prepare();
    for (var i = 0; i < 3; i++) {
      final p = await start(request: 'start-$i', difficulty: i == 0 ? 3 : 4);
      final id = p['practice_id']! as String;
      await repo.saveExchange(id, 'line', -1, practiceExchange());
      if (i < 2) await repo.setPracticeState(id, 1, 'completed', 'Debrief.');
    }
    final stats = await repo.statistics(jobId: job);
    expect(stats['groups'], hasLength(2));
    expect(
      interviewMaps(stats['groups']).map((g) => g['sample_count']),
      everyElement(1),
    );
  });
  test('file-backed practice checkpoints survive reopening', () async {
    final dir = await Directory.systemTemp.createTemp('interview-reopen-');
    final file = File('${dir.path}/test.sqlite');
    var local = CareerShopperDatabase(NativeDatabase(file));
    try {
      final localJob = await JobRepository(
        local,
      ).queueManualUrl(Uri.parse('https://example.test/reopen'));
      var store = InterviewRepository(local);
      await store.submitPreparation(
        localJob,
        0,
        interviewIntel(),
        interviewBank(),
      );
      final id =
          (await store.startPractice(
                localJob,
                'technical',
                'request',
                practiceSettings(),
              ))['practice_id']!
              as String;
      await store.saveExchange(id, 'line', -1, practiceExchange());
      await local.close();
      local = CareerShopperDatabase(NativeDatabase(file));
      store = InterviewRepository(local);
      final p = await store.practice(id);
      expect(p['exchanges'], hasLength(1));
      expect(p['status'], 'active');
      await store.setPracticeState(id, 1, 'completed', 'Resumed and finished.');
    } finally {
      await local.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'schema 17 upgrade creates interview workspace only for interviewing applications',
    () async {
      final dir = await Directory.systemTemp.createTemp('interview-upgrade-');
      final file = File('${dir.path}/test.sqlite');
      var local = CareerShopperDatabase(NativeDatabase(file));
      try {
        final job = await JobRepository(
          local,
        ).queueManualUrl(Uri.parse('https://example.test/migrate'));
        await JobRepository(local).setApplicationStatus(
          job,
          ApplicationStatus.interviewing,
          actor: 'user',
          origin: 'test',
        );
        for (final table in [
          'interview_exchanges',
          'interview_practices',
          'interview_revisions',
          'interview_workspaces',
          'interview_settings',
        ]) {
          await local.customStatement('DROP TABLE $table');
        }
        await local.customStatement('PRAGMA user_version = 17');
        await local.close();
        local = CareerShopperDatabase(NativeDatabase(file));
        expect(
          (await InterviewRepository(local).get(job))['preparation_state'],
          'needed',
        );
        expect(
          (await InterviewRepository(local).settings())['auto_prepare'],
          true,
        );
        expect(
          (await local.customSelect('PRAGMA foreign_key_check').get()),
          isEmpty,
        );
      } finally {
        await local.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
