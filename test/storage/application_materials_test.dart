import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/documents/application_exporter.dart';
import 'package:careershopper/src/documents/document_prompt.dart';
import 'package:careershopper/src/ingestion/normalization.dart';
import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/ai_agent_purpose.dart';
import 'package:careershopper/src/storage/application_material_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/document_template_repository.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:careershopper/src/storage/listing_availability_service.dart';

void main() {
  late CareerShopperDatabase db;
  late JobRepository jobs;
  late ApplicationMaterialRepository materials;
  late String jobId, markdown, factId;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    jobs = JobRepository(db);
    materials = ApplicationMaterialRepository(db);
    jobId = (await jobs.ingest(
      NormalizedListing(
        sourceFamily: 'test',
        adapterId: 'test',
        providerJobId: '1',
        title: 'Engineer',
        employerName: 'Example',
        normalizedEmployerName: 'example',
        location: 'Remote',
        description: 'Build systems.',
        contentHash: contentHash('Build systems.'),
        sourceUrl: Uri.parse('https://example.test/job'),
        applicationUrl: Uri.parse('https://example.test/apply'),
        observedAt: DateTime.now(),
      ),
    )).jobId;
    factId = await ProfileRepository(db).saveCareerFact(
      const CareerFactDraft(
        kind: 'identity',
        value: {'name': 'Alex Example'},
        visibility: 'resume',
      ),
      actor: 'user',
    );
    final fact = await (db.select(
      db.careerFacts,
    )..where((r) => r.id.equals(factId))).getSingle();
    markdown = '# Alex Example <!-- facts: ${fact.currentRevisionId} -->';
  });
  tearDown(() => db.close());

  test(
    'MCP Apply requests completion confirmation without changing state',
    () async {
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final draft = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
      );
      final output = await Directory.systemTemp.createTemp(
        'careershopper-apply-',
      );
      addTearDown(() => output.delete(recursive: true));
      final opened = <Uri>[];
      final tools = McpUiTools(
        db,
        harnesses: _harness(db, exporter: ApplicationExporter(output)),
        openUrl: (url) async {
          opened.add(url);
        },
        renderer: (_) async => ApplicationDocumentRenderer(),
      );
      final before = (await jobs.getJob(jobId))!;
      final result = await tools.call('application_apply', {
        'job_id': jobId,
        'material_set_id': draft,
        'format': 'docx',
        'confirmed': true,
        'replace_output': true,
      });
      expect(opened.single.toString(), 'https://example.test/apply');
      expect(result['completion_confirmation_required'], true);
      expect(result['application_submitted'], false);
      final after = (await jobs.getJob(jobId))!;
      expect(after.reviewState, before.reviewState);
      expect(after.applicationStatus, before.applicationStatus);
    },
  );

  for (final format in ApplicationDocumentFormat.values) {
    test(
      'MCP exports $format without opening a listing or changing state',
      () async {
        await jobs.setReviewState(
          jobId,
          ReviewState.approved,
          actor: 'user',
          origin: 'test',
        );
        final draft = await materials.save(
          jobId: jobId,
          resume: markdown,
          coverLetter: markdown,
        );
        final output = await Directory.systemTemp.createTemp(
          'careershopper-export-only-',
        );
        addTearDown(() => output.delete(recursive: true));
        final harness = _harness(db, exporter: ApplicationExporter(output));
        final tools = McpUiTools(
          db,
          harnesses: harness,
          openUrl: (_) async => fail('Export must never open a browser'),
          renderer: (_) async => ApplicationDocumentRenderer(
            regularFont: await File(
              'assets/fonts/DejaVuSans.ttf',
            ).readAsBytes(),
            boldFont: await File(
              'assets/fonts/DejaVuSans-Bold.ttf',
            ).readAsBytes(),
          ),
        );
        final before = await jobs.getJob(jobId);
        final args = <String, Object?>{
          'job_id': jobId,
          'material_set_id': draft,
          'format': format.name,
          'confirmed': true,
          'replace_output': true,
        };
        await expectLater(
          tools.call('application_documents_export', {
            ...args,
            'confirmed': false,
          }),
          throwsFormatException,
        );
        await expectLater(
          tools.call('application_documents_export', {
            ...args,
            'replace_output': false,
          }),
          throwsStateError,
        );
        await expectLater(
          tools.call(
            'application_documents_export',
            args,
            workOrderId: 'scoped',
          ),
          throwsStateError,
        );
        final result = await tools.call('application_documents_export', args);
        expect(result['listing_opened'], false);
        expect(result['application_submitted'], false);
        expect(result['files'], [
          'resume.${format.name}',
          'cover letter.${format.name}',
        ]);
        final directory = result['output_directory'];
        expect(directory, '${output.path}/Documents/CareerShopper');
        expect(await File('$directory/resume.${format.name}').exists(), isTrue);
        expect(
          await File('$directory/cover letter.${format.name}').exists(),
          isTrue,
        );
        final after = await jobs.getJob(jobId);
        expect(after!.reviewState, before!.reviewState);
        expect(after.applicationStatus, before.applicationStatus);
        expect((await materials.get(draft)).reviewedAt, isNull);
        await ProfileRepository(db).retireCareerFact(factId, actor: 'user');
        await expectLater(
          tools.call('application_documents_export', args),
          throwsStateError,
        );
      },
    );
  }

  test(
    'formatted metadata and blocks use the same confirmed-fact validation',
    () async {
      final fact = await (db.select(
        db.careerFacts,
      )..where((r) => r.id.equals(factId))).getSingle();
      final id = fact.currentRevisionId;
      final source =
          '---\nsubtitle: Engineer\nfooter: Alex Example\n--- <!-- facts: $id -->\n\n$markdown\n\n## DIRECT MATCH <!-- facts: $id -->\n\n- **Ownership:** Supported systems. <!-- facts: $id -->\n\n<!-- pagebreak -->\n\n*Project dates* <!-- facts: $id -->';
      await materials.validate(source, markdown);
      await expectLater(
        materials.validate(
          source.replaceFirst(
            '--- <!-- facts: $id -->',
            '--- <!-- facts: missing-revision -->',
          ),
          markdown,
        ),
        throwsStateError,
      );
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final saved = await materials.save(
        jobId: jobId,
        resume: source,
        coverLetter: markdown,
      );
      expect((await materials.get(saved)).resumeMarkdown, source);
      expect(
        (await db.select(db.materialClaims).get()).any(
          (c) => c.blockText.isEmpty,
        ),
        isFalse,
      );
    },
  );

  test(
    'immutable reviewed drafts retain claim sources and reject stale edits',
    () async {
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final first = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
      );
      expect((await materials.watch(jobId).first)!.reviewed, isFalse);
      final edited = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
        reviewed: true,
        expectedMaterialId: first,
      );
      expect((await materials.watch(jobId).first)!.id, edited);
      expect((await materials.watch(jobId).first)!.reviewed, isTrue);
      expect(await db.select(db.materialSets).get(), hasLength(2));
      expect(await db.select(db.materialClaims).get(), hasLength(4));
      await expectLater(
        materials.save(
          jobId: jobId,
          resume: markdown,
          coverLetter: markdown,
          reviewed: true,
          expectedMaterialId: first,
        ),
        throwsStateError,
      );
      await ProfileRepository(db).retireCareerFact(factId, actor: 'user');
      await expectLater(
        materials.validate(markdown, markdown),
        throwsStateError,
      );
    },
  );

  test(
    'Apply accepts unreviewed drafts but refuses superseded or outdated drafts',
    () async {
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final output = await Directory.systemTemp.createTemp(
        'careershopper-optional-review-',
      );
      addTearDown(() => output.delete(recursive: true));
      final harness = _harness(db, exporter: ApplicationExporter(output));
      final original = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
      );
      Future<String> export(String id) => harness.exportApplication(
        jobId,
        id,
        ApplicationDocumentFormat.docx,
        ApplicationDocumentRenderer(),
      );
      final path = await export(original);
      expect(await File('$path/resume.docx').exists(), isTrue);
      expect(await File('$path/cover letter.docx').exists(), isTrue);
      expect((await materials.get(original)).reviewedAt, isNull);
      final reviewed = await harness.saveMaterials(
        jobId,
        original,
        markdown,
        markdown,
      );
      await expectLater(export(original), throwsStateError);
      await ProfileRepository(db).retireCareerFact(factId, actor: 'user');
      await expectLater(export(reviewed), throwsStateError);
    },
  );

  test('pending and private references cannot be submitted', () async {
    await db
        .update(db.careerFactRevisions)
        .write(
          const CareerFactRevisionsCompanion(
            verificationStatus: Value('pending'),
          ),
        );
    await expectLater(materials.validate(markdown, markdown), throwsStateError);
    await db
        .update(db.careerFactRevisions)
        .write(
          const CareerFactRevisionsCompanion(
            verificationStatus: Value('confirmed'),
            visibility: Value('private'),
          ),
        );
    await expectLater(materials.validate(markdown, markdown), throwsStateError);
  });

  test(
    'generation receives the upgraded saved project-heading instructions',
    () async {
      final templates = DocumentTemplateRepository(db);
      await templates.ensureDefaults();
      await templates.saveResumeTemplate(
        ResumeTemplateDraft(
          id: defaultResumeTemplateId,
          name: 'Pipeline Classic',
          settings: ResumeTemplateSettings.fromJson({
            ...ResumeTemplateSettings.defaults().toJson(),
            'generation_prompt': File(
              'test/fixtures/document-prompt-descriptive-project-headings.txt',
            ).readAsStringSync(),
          }),
        ),
      );
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      await harness.queueApplication(jobId);
      await runner.started.future;
      expect(runner.request!.prompt, contains(defaultDocumentGenerationPrompt));
      expect(
        runner.request!.prompt,
        isNot(contains('name, actual product/platform type')),
      );
      final read = await McpUiTools(db).call('document_template_get', {});
      expect(
        (read['settings'] as Map)['generation_prompt'],
        defaultDocumentGenerationPrompt,
      );
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((status) => status == 'failed');
    },
  );

  test(
    'queue generates scoped drafts, review stays separate from applying, regeneration preserves old drafts',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      final templates = DocumentTemplateRepository(db);
      await templates.ensureDefaults();
      final template = (await templates.watchDefaultResumeTemplate().first)!;
      await templates.saveResumeTemplate(
        ResumeTemplateDraft(
          id: template.id,
          name: template.name,
          settings: ResumeTemplateSettings.fromJson({
            ...template.settings.toJson(),
            'generation_prompt': 'Emphasize ownership and product impact.',
          }),
        ),
      );
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final original = (await harness.watchProfiles().first).single.id;
      final writer = await harness.duplicateProfile(
        original,
        'Thorough writer',
      );
      await db.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ? WHERE id = ?',
        ['{"effort":"high"}', writer],
      );
      await harness.setPurposeProfile(
        AiAgentPurpose.applicationWriting,
        writer,
      );
      final result = await harness.queueApplication(jobId);
      await runner.started.future;
      expect(result.profileName, 'Thorough writer');
      expect(runner.request!.configValues, {'effort': 'high'});
      expect(runner.request!.prompt, contains('application_materials_submit'));
      expect(
        runner.request!.prompt,
        contains('Emphasize ownership and product impact.'),
      );
      expect((await jobs.getJob(jobId))!.reviewState, ReviewState.approved);
      expect(
        (await jobs.getJob(jobId))!.applicationStatus,
        ApplicationStatus.readyToApply,
      );
      expect((await harness.queueApplication(jobId)).launched, isFalse);
      final response = await _submit(
        db,
        result.workOrderId,
        jobId,
        _completeMarkdown(markdown),
      );
      expect(response, isNot(contains('error')));
      expect(await materials.watch(jobId).first, isNull);
      expect(await harness.watchMaterialStatus(jobId).first, 'running');
      final corrected = _completeMarkdown(
        markdown,
      ).replaceAll('built', 'maintained');
      expect(
        await _submit(db, result.workOrderId, jobId, corrected),
        isNot(contains('error')),
      );
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
      final draft = (await materials.watch(jobId).first)!;
      expect(draft.resume, corrected);
      expect(draft.reviewed, isFalse);
      await harness.saveMaterials(jobId, draft.id, markdown, markdown);
      await jobs.setApplicationStatus(
        jobId,
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'test',
      );
      final failedRunner = _Runner();
      final secondHarness = _harness(db, runner: failedRunner);
      await secondHarness.queueApplication(jobId);
      await failedRunner.started.future;
      failedRunner.finished.complete();
      await secondHarness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'failed');
      expect(
        (await jobs.getJob(jobId))!.applicationStatus,
        ApplicationStatus.applied,
      );
      expect((await materials.watch(jobId).first)!.reviewed, isTrue);
    },
  );

  test(
    'MCP cannot generate materials without an authorized scoped work order',
    () async {
      expect(await _submit(db, null, jobId, markdown), contains('error'));
      expect(await db.select(db.materialSets).get(), isEmpty);
    },
  );

  test(
    'diagnostic validation is read-only and skeletal submission cannot replace existing drafts',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final original = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
        reviewed: true,
      );
      expect(
        await _submit(
          db,
          queued.workOrderId,
          jobId,
          markdown,
          tool: 'application_materials_validate',
        ),
        isNot(contains('error')),
      );
      expect(await db.select(db.materialSets).get(), hasLength(1));
      expect(await harness.watchMaterialStatus(jobId).first, 'running');
      final response = await _submit(db, queued.workOrderId, jobId, markdown);
      expect(response['error'].toString(), contains('incomplete'));
      expect(await db.select(db.materialSets).get(), hasLength(1));
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((status) => status == 'failed');
      expect((await materials.watch(jobId).first)!.id, original);
    },
  );

  for (final failure in [
    'runner error',
    'invalid correction',
    'changed facts',
  ]) {
    test('provisional drafts stay hidden after $failure', () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final original = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
        reviewed: true,
      );
      expect(
        await _submit(
          db,
          queued.workOrderId,
          jobId,
          _completeMarkdown(markdown),
        ),
        isNot(contains('error')),
      );
      expect((await materials.watch(jobId).first)!.id, original);
      if (failure == 'invalid correction') {
        expect(
          await _submit(db, queued.workOrderId, jobId, markdown),
          contains('error'),
        );
      }
      if (failure == 'changed facts') {
        await ProfileRepository(db).retireCareerFact(factId, actor: 'user');
      }
      if (failure == 'runner error') {
        runner.finished.completeError(StateError('ACP transport failed'));
      } else {
        runner.finished.complete();
      }
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((status) => status == 'failed');
      expect((await materials.watch(jobId).first)!.id, original);
      expect((await materials.watch(jobId).first)!.reviewed, isTrue);
      expect(
        (await db.select(db.materialSets).get()).where((row) => row.staged),
        hasLength(1),
      );
    });
  }

  test(
    'v9 migration preserves existing document publication and adds staging',
    () async {
      // Independent memory database and a disposable on-disk migration copy.
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'careershopper-staging-migration-',
      );
      final file = File('${directory.path}/test.sqlite3');
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final original = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
        reviewed: true,
      );
      await db.customStatement('VACUUM INTO ?', [file.path]);
      var local = CareerShopperDatabase(NativeDatabase(file));
      try {
        await local.customSelect('SELECT * FROM material_sets').get();
        await local.customStatement(
          'ALTER TABLE material_sets DROP COLUMN staged',
        );
        await local.customStatement('PRAGMA user_version = 9');
        await local.close();
        local = CareerShopperDatabase(NativeDatabase(file));
        final preserved = (await local.select(local.materialSets).get()).single;
        expect(preserved.id, original);
        expect(preserved.resumeMarkdown, markdown);
        expect(preserved.staged, isFalse);
        expect(
          (await ApplicationMaterialRepository(
            local,
          ).watch(jobId).first)!.reviewed,
          isTrue,
        );
        final columns = await local
            .customSelect("PRAGMA table_info('material_sets')")
            .get();
        expect(
          columns
              .singleWhere((row) => row.data['name'] == 'staged')
              .data['dflt_value'],
          '0',
        );
        expect(
          (await local.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          local.schemaVersion,
        );
      } finally {
        await local.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      }
    },
  );

  test(
    'expiry retains staged and published drafts, rejects late publication, and allows retry',
    () async {
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final previous = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
      );
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      await _submit(db, queued.workOrderId, jobId, _completeMarkdown(markdown));
      final staged = await db.select(db.materialSets).get();
      expect(staged, hasLength(2));
      expect(
        await harness.recoverExpiredWork(
          now: DateTime.now().add(const Duration(hours: 1)),
        ),
        1,
      );
      expect((await materials.watch(jobId).first)!.id, previous);
      expect(await db.select(db.materialSets).get(), staged);
      expect(await harness.watchMaterialStatus(jobId).first, 'failed');
      await expectLater(
        materials.publishGeneration(queued.workOrderId),
        throwsStateError,
      );
      final retryRunner = _Runner();
      final retry = await _harness(
        db,
        runner: retryRunner,
      ).queueApplication(jobId);
      expect(retry.launched, isTrue);
      expect(retry.workOrderId, queued.workOrderId);
      expect((await materials.watch(jobId).first)!.id, previous);
      await retryRunner.started.future;
      retryRunner.finished.complete();
      await harness.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
      await harness.interruptConversation(queued.workOrderId);
    },
  );

  test(
    'a resumed turn can correct a failed staged generation without publishing the old candidate',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      await (db.update(
        db.aiWorkOrders,
      )..where((row) => row.id.equals(queued.workOrderId))).write(
        const AiWorkOrdersCompanion(acpSessionId: Value('test-session')),
      );
      expect(
        await _submit(
          db,
          queued.workOrderId,
          jobId,
          _completeMarkdown(markdown),
        ),
        isNot(contains('error')),
      );
      runner.finished.completeError(StateError('transport failed'));
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((status) => status == 'failed');
      expect(await materials.watch(jobId).first, isNull);

      final resumed = _Runner();
      final resumedHarness = _harness(db, runner: resumed);
      await resumedHarness.sendMessage(
        queued.workOrderId,
        'Correct and submit the complete documents.',
      );
      await resumed.started.future;
      expect(resumed.request!.existingSessionId, 'test-session');
      expect(await materials.watch(jobId).first, isNull);
      final corrected = _completeMarkdown(
        markdown,
      ).replaceAll('built', 'maintained');
      expect(
        await _submit(db, queued.workOrderId, jobId, corrected),
        isNot(contains('error')),
      );
      // A read-only diagnostic check must not replace or invalidate the submission.
      expect(
        await _submit(
          db,
          queued.workOrderId,
          jobId,
          markdown,
          tool: 'application_materials_validate',
        ),
        isNot(contains('error')),
      );
      resumed.finished.complete();
      await resumedHarness
          .watchMaterialStatus(jobId)
          .firstWhere((status) => status == 'completed');
      expect((await materials.watch(jobId).first)!.resume, corrected);
    },
  );
  test(
    'writer gets confirmed facts up front and reviews stay isolated with at most two passes',
    () async {
      final requests = <AcpRunRequest>[];
      var writerTurns = 0;
      final runner = _WorkflowRunner((request) async {
        requests.add(request);
        if (request.recruitingReviewer) {
          expect(request.existingSessionId, isNull);
          expect(request.prompt, contains('Build systems.'));
          expect(request.prompt, isNot(contains('Confirmed profile:')));
          expect(request.prompt, isNot(contains('evaluation_summary')));
          expect(request.prompt, contains('Your only task is to decide'));
          expect(
            request.prompt,
            contains('You are not a proofreader, editor, or resume coach'),
          );
          expect(request.prompt, contains('Do not critique document length'));
          expect(request.prompt, isNot(contains('recommend splitting')));
          expect(request.prompt, isNot(contains('specific customer impact')));
          expect(request.prompt, isNot(contains('original-writer')));
          expect(request.prompt, isNot(contains('Recruiting screen 1')));
          expect(
            request.prompt,
            contains(writerTurns > 1 ? 'maintained' : 'built'),
          );
          await request.onSessionUpdate!({
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text':
                    'Do not promote to human review. The documents do not demonstrate specific customer impact required by the listing.',
              },
            },
          }, false);
          return;
        }
        writerTurns++;
        if (writerTurns == 1) {
          expect(request.prompt, contains('Confirmed profile:'));
          expect(request.prompt, contains('Alex Example'));
          expect(request.prompt, contains('Do not probe individual blocks'));
          await request.onSessionStarted!('original-writer');
        } else {
          expect(request.existingSessionId, 'original-writer');
          expect(request.prompt, contains('specific customer impact'));
        }
        final tool = {
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'submit',
            'title': 'application_materials_submit',
          },
        };
        await request.onSessionUpdate!(tool, false);
        await request.onSessionUpdate!(tool, false);
        await request.onSessionUpdate!({
          'update': {
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'submit',
            'status': 'completed',
          },
        }, false);
        await request.onSessionUpdate!({
          'update': {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'old',
            'title': 'replayed',
          },
        }, true);
        expect(
          await _submit(
            db,
            request.workOrderId,
            jobId,
            _completeMarkdown(
              markdown,
            ).replaceAll('built', writerTurns > 1 ? 'maintained' : 'built'),
            requestSecondReview: writerTurns > 1,
          ),
          isNot(contains('error')),
        );
      });
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Writer',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final dispatch = await harness.queueApplication(jobId);
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed' || s == 'failed');
      expect(await harness.watchMaterialStatus(jobId).first, 'completed');
      expect(requests, hasLength(5));
      expect(requests.where((r) => r.recruitingReviewer), hasLength(2));
      final activity = await harness.watchActivity(dispatch.workOrderId).first;
      expect(
        activity.where((a) => a.kind == 'recruiting_review'),
        hasLength(2),
      );
      final summary = activity.last;
      expect(summary.kind, 'run_summary');
      expect(summary.details['tool_call_count'], 3);
      expect(summary.details['elapsed_ms'], isNonNegative);
      expect(summary.text, contains('3 tool calls'));
      expect(
        (await materials.watch(jobId).first)!.resume,
        contains('maintained'),
      );
      expect(
        (await jobs.getJob(jobId))!.applicationOutcome,
        ApplicationOutcome.active,
      );
    },
  );

  test(
    'a reviewer failure preserves published documents and ends with a failed summary',
    () async {
      await jobs.setReviewState(
        jobId,
        ReviewState.approved,
        actor: 'user',
        origin: 'test',
      );
      final old = await materials.save(
        jobId: jobId,
        resume: markdown,
        coverLetter: markdown,
      );
      final runner = _WorkflowRunner((r) async {
        if (r.recruitingReviewer) throw StateError('Review unavailable');
        await r.onSessionStarted!('writer');
        await _submit(db, r.workOrderId, jobId, _completeMarkdown(markdown));
      });
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Writer',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final run = await harness.queueApplication(jobId);
      await harness.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
      expect((await materials.watch(jobId).first)!.id, old);
      final activity = await harness.watchActivity(run.workOrderId).first;
      expect(activity.last.kind, 'run_summary');
      expect(activity.last.details['status'], 'failed');
      expect(
        activity.any(
          (e) => e.kind == 'error' && e.text.contains('Review unavailable'),
        ),
        true,
      );
    },
  );

  for (final failure in ['malformed', 'transport', 'legacy']) {
    test(
      'resume failed second review preserves drafts and skips completed steps ($failure)',
      () async {
        final requests = <AcpRunRequest>[];
        var writerTurns = 0;
        var reviews = 0;
        final firstRunner = _WorkflowRunner((request) async {
          requests.add(request);
          if (request.recruitingReviewer) {
            reviews++;
            if (reviews == 2 && failure == 'transport') {
              throw StateError('review connection failed');
            }
            await request.onSessionUpdate!({
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {
                  'type': 'text',
                  'text': reviews == 2
                      ? 'Incomplete assessment without a decision.'
                      : 'Promote to human review. Relevant experience.',
                },
              },
            }, false);
            return;
          }
          writerTurns++;
          await request.onSessionStarted!('saved-writer');
          expect(
            await _submit(
              db,
              request.workOrderId,
              jobId,
              _completeMarkdown(
                markdown,
              ).replaceAll('built', writerTurns == 1 ? 'built' : 'maintained'),
              requestSecondReview: writerTurns == 2,
            ),
            isNot(contains('error')),
          );
        });
        final first = _harness(db, runner: firstRunner);
        await first.saveProfile(
          const AiHarnessProfileDraft(
            name: 'Writer',
            executable: '/bin/true',
            arguments: [],
          ),
        );
        final dispatched = await first.queueApplication(jobId);
        await first.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
        await pumpEventQueue();
        expect(writerTurns, 2);
        expect(reviews, 2);
        expect(await materials.watch(jobId).first, isNull);
        final savedPair =
            (await (db.select(db.materialSets)
                  ..orderBy([
                    (r) => OrderingTerm.desc(r.createdAt),
                    (r) => OrderingTerm.desc(r.id),
                  ])
                  ..limit(1))
                .getSingle());
        expect(savedPair.resumeMarkdown, contains('maintained'));
        final activity = await first
            .watchActivity(dispatched.workOrderId)
            .first;
        expect(
          activity.any(
            (e) =>
                e.kind ==
                (failure == 'transport'
                    ? 'recruiting_review_error'
                    : 'recruiting_review_invalid'),
          ),
          true,
        );
        if (failure == 'legacy') {
          final order = await (db.select(
            db.aiWorkOrders,
          )..where((r) => r.id.equals(dispatched.workOrderId))).getSingle();
          final scope = jsonDecode(order.scopeJson) as Map<String, dynamic>;
          scope.remove('materials_checkpoint');
          await (db.update(
            db.aiWorkOrders,
          )..where((r) => r.id.equals(order.id))).write(
            AiWorkOrdersCompanion(scopeJson: Value(jsonEncode(scope))),
          );
        }
        final resumedRequests = <AcpRunRequest>[];
        // Reconstruct the harness to exercise durable recovery after an app restart.
        final resumed = _harness(
          db,
          runner: _WorkflowRunner((request) async {
            resumedRequests.add(request);
            expect(request.workOrderId, dispatched.workOrderId);
            if (request.recruitingReviewer) {
              expect(request.prompt, contains('maintained'));
              expect(request.existingSessionId, isNull);
              await request.onSessionUpdate!({
                'update': {
                  'sessionUpdate': 'agent_message_chunk',
                  'content': {
                    'type': 'text',
                    'text':
                        '**Recommendation:** Promote to human review. Supported work.',
                  },
                },
              }, false);
            } else {
              expect(request.existingSessionId, 'saved-writer');
              expect(request.prompt, contains('completed pass 2'));
              expect(request.prompt, contains(savedPair.id));
              // No changes needed; a completed original submission is still valid.
            }
          }),
        );
        await resumed.resumeMaterialGeneration(dispatched.workOrderId);
        await resumed
            .watchMaterialStatus(jobId)
            .firstWhere((s) => s == 'completed' || s == 'failed');
        expect(await resumed.watchMaterialStatus(jobId).first, 'completed');
        expect(resumedRequests, hasLength(2));
        expect(resumedRequests.first.recruitingReviewer, true);
        expect((await materials.watch(jobId).first)!.id, savedPair.id);
        expect(await db.select(db.aiWorkOrders).get(), hasLength(1));
        await expectLater(
          resumed.resumeMaterialGeneration(dispatched.workOrderId),
          throwsStateError,
        );
      },
    );
  }

  test(
    'resume a failed writer correction reuses its completed review and requires submission',
    () async {
      var initial = true;
      final runner = _WorkflowRunner((request) async {
        if (request.recruitingReviewer) {
          await request.onSessionUpdate!({
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text': 'Promote to human review. Clarify impact.',
              },
            },
          }, false);
        } else if (initial) {
          initial = false;
          await request.onSessionStarted!('writer-context');
          await _submit(
            db,
            request.workOrderId,
            jobId,
            _completeMarkdown(markdown),
          );
        } else {
          throw StateError('writer transport failed');
        }
      });
      final first = _harness(db, runner: runner);
      await first.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Writer',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final dispatch = await first.queueApplication(jobId);
      await first.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
      await pumpEventQueue();
      var shouldSubmit = false;
      final retry = _harness(
        db,
        runner: _WorkflowRunner((request) async {
          expect(request.recruitingReviewer, false);
          expect(request.existingSessionId, 'writer-context');
          expect(request.prompt, contains('Clarify impact'));
          expect(request.prompt, contains('resumed correction step'));
          if (shouldSubmit) {
            await _submit(
              db,
              request.workOrderId,
              jobId,
              _completeMarkdown(markdown).replaceAll('built', 'maintained'),
            );
          }
        }),
      );
      expect(
        (await retry.queueApplication(jobId)).workOrderId,
        dispatch.workOrderId,
      );
      await retry.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
      await pumpEventQueue();
      expect(await materials.watch(jobId).first, isNull);
      shouldSubmit = true;
      expect(
        (await retry.queueApplication(jobId)).workOrderId,
        dispatch.workOrderId,
      );
      await retry
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed' || s == 'failed');
      expect(await retry.watchMaterialStatus(jobId).first, 'completed');
      expect(
        (await materials.watch(jobId).first)!.resume,
        contains('maintained'),
      );
    },
  );

  test(
    'an expired preflight skips the writer and preserves review and application stage',
    () async {
      var calls = 0;
      final harness = AiHarnessRepository(
        db,
        runner: _WorkflowRunner((_) async {
          calls++;
        }),
        availability: ListingAvailabilityService(
          db,
          clientFactory: () => MockClient(
            (_) async =>
                http.Response('<main>This job has expired.</main>', 200),
          ),
        ),
      );
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Writer',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final dispatch = await harness.queueApplication(jobId);
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
      final job = (await jobs.getJob(jobId))!;
      expect(calls, 0);
      expect(job.applicationOutcome, ApplicationOutcome.expired);
      expect(job.availability, JobAvailability.closed);
      expect(job.applicationStatus, ApplicationStatus.readyToApply);
      expect(job.reviewState, ReviewState.approved);
      expect(await jobs.watchInbox().first, isEmpty);
      expect(await materials.watch(jobId).first, isNull);
      expect(
        (await harness.watchActivity(dispatch.workOrderId).first)
            .last
            .details['tool_call_count'],
        0,
      );
    },
  );

  test(
    'employer attribution rejects mixed cover-letter paragraphs and misplaced resume bullets',
    () async {
      final refs = await _seedAttributionFacts(db);
      final wrong =
          'At Northwind, I reviewed a change request. <!-- facts: ${refs['team-b']} -->';
      await expectLater(
        materials.validate(markdown, '$markdown\n\n$wrong'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'diagnostic',
            allOf(
              contains('Cover letter, block 2'),
              contains('Northwind'),
              contains('Contoso'),
              contains('team-b'),
            ),
          ),
        ),
      );
      final heading =
          '### Northwind, Engineer <!-- facts: ${refs['employer-a']} -->';
      final misplaced =
          '- Reviewed a change request. <!-- facts: ${refs['team-b']} -->';
      await expectLater(
        materials.validate('$markdown\n\n$heading\n\n$misplaced', markdown),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'diagnostic',
            contains('employer attribution mismatch'),
          ),
        ),
      );
      await expectLater(
        materials.validate(
          markdown,
          '$markdown\n\nAt NW, I reviewed a change request. <!-- facts: ${refs['team-b']} -->',
        ),
        throwsStateError,
      );
      await expectLater(
        materials.validate(
          markdown,
          '$markdown\n\nAt Northwind, I built the client project. <!-- facts: ${refs['project-work-b']} -->',
        ),
        throwsStateError,
      );
      // Explicit attribution permits a comparison without transferring metrics.
      await materials.validate(
        markdown,
        '$markdown\n\nAt Northwind, I led up to five people. Earlier, at Contoso, I led three. <!-- facts: ${refs['team-a']}, ${refs['team-b']} -->',
      );
      await materials.validate(
        markdown,
        '$markdown\n\nLed teams of three and up to five people across my career. <!-- facts: ${refs['team-a']}, ${refs['team-b']} -->',
      );
      // Shared skills carry no employer-specific ownership claim.
      await materials.validate(
        '$markdown\n\n$heading\n\n- Led up to five people using shared development tools. <!-- facts: ${refs['team-a']}, ${refs['shared-skill']} -->',
        markdown,
      );
      // A new section clears the employer scope inherited from a work heading.
      await materials.validate(
        '$markdown\n\n$heading\n\n## Earlier experience <!-- facts: ${refs['employer-b']} -->\n\n$misplaced',
        markdown,
      );
    },
  );

  test(
    'MCP rejects wrong employer attribution before staging and accepts a supported correction',
    () async {
      final refs = await _seedAttributionFacts(db);
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final source = _completeMarkdown(markdown);
      final bad =
          '$source\n\nAt Northwind, I reviewed a change request. <!-- facts: ${refs['team-b']} -->';
      final failed = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'resume_markdown': source,
        'cover_letter_markdown': bad,
      });
      expect(
        failed['error'].toString(),
        contains('employer attribution mismatch'),
      );
      expect(await db.select(db.materialSets).get(), isEmpty);
      final handle = ((failed['error'] as Map)['data'] as Map)['draft_id'];
      final repaired = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'draft_id': handle,
        'edits': [
          {
            'document': 'cover_letter',
            'old_text': 'At Northwind, I reviewed a change request.',
            'new_text': 'At Contoso, I reviewed a change request.',
          },
        ],
      });
      expect(repaired, isNot(contains('error')));
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
      expect(
        (await materials.watch(jobId).first)!.coverLetter,
        contains('At Contoso, I reviewed a change request.'),
      );
    },
  );

  test(
    'short citations survive reconnects and review edits and store exact revisions',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final order = await (db.select(
        db.aiWorkOrders,
      )..where((r) => r.id.equals(queued.workOrderId))).getSingle();
      final refs = (jsonDecode(order.scopeJson) as Map)['citation_refs'] as Map;
      final revision = RegExp(
        r'<!-- facts: (.*?) -->',
      ).firstMatch(markdown)!.group(1)!;
      expect(refs, {'F1': revision});
      expect(runner.request!.prompt, contains('"citation_ref":"F1"'));
      expect(runner.request!.prompt, isNot(contains(revision)));
      final source = _completeMarkdown(markdown.replaceAll(revision, 'F1'));
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final fetched = await _rpc(server, 'profile_get', {});
      expect(jsonEncode(fetched), contains('"citation_ref":"F1"'));
      final submitted = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'resume_markdown': source,
        'cover_letter_markdown': source,
      });
      expect(submitted, isNot(contains('error')));
      final baseId =
          ((submitted['result'] as Map)['structuredContent']
                  as Map)['material_set_id']
              as String;
      expect(
        (await materials.get(baseId)).resumeMarkdown,
        source.replaceAll('F1', revision),
      );
      // Reviewer resumes in a new process; writer still has short refs in context.
      final revised = await _rpc(
        McpServer(db, workOrderId: queued.workOrderId),
        'application_materials_submit',
        {
          'job_id': jobId,
          'base_material_set_id': baseId,
          'edits': [
            {
              'document': 'resume',
              'old_text': '# Alex Example <!-- facts: F1 -->',
              'new_text': '# **Alex Example** <!-- facts: F1 -->',
            },
          ],
        },
      );
      expect(revised, isNot(contains('error')));
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
      final saved = (await materials.watch(jobId).first)!;
      expect(saved.resume, contains('# **Alex Example**'));
      expect(saved.resume, isNot(contains('facts: F1')));
      expect(saved.resume, contains(revision));
      expect(
        (await db.select(db.materialClaims).get()).every(
          (claim) => (jsonDecode(claim.factRevisionIdsJson) as List).every(
            (id) => id == revision,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'short refs never remap a revised or private fact and unknown refs fail',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final unknown = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'resume_markdown': '# Alex <!-- facts: F999 -->',
        'cover_letter_markdown': markdown,
      });
      expect(unknown['error'].toString(), contains('F999'));
      await ProfileRepository(db).saveCareerFact(
        CareerFactDraft(
          id: factId,
          kind: 'identity',
          value: {'name': 'Alex Changed'},
          visibility: 'private',
        ),
        actor: 'user',
      );
      final stale = await _rpc(
        McpServer(db, workOrderId: queued.workOrderId),
        'application_materials_submit',
        {
          'job_id': jobId,
          'resume_markdown': _completeMarkdown('# Alex <!-- facts: F1 -->'),
          'cover_letter_markdown': _completeMarkdown(
            '# Alex <!-- facts: F1 -->',
          ),
        },
      );
      expect(stale['error'].toString(), contains('current confirmed revision'));
      expect(await db.select(db.materialSets).get(), isEmpty);
      runner.finished.complete();
      await harness.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
    },
  );

  test(
    'repeated citation edits require explicit replace_all and diagnose missing matches',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final source = _completeMarkdown('# Alex Example <!-- facts: F1 -->');
      final bad = source.replaceAll('F1', 'F999');
      final invalid = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'resume_markdown': bad,
        'cover_letter_markdown': source,
      });
      final handle = ((invalid['error'] as Map)['data'] as Map)['draft_id'];
      final multiple = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'draft_id': handle,
        'edits': [
          {'document': 'resume', 'old_text': 'F999', 'new_text': 'F1'},
        ],
      });
      expect(
        multiple['error'].toString(),
        allOf(
          contains('Edit 1 (resume)'),
          contains('replace_all=true'),
          contains('No edits were applied'),
        ),
      );
      final missing = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'draft_id': handle,
        'edits': [
          {
            'document': 'resume',
            'old_text': 'F888',
            'new_text': 'F1',
            'replace_all': true,
          },
        ],
      });
      expect(
        missing['error'].toString(),
        allOf(contains('Edit 1 (resume)'), contains('matched 0 times')),
      );
      final fixed = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'draft_id': handle,
        'edits': [
          {
            'document': 'resume',
            'old_text': 'F999',
            'new_text': 'F1',
            'replace_all': true,
          },
        ],
      });
      expect(fixed, isNot(contains('error')));
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
    },
  );

  test(
    'draft handles support atomic corrections and submission without repeating documents',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final complete = _completeMarkdown(markdown);
      final revision = RegExp(
        r'<!-- facts: (.*?) -->',
      ).firstMatch(markdown)!.group(1)!;
      final bad = complete.replaceFirst(revision, 'citation-typo');
      final failed = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'resume_markdown': bad,
        'cover_letter_markdown': complete,
      });
      final draftId = ((failed['error'] as Map)['data'] as Map)['draft_id'];
      expect(draftId, isA<String>());
      expect(await db.select(db.materialSets).get(), isEmpty);
      final ambiguous = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'draft_id': draftId,
        'edits': [
          {
            'document': 'resume',
            'old_text': 'citation-typo',
            'new_text': revision,
          },
          {'document': 'resume', 'old_text': '<!-- facts:', 'new_text': ''},
        ],
      });
      expect(ambiguous['error'].toString(), contains('exactly once'));
      // The first edit in a rejected batch must not have changed the buffer.
      final corrected = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'draft_id': draftId,
        'edits': [
          {
            'document': 'resume',
            'old_text': 'citation-typo',
            'new_text': revision,
          },
        ],
      });
      expect(corrected, isNot(contains('error')));
      final handle =
          ((corrected['result'] as Map)['structuredContent']
              as Map)['draft_id'];
      final foreignProcess = await _rpc(
        McpServer(db, workOrderId: queued.workOrderId),
        'application_materials_submit',
        {'job_id': jobId, 'draft_id': handle},
      );
      expect(
        foreignProcess['error'].toString(),
        contains('Unknown or expired'),
      );
      final submitted = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'draft_id': handle,
      });
      expect(submitted, isNot(contains('error')));
      final baseId =
          ((submitted['result'] as Map)['structuredContent']
              as Map)['material_set_id'];
      expect((await materials.get(baseId as String)).resumeMarkdown, complete);
      // A resumed reviewer/writer session reuses the persisted staged pair.
      final resumed = McpServer(db, workOrderId: queued.workOrderId);
      final revised = await _rpc(resumed, 'application_materials_submit', {
        'job_id': jobId,
        'base_material_set_id': baseId,
        'edits': [
          {
            'document': 'resume',
            'old_text': '# Alex Example',
            'new_text': '# **Alex Example**',
          },
        ],
      });
      expect(revised, isNot(contains('error')));
      final revisionId =
          ((revised['result'] as Map)['structuredContent']
                  as Map)['material_set_id']
              as String;
      expect(
        (await materials.get(revisionId)).resumeMarkdown,
        contains('# **Alex Example**'),
      );
      expect((await materials.get(baseId)).resumeMarkdown, complete);
      runner.finished.complete();
      await harness
          .watchMaterialStatus(jobId)
          .firstWhere((s) => s == 'completed');
      final closed = await _rpc(resumed, 'application_materials_submit', {
        'job_id': jobId,
        'base_material_set_id': revisionId,
      });
      expect(closed['error'].toString(), contains('active, user-requested'));
    },
  );

  test(
    'handles revalidate changed facts and cannot reuse unrelated base materials',
    () async {
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      final server = McpServer(db, workOrderId: queued.workOrderId);
      final complete = _completeMarkdown(markdown);
      final unrelated = await materials.save(
        jobId: jobId,
        resume: complete,
        coverLetter: complete,
      );
      final denied = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'base_material_set_id': unrelated,
      });
      expect(denied['error'].toString(), contains('this job and work order'));
      final valid = await _rpc(server, 'application_materials_validate', {
        'job_id': jobId,
        'resume_markdown': complete,
        'cover_letter_markdown': complete,
      });
      final handle =
          ((valid['result'] as Map)['structuredContent'] as Map)['draft_id'];
      await ProfileRepository(db).saveCareerFact(
        CareerFactDraft(
          id: factId,
          kind: 'identity',
          value: {'name': 'Alex Example'},
          visibility: 'private',
        ),
        actor: 'user',
      );
      final rejected = await _rpc(server, 'application_materials_submit', {
        'job_id': jobId,
        'draft_id': handle,
      });
      expect(
        rejected['error'].toString(),
        contains('current confirmed revision'),
      );
      expect(await db.select(db.materialSets).get(), hasLength(1));
      runner.finished.complete();
      await harness.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
    },
  );

  test(
    'confidential evidence is excluded from writer context and rejected on validation',
    () async {
      final profile = ProfileRepository(db);
      final secretId = await profile.saveCareerFact(
        const CareerFactDraft(
          kind: 'project',
          value: {'name': 'Secret Widget', 'disclosure_status': 'confidential'},
          visibility: 'application_only',
        ),
        actor: 'user',
      );
      await profile.saveCareerFact(
        const CareerFactDraft(
          kind: 'project',
          value: {'name': 'Private Widget'},
          visibility: 'private',
        ),
        actor: 'user',
      );
      final secret = (await profile.watchCareerFacts().first).singleWhere(
        (f) => f.id == secretId,
      );
      await expectLater(
        materials.validate(
          '$markdown\n\nSecret Widget <!-- facts: ${secret.revisionId} -->',
          markdown,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('confidential'),
          ),
        ),
      );
      final runner = _Runner();
      final harness = _harness(db, runner: runner);
      await harness.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final queued = await harness.queueApplication(jobId);
      await runner.started.future;
      expect(runner.request!.prompt, isNot(contains('Secret Widget')));
      expect(runner.request!.prompt, isNot(contains('Private Widget')));
      for (final server in [
        McpServer(db, workOrderId: queued.workOrderId),
        McpServer(db, answerWriter: true),
      ]) {
        final result = await _rpc(server, 'profile_get', {});
        expect(jsonEncode(result), isNot(contains('Secret Widget')));
        expect(jsonEncode(result), isNot(contains('Private Widget')));
        expect(jsonEncode(result), contains('Alex Example'));
      }
      expect(
        jsonEncode(await _rpc(McpServer(db), 'profile_get', {})),
        contains('Secret Widget'),
      );
      runner.finished.complete();
      await harness.watchMaterialStatus(jobId).firstWhere((s) => s == 'failed');
    },
  );

  test(
    'validator reports document block and every invalid revision instead of a generic error',
    () async {
      await expectLater(
        materials.validate(
          '$markdown\n\nBad <html> <!-- facts: missing -->',
          markdown,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Resume'), contains('Block 2')),
          ),
        ),
      );
      await expectLater(
        materials.validate(
          '$markdown\n\nClaim <!-- facts: missing-one, missing-two -->',
          markdown,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Resume, block 2'),
              contains('missing-one'),
              contains('missing-two'),
            ),
          ),
        ),
      );
    },
  );
}

String _completeMarkdown(String name) {
  final citation = RegExp(r'<!-- facts: .*? -->').firstMatch(name)!.group(0)!;
  return '$name\n\n## Experience $citation\n\n'
      'Alex built backend services for customer account management, taking responsibility for requirements, design, implementation, testing, deployment, and production support. The work included collaborating with product colleagues to understand customer needs and making clear technical decisions about reliable service behavior. $citation\n\n'
      'Alex also built database integrations, investigated production issues, documented operational procedures, and reviewed changes with other engineers to keep the services understandable and maintainable. $citation';
}

AiHarnessRepository _harness(
  CareerShopperDatabase db, {
  AcpAgentRunner? runner,
  ApplicationExporter? exporter,
}) => AiHarnessRepository(
  db,
  runner: runner,
  exporter: exporter,
  availability: ListingAvailabilityService(
    db,
    clientFactory: () =>
        MockClient((_) async => http.Response('<main>Apply now</main>', 200)),
  ),
);

class _Runner implements AcpAgentRunner {
  AcpRunRequest? request;
  final started = Completer<void>();
  final finished = Completer<void>();
  @override
  Future<void> run(AcpRunRequest request) async {
    if (request.recruitingReviewer) {
      await request.onSessionUpdate?.call({
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': 'Promote to human review. Relevant supported experience.',
          },
        },
      }, false);
      return;
    }
    if (started.isCompleted) return;
    this.request = request;
    await request.onSessionStarted?.call('writer-session');
    started.complete();
    await Future.any([
      finished.future,
      if (request.control != null) request.control!.whenCancelled,
    ]);
    request.control?.checkCancelled();
  }
}

Future<Map<String, Object?>> _submit(
  CareerShopperDatabase db,
  String? orderId,
  String jobId,
  String markdown, {
  String tool = 'application_materials_submit',
  bool requestSecondReview = false,
}) async {
  final controller = StreamController<List<int>>();
  final sink = IOSink(controller.sink);
  final response = controller.stream.transform(utf8.decoder).join();
  await McpServer(db, workOrderId: orderId).serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': tool,
            'arguments': {'job_id': jobId, 'resume_markdown': markdown, 'cover_letter_markdown': markdown, if (requestSecondReview) 'request_second_review': true},
          },
        })}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return (jsonDecode(await response) as Map).cast<String, Object?>();
}

class _WorkflowRunner implements AcpAgentRunner {
  _WorkflowRunner(this.action);
  final Future<void> Function(AcpRunRequest) action;
  @override
  Future<void> run(AcpRunRequest request) => action(request);
}

Future<Map<String, Object?>> _rpc(
  McpServer server,
  String tool,
  Map<String, Object?> arguments,
) async {
  final controller = StreamController<List<int>>();
  final sink = IOSink(controller.sink);
  final response = controller.stream.transform(utf8.decoder).join();
  await server.serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {'name': tool, 'arguments': arguments},
        })}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return (jsonDecode(await response) as Map).cast<String, Object?>();
}

Future<Map<String, String>> _seedAttributionFacts(
  CareerShopperDatabase db,
) async {
  final profile = ProfileRepository(db);
  final fixtures = <String, (String, Map<String, Object?>)>{
    'employer-a': (
      'employment',
      {
        'employer': 'Northwind',
        'employer_aliases': ['NW'],
      },
    ),
    'employer-b': ('employment', {'employer': 'Contoso'}),
    'team-a': (
      'achievement',
      {
        'statement': 'Documented a release process.',
        'context_fact_ids': ['employer-a', 'shared-skill'],
      },
    ),
    'team-b': (
      'achievement',
      {
        'statement': 'Reviewed a change request.',
        'context_fact_ids': ['employer-b'],
      },
    ),
    'shared-skill': (
      'skill',
      {
        'name': 'Shared development tools',
        'context_fact_ids': ['employer-a', 'employer-b'],
      },
    ),
    'project-b': (
      'project',
      {
        'name': 'Client project',
        'context_fact_ids': ['employer-b'],
      },
    ),
    'project-work-b': (
      'achievement',
      {
        'statement': 'Built the client project.',
        'context_fact_ids': ['project-b'],
      },
    ),
  };
  for (final entry in fixtures.entries) {
    await profile.saveCareerFact(
      CareerFactDraft(
        id: entry.key,
        kind: entry.value.$1,
        value: entry.value.$2,
        visibility: 'resume',
      ),
      actor: 'user',
    );
  }
  return {
    for (final fact in await profile.watchCareerFacts().first)
      fact.id: fact.revisionId,
  };
}
