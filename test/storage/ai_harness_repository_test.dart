import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/domain/chat_image.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/protocol/acp_configuration.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/ai_agent_purpose.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late AiHarnessRepository harnesses;
  late JobRepository jobs;
  late _PendingAcpRunner runner;

  setUp(() {
    database = CareerShopperDatabase(NativeDatabase.memory());
    runner = _PendingAcpRunner();
    harnesses = AiHarnessRepository(database, runner: runner);
    jobs = JobRepository(database);
  });

  tearDown(() => database.close());

  test(
    'approval activity preserves the requested action and exact selected permission through MCP',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final id = await harnesses.startConversation('Draft materials');
      await _waitFor(() => runner.requests.isNotEmpty);
      final call = {
        'toolCallId': 'exec-example',
        'title': 'mcp.careershopper_session.application_materials_submit',
        'rawInput': {'job_id': 'job-123'},
      };
      for (final update in [
        {
          'sessionUpdate': 'permission_request',
          'title': 'Approval required',
          'toolCall': call,
          'options': [
            {'optionId': 'always', 'kind': 'allow_always'},
          ],
          'workingDirectory': '/tmp/work',
        },
        {
          'sessionUpdate': 'permission_decision',
          'title': 'Always allowed',
          'toolCall': call,
          'optionId': 'always',
          'optionKind': 'allow_always',
        },
      ]) {
        await runner.requests.first.onSessionUpdate!({'update': update}, false);
      }
      final result = await McpUiTools(
        database,
        harnesses: harnesses,
      ).call('ai_conversation_get', {'conversation_id': id});
      final approvals = (result['activity'] as List)
          .where((a) => a['kind'].toString().startsWith('permission_'))
          .toList();
      expect(approvals, hasLength(2));
      expect(approvals.first['details']['toolCall'], call);
      expect(approvals.first['details']['workingDirectory'], '/tmp/work');
      expect(approvals.last['details']['optionKind'], 'allow_always');
      runner.complete(0);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.single.status == 'completed',
      );
    },
  );

  test(
    'chat interruption and completion each persist measured summaries through MCP',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final id = await harnesses.startConversation('Explain the job');
      await _waitFor(() => runner.requests.isNotEmpty);
      await runner.requests.first.onSessionStarted!('saved-chat');
      await runner.requests.first.onSessionUpdate!({
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'one',
          'title': 'job_get',
        },
      }, false);
      await harnesses.interruptConversation(id);
      final first = (await harnesses.watchActivity(id).first).last;
      expect(first.kind, 'run_summary');
      expect(first.details['status'], 'interrupted');
      expect(first.details['tool_call_count'], 1);
      await harnesses.sendMessage(id, 'Continue');
      await _waitFor(() => runner.requests.length == 2);
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.single.status == 'completed',
      );
      final result = await McpUiTools(
        database,
        harnesses: harnesses,
      ).call('ai_conversation_get', {'conversation_id': id});
      final summaries = (result['activity'] as List)
          .where((r) => r['kind'] == 'run_summary')
          .toList();
      expect(summaries, hasLength(2));
      expect(summaries.last['details']['status'], 'completed');
      expect(summaries.last['details']['tool_call_count'], 0);
      expect(summaries.last['details']['elapsed_ms'], isNonNegative);
    },
  );

  test(
    'chat images are saved, readable through MCP, and included when steering',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final image = ChatImage.fromBytes(
        await File('test/fixtures/chat-image.png').readAsBytes(),
      );
      final id = await harnesses.startConversation('', images: [image]);
      await _waitFor(() => runner.requests.isNotEmpty);
      expect(runner.requests.single.images.single.bytes, image.bytes);
      await runner.requests.single.onSessionStarted!('image-session');
      final activity = await harnesses.watchActivity(id).first;
      expect(activity.single.images.single.bytes, image.bytes);
      final read = await McpUiTools(
        database,
        harnesses: harnesses,
      ).call('ai_conversation_get', {'conversation_id': id});
      expect(((read['activity'] as List).single as Map)['images'], [
        image.toContentBlock(),
      ]);
      await harnesses.sendMessage(id, 'Compare this', images: [image]);
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.existingSessionId, 'image-session');
      expect(runner.requests.last.images.single.bytes, image.bytes);
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (items) => items.single.status == 'completed',
      );
      expect(
        (await harnesses.watchActivity(id).first).where(
          (e) => e.images.isNotEmpty,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'v14 migration adds empty notes and preserves historical job activity',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final dir = await Directory.systemTemp.createTemp(
        'job-context-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      var local = CareerShopperDatabase(NativeDatabase(file));
      final job = await JobRepository(
        local,
      ).queueManualUrl(Uri.parse('https://example.test/migrate'));
      final now = DateTime.now();
      await local
          .into(local.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'old',
              kind: 'search_analysis',
              status: 'completed',
              scopeJson: '{}',
              promptVersion: 'test',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await local
          .into(local.aiWorkItems)
          .insert(
            AiWorkItemsCompanion.insert(
              id: 'old-item',
              workOrderId: 'old',
              subjectId: job,
              status: 'completed',
              idempotencyKey: 'old-item',
              updatedAt: now,
            ),
          );
      await local.customStatement('ALTER TABLE jobs DROP COLUMN notes');
      await local.customStatement(
        'ALTER TABLE ai_work_orders DROP COLUMN job_id',
      );
      await local.customStatement('PRAGMA user_version = 14');
      await local.close();
      local = CareerShopperDatabase(NativeDatabase(file));
      expect(await JobRepository(local).watchJobNotes(job).first, '');
      expect(
        (await AiHarnessRepository(
          local,
        ).watchConversations(jobId: job).first).single.id,
        'old',
      );
      await JobRepository(
        local,
      ).saveJobNotes(job, 'Retained', expectedNotes: '');
      await local.close();
      local = CareerShopperDatabase(NativeDatabase(file));
      expect(await JobRepository(local).watchJobNotes(job).first, 'Retained');
      await local.close();
    },
  );

  test(
    'job discussions inherit selected visible context and resume their own session',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Context agent',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final job = await jobs.queueManualUrl(
        Uri.parse('https://example.test/context'),
      );
      final other = await jobs.queueManualUrl(
        Uri.parse('https://example.test/other'),
      );
      final imported = await harnesses.dispatchManualImport(job);
      await _waitFor(() => runner.requests.length == 1);
      await runner.requests[0].onSessionStarted!('original-session');
      await runner.requests[0].onSessionUpdate!({
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'text',
            'text': 'The listing claims remote but mentions office visits.',
          },
        },
      }, false);
      await database.customStatement(
        "UPDATE ai_work_items SET status = 'completed' WHERE work_order_id = ?",
        [imported.workOrderId],
      );
      runner.complete(0);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.single.status == 'completed',
      );
      await jobs.saveJobNotes(
        job,
        'Ask about required office visits.',
        expectedNotes: '',
      );
      expect(await harnesses.watchConversations(jobId: other).first, isEmpty);
      await expectLater(
        harnesses.startJobConversation(
          other,
          'Explain',
          contextConversationId: imported.workOrderId,
        ),
        throwsArgumentError,
      );
      final discussion = await harnesses.startJobConversation(
        job,
        'Is this remote?',
        contextConversationId: imported.workOrderId,
      );
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests[1].existingSessionId, isNull);
      expect(
        runner.requests[1].prompt,
        contains('The listing claims remote but mentions office visits.'),
      );
      expect(
        runner.requests[1].prompt,
        contains('Ask about required office visits.'),
      );
      expect(runner.requests[1].prompt, contains(job));
      await runner.requests[1].onSessionStarted!('discussion-session');
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (rows) =>
            rows.firstWhere((r) => r.id == discussion).status == 'completed',
      );
      await jobs.saveJobNotes(
        job,
        'Recruiter says one office day.',
        expectedNotes: 'Ask about required office visits.',
      );
      await harnesses.sendMessage(discussion, 'What should I clarify?');
      await _waitFor(() => runner.requests.length == 3);
      expect(runner.requests[2].existingSessionId, 'discussion-session');
      expect(
        runner.requests[2].prompt,
        contains('Recruiter says one office day.'),
      );
      final original = await (database.select(
        database.aiWorkOrders,
      )..where((row) => row.id.equals(imported.workOrderId))).getSingle();
      expect(original.status, 'completed');
      expect(original.acpSessionId, 'original-session');
      final mcp = McpUiTools(database);
      final linked = await mcp.call('ai_conversations_list', {'job_id': job});
      expect(
        (linked['conversations'] as List).map((c) => (c as Map)['id']),
        containsAll([imported.workOrderId, discussion]),
      );
      final context = await mcp.call('job_context_get', {
        'job_id': job,
        'conversation_id': imported.workOrderId,
      });
      expect(context['notes'], 'Recruiter says one office day.');
      expect(context['prior_activity_truncated'], false);
      runner.complete(2);
      await harnesses.watchConversations().firstWhere(
        (rows) =>
            rows.firstWhere((r) => r.id == discussion).status == 'completed',
      );
    },
  );

  test(
    'purpose assignments and copies preserve independent settings',
    () async {
      final original = await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Writer',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      await database.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ? WHERE id = ?',
        ['{"effort":"high"}', original],
      );
      final copy = await harnesses.duplicateProfile(original, 'Fast matching');
      final copied = await (database.select(
        database.aiHarnessProfiles,
      )..where((r) => r.id.equals(copy))).getSingle();
      expect(copied.configValuesJson, '{"effort":"high"}');
      expect(copied.isDefault, false);
      expect(copied.isJobMatchingDefault, false);
      await database.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ? WHERE id = ?',
        ['{"effort":"low"}', copy],
      );
      await harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, copy);
      await harnesses.setPurposeProfile(
        AiAgentPurpose.applicationWriting,
        original,
      );
      expect(
        (await resolveAiProfile(
          database,
          purpose: AiAgentPurpose.jobMatching,
        ))!.configValuesJson,
        '{"effort":"low"}',
      );
      expect(
        (await resolveAiProfile(
          database,
          purpose: AiAgentPurpose.applicationWriting,
        ))!.configValuesJson,
        '{"effort":"high"}',
      );
      await harnesses.saveProfile(
        AiHarnessProfileDraft(
          id: copy,
          name: 'Renamed',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      expect(
        (await resolveAiProfile(
          database,
          purpose: AiAgentPurpose.jobMatching,
        ))!.id,
        copy,
      );
      final profiles = await McpUiTools(database).call('ai_profiles_list', {});
      expect(
        (profiles['profiles'] as List)
            .where((p) => (p as Map)['is_job_matching_default'] == true)
            .single,
        containsPair('id', copy),
      );
      await expectLater(
        harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, 'missing'),
        throwsArgumentError,
      );
      expect(
        (await resolveAiProfile(
          database,
          purpose: AiAgentPurpose.jobMatching,
        ))!.id,
        copy,
      );
      await harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, original);
      expect(
        (await harnesses.watchProfiles().first).where(
          (p) => p.isJobMatchingDefault,
        ),
        hasLength(1),
      );
      await harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, copy);
      await harnesses.deleteProfile(copy);
      expect(
        (await resolveAiProfile(
          database,
          purpose: AiAgentPurpose.jobMatching,
        ))!.id,
        original,
      );
      await harnesses.setPurposeProfile(
        AiAgentPurpose.applicationWriting,
        null,
      );
      expect(
        (await harnesses.watchProfiles().first)
            .single
            .isApplicationWritingDefault,
        false,
      );
      expect(runner.requests, isEmpty);
    },
  );

  test(
    'search and import use matching settings while chat retains general defaults',
    () async {
      final original = await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'General',
          executable: '/bin/general',
          arguments: [],
        ),
      );
      final fast = await harnesses.duplicateProfile(original, 'Fast');
      await database.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ? WHERE id = ?',
        ['{"effort":"low"}', fast],
      );
      await harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, fast);
      final searchJob = await jobs.queueManualUrl(
        Uri.parse('https://example.test/search'),
      );
      final importJob = await jobs.queueManualUrl(
        Uri.parse('https://example.test/import'),
      );
      await harnesses.dispatchSearchAnalysis([searchJob]);
      await harnesses.dispatchManualImport(importJob);
      await harnesses.startConversation('Hello');
      await _waitFor(() => runner.requests.length == 3);
      final orders = await database.select(database.aiWorkOrders).get();
      for (final order in orders) {
        final chat = order.kind == 'interactive_chat';
        expect(order.agentId, chat ? original : fast);
        expect(
          jsonDecode(order.configValuesJson),
          chat ? {} : {'effort': 'low'},
        );
        expect(
          runner.requests
              .singleWhere((r) => r.workOrderId == order.id)
              .configValues,
          chat ? {} : {'effort': 'low'},
        );
      }
      await harnesses.setPurposeProfile(AiAgentPurpose.jobMatching, original);
      expect(
        (await database.select(database.aiWorkOrders).get())
            .where((o) => o.kind != 'interactive_chat')
            .every((o) => o.agentId == fast),
        true,
      );
    },
  );

  test(
    'v13 migration retains profiles and settings with default routing',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final dir = await Directory.systemTemp.createTemp(
        'agent-purpose-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      var local = CareerShopperDatabase(NativeDatabase(file));
      final repo = AiHarnessRepository(local);
      final id = await repo.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Existing',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      await local.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ?',
        ['{"effort":"high"}'],
      );
      await local.customStatement(
        'ALTER TABLE ai_harness_profiles DROP COLUMN is_job_matching_default',
      );
      await local.customStatement(
        'ALTER TABLE ai_harness_profiles DROP COLUMN is_application_writing_default',
      );
      await local.customStatement('PRAGMA user_version = 13');
      await local.close();
      local = CareerShopperDatabase(NativeDatabase(file));
      for (final purpose in AiAgentPurpose.values) {
        final selected = await resolveAiProfile(local, purpose: purpose);
        expect(selected!.id, id);
        expect(selected.configValuesJson, '{"effort":"high"}');
        expect(selected.isJobMatchingDefault, false);
        expect(selected.isApplicationWritingDefault, false);
      }
      await local.close();
    },
  );

  test(
    'successful import refreshes an existing status watcher after MCP writes',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final jobId = await jobs.queueManualUrl(
        Uri.parse('https://example.test/job'),
      );
      final dispatched = await harnesses.dispatchManualImport(jobId);
      await _waitFor(() => runner.requests.isNotEmpty);
      final statuses = <String>[];
      final completed = Completer<void>();
      final subscription = harnesses.watchConversations().listen((orders) {
        final status = orders.single.status;
        statuses.add(status);
        if (status == 'completed' && !completed.isCompleted) {
          completed.complete();
        }
      });
      try {
        await _waitFor(() => statuses.contains('running'));
        // Raw SQL simulates the helper's writes without this connection's Drift
        // notifications. Keep the same subscription throughout the test.
        await database.customStatement(
          "UPDATE ai_work_items SET status = 'completed' WHERE work_order_id = ?",
          [dispatched.workOrderId],
        );
        await database.customStatement(
          "UPDATE ai_work_orders SET status = 'completed' WHERE id = ?",
          [dispatched.workOrderId],
        );
        expect(statuses.last, 'running');
        runner.complete(0);
        await completed.future.timeout(const Duration(seconds: 3));
        expect(statuses.last, 'completed');
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'defaults persist, new work inherits them, conversation settings override them',
    () async {
      final profileId = await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final settings = harnesses.configureAgent(
        (session) async {},
        profileId: profileId,
      );
      await _waitFor(() => runner.requests.length == 1);
      final session = AcpConfigurationSession(
        AcpConfigOption.parse([
          {
            'id': 'engine',
            'name': 'Model',
            'type': 'select',
            'category': 'model',
            'currentValue': 'beta',
            'options': [
              {'value': 'beta', 'name': 'Beta'},
            ],
          },
        ]),
        (_, _) async => [],
      );
      expect(runner.requests.first.configurationOnly, isTrue);
      await runner.requests.first.configure!(session);
      runner.complete(0);
      await settings;
      final profile = await database
          .select(database.aiHarnessProfiles)
          .getSingle();
      expect(jsonDecode(profile.configValuesJson), {'engine': 'beta'});
      await harnesses.saveProfile(
        AiHarnessProfileDraft(
          id: profileId,
          name: 'Renamed',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      expect(
        (await database.select(database.aiHarnessProfiles).getSingle())
            .configValuesJson,
        profile.configValuesJson,
      );
      final id = await harnesses.startConversation('hello');
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests[1].configValues, {'engine': 'beta'});
      await expectLater(
        harnesses.configureAgent((_) async {}, conversationId: id),
        throwsStateError,
      );
      await runner.requests[1].onSessionStarted!('session');
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.single.status == 'completed',
      );
      final conversationSettings = harnesses.configureAgent(
        (_) async {},
        conversationId: id,
      );
      await _waitFor(() => runner.requests.length == 3);
      expect(runner.requests[2].existingSessionId, 'session');
      await expectLater(
        harnesses.sendMessage(id, 'while configuring'),
        throwsStateError,
      );
      session.options = AcpConfigOption.parse([
        {
          'id': 'engine',
          'name': 'Model',
          'type': 'select',
          'currentValue': 'alpha',
          'options': [
            {'value': 'alpha', 'name': 'Alpha'},
          ],
        },
      ]);
      await runner.requests[2].configure!(session);
      runner.complete(2);
      await conversationSettings;
      await harnesses.sendMessage(id, 'continue');
      await _waitFor(() => runner.requests.length == 4);
      expect(runner.requests[3].configValues, {'engine': 'alpha'});
      final jobId = await jobs.queueManualUrl(
        Uri.parse('https://example.test/job'),
      );
      await harnesses.dispatchManualImport(jobId);
      await _waitFor(() => runner.requests.length == 5);
      expect(runner.requests[4].configValues, {'engine': 'beta'});
      await session.close();
    },
  );

  test('v8 migration adds draft provenance and review metadata', () async {
    final warning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp(
      'careershopper-material-migration-',
    );
    final file = File('${directory.path}/database.sqlite3');
    var db = CareerShopperDatabase(NativeDatabase(file));
    try {
      await db.customSelect('SELECT * FROM material_sets').get();
      await db.customStatement(
        'ALTER TABLE material_sets DROP COLUMN work_order_id',
      );
      await db.customStatement(
        'ALTER TABLE material_sets DROP COLUMN reviewed_at',
      );
      await db.customStatement('PRAGMA user_version = 8');
      await db.close();
      db = CareerShopperDatabase(NativeDatabase(file));
      final columns = await db
          .customSelect("PRAGMA table_info('material_sets')")
          .get();
      expect(
        columns.map((r) => r.data['name']),
        containsAll(['work_order_id', 'reviewed_at']),
      );
      expect(await db.select(db.materialSets).get(), isEmpty);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = warning;
    }
  });

  test('v7 migration preserves records and adds empty settings', () async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final directory = await Directory.systemTemp.createTemp(
      'careershopper-config-migration-',
    );
    final file = File('${directory.path}/database.sqlite3');
    var db = CareerShopperDatabase(NativeDatabase(file));
    try {
      final repository = AiHarnessRepository(db, runner: runner);
      await repository.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Existing',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      await db.customStatement(
        'ALTER TABLE ai_harness_profiles DROP COLUMN config_values_json',
      );
      await db.customStatement(
        'ALTER TABLE ai_work_orders DROP COLUMN config_values_json',
      );
      await db.customStatement('PRAGMA user_version = 7');
      await db.close();
      db = CareerShopperDatabase(NativeDatabase(file));
      final profile = await db.select(db.aiHarnessProfiles).getSingle();
      expect(profile.name, 'Existing');
      expect(profile.configValuesJson, '{}');
      expect(
        (await db.customSelect("PRAGMA table_info('ai_work_orders')").get())
            .any((row) => row.data['name'] == 'config_values_json'),
        isTrue,
      );
    } finally {
      await db.close();
      await directory.delete(recursive: true);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    }
  });

  test(
    'recovers only expired active runs and preserves completed items and history',
    () async {
      final now = DateTime.now().toUtc();
      for (final (id, status, deadline) in [
        ('expired', 'running', now.subtract(const Duration(hours: 1))),
        ('fresh', 'running', now.add(const Duration(hours: 1))),
        ('done', 'completed', now.subtract(const Duration(hours: 1))),
      ]) {
        await database
            .into(database.aiWorkOrders)
            .insert(
              AiWorkOrdersCompanion.insert(
                id: id,
                kind: 'application_materials',
                status: status,
                scopeJson: '{}',
                promptVersion: 'test',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await database.customStatement(
          'UPDATE ai_work_orders SET leased_until = ? WHERE id = ?',
          [deadline.millisecondsSinceEpoch ~/ 1000, id],
        );
        for (final itemStatus in ['running', 'submitted', 'completed']) {
          await database
              .into(database.aiWorkItems)
              .insert(
                AiWorkItemsCompanion.insert(
                  id: '$id-$itemStatus',
                  workOrderId: id,
                  subjectId: '$id-$itemStatus',
                  status: itemStatus,
                  idempotencyKey: '$id-$itemStatus',
                  updatedAt: now,
                ),
              );
        }
      }
      expect(await harnesses.recoverExpiredWork(now: now), 1);
      expect(await harnesses.recoverExpiredWork(now: now), 0);
      final orders = await database.select(database.aiWorkOrders).get();
      expect(orders.firstWhere((o) => o.id == 'expired').status, 'failed');
      expect(orders.firstWhere((o) => o.id == 'fresh').status, 'running');
      expect(orders.firstWhere((o) => o.id == 'done').status, 'completed');
      final items = await database.select(database.aiWorkItems).get();
      expect(
        items.firstWhere((i) => i.id == 'expired-running').status,
        'failed',
      );
      expect(
        items.firstWhere((i) => i.id == 'expired-submitted').status,
        'failed',
      );
      expect(
        items.firstWhere((i) => i.id == 'expired-completed').status,
        'completed',
      );
      final activity = await harnesses.watchActivity('expired').first;
      expect(activity.single.text, contains('interrupted'));
      expect(await harnesses.watchActivity('fresh').first, isEmpty);
    },
  );

  test(
    'deadline monitor recovers work that expires while the app is open',
    () async {
      final now = DateTime.now().toUtc();
      final deadline = now.add(const Duration(seconds: 1));
      await database
          .into(database.aiWorkOrders)
          .insert(
            AiWorkOrdersCompanion.insert(
              id: 'expires',
              kind: 'interactive_chat',
              status: 'running',
              scopeJson: '{}',
              promptVersion: 'test',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database.customStatement(
        'UPDATE ai_work_orders SET leased_until = ?',
        [deadline.millisecondsSinceEpoch ~/ 1000],
      );
      await harnesses.monitorWorkExpiry();
      try {
        await harnesses
            .watchConversations()
            .firstWhere((rows) => rows.single.status == 'failed')
            .timeout(const Duration(seconds: 3));
      } finally {
        await harnesses.stopWorkExpiryMonitor();
      }
    },
  );

  test('first saved harness becomes the default', () async {
    await harnesses.saveProfile(
      const AiHarnessProfileDraft(
        name: 'Test harness',
        executable: '/bin/true',
        arguments: ['--acp'],
      ),
    );

    final profiles = await harnesses.watchProfiles().first;
    expect(profiles, hasLength(1));
    expect(profiles.single.isDefault, isTrue);
  });

  test('profile must use ACP stdio', () async {
    expect(
      () => harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Invalid',
          executable: '/bin/true',
          arguments: ['--version'],
          protocol: 'legacy_process',
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'search batches claim each eligible job once and expose incomplete work',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final first = await jobs.queueManualUrl(
        Uri.parse('https://example.test/1'),
      );
      final second = await jobs.queueManualUrl(
        Uri.parse('https://example.test/2'),
      );
      final evaluated = await jobs.queueManualUrl(
        Uri.parse('https://example.test/3'),
      );
      await database.customStatement(
        'UPDATE jobs SET current_evaluation_id = ? WHERE id = ?',
        ['existing', evaluated],
      );
      await database.customStatement(
        "UPDATE jobs SET review_state = 'hidden_by_search' WHERE id = ?",
        [second],
      );
      expect(
        await harnesses.dispatchSearchAnalysis([
          first,
          second,
          evaluated,
          first,
        ]),
        2,
      );
      expect(
        (await jobs.getJob(second))!.reviewState,
        ReviewState.pendingEvaluation,
      );
      expect(await harnesses.dispatchSearchAnalysis([first, second]), 0);
      await _waitFor(() => runner.requests.isNotEmpty);
      expect(runner.requests, hasLength(1));
      final orders = await database.select(database.aiWorkOrders).get();
      expect(orders, hasLength(2));
      expect(
        orders
            .map((o) => (jsonDecode(o.scopeJson)['job_ids'] as List).single)
            .toSet(),
        {first, second},
      );
      expect(runner.requests.single.scopedMcp, isTrue);
      expect(runner.requests.single.jobId, first);
      expect(runner.requests.single.existingSessionId, isNull);
      expect(
        runner.requests.single.prompt,
        contains(jobEvaluationScoringInstructions),
      );
      expect(
        runner.requests.single.prompt,
        contains('confidence as a number from 0 through 1 inclusive'),
      );
      expect(
        runner.requests.single.prompt,
        contains('for 78% confidence, use 0.78, not 78'),
      );
      expect(runner.requests.single.prompt, isNot(contains(second)));
      await runner.requests.first.onSessionStarted!('first-job-session');
      await database.customStatement(
        "UPDATE ai_work_items SET status = 'completed' WHERE subject_id = ?",
        [first],
      );
      runner.complete(0);
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.jobId, second);
      expect(runner.requests.last.existingSessionId, isNull);
      expect(
        runner.requests.last.workOrderId,
        isNot(runner.requests.first.workOrderId),
      );
      expect(runner.requests.last.prompt, isNot(contains(first)));
      expect(
        runner.requests.last.prompt,
        contains('single-job search evaluation'),
      );
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.any((r) => r.status == 'failed'),
      );
      final items = await database.select(database.aiWorkItems).get();
      expect(items.firstWhere((i) => i.subjectId == first).status, 'completed');
      expect(items.firstWhere((i) => i.subjectId == second).status, 'failed');
    },
  );

  test(
    'Indeed search evaluation uses saved content and source URL, retaining application URL',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      for (final description in [
        'Build Node.js services.',
        '',
        'Build services [description truncated]',
      ]) {
        final index = runner.requests.length;
        final source = Uri.parse(
          'https://www.indeed.com/viewjob?jk=test$index',
        );
        final application = Uri.parse('https://external.test/apply/$index');
        final result = await jobs.ingest(
          NormalizedListing(
            sourceFamily: 'indeed',
            adapterId: 'indeed_public_search_v1',
            providerJobId: 'test$index',
            title: 'Engineer',
            employerName: 'Example',
            normalizedEmployerName: 'example',
            location: 'Remote',
            description: description,
            contentHash: 'hash$index',
            sourceUrl: source,
            applicationUrl: application,
            observedAt: DateTime.now().toUtc(),
          ),
        );
        expect(await harnesses.dispatchSearchAnalysis([result.jobId]), 1);
        await _waitFor(() => runner.requests.length == index + 1);
        final request = runner.requests.last;
        expect(request.jobUrl, source.toString());
        expect(request.existingSessionId, isNull);
        expect(request.prompt, contains('skip steps 2 through 4'));
        expect(
          request.prompt,
          contains('empty, a search excerpt, visibly cut off'),
        );
        expect(
          request.prompt,
          contains('do not by themselves mean it is incomplete'),
        );
        expect(request.prompt, isNot(contains(application.toString())));
        expect(request.prompt, contains(jobEvaluationScoringInstructions));
        expect(request.prompt, contains(companyContextInstructions));
        expect(request.prompt, contains('Company research is separate'));
        final saved = await jobs.getJob(result.jobId);
        expect(saved!.applicationUrl, application);
        expect(saved.description, description);
        runner.complete(index);
        await harnesses.watchConversations().firstWhere(
          (rows) =>
              rows.every((r) => r.status != 'running' && r.status != 'queued'),
        );
      }
    },
  );

  for (final fromSearch in [true, false]) {
    test(
      'LinkedIn ${fromSearch ? 'search evaluation' : 'manual import'} receives local retrieval and block guidance',
      () async {
        await harnesses.saveProfile(
          const AiHarnessProfileDraft(
            name: 'Test',
            executable: '/bin/true',
            arguments: [],
          ),
        );
        final source = Uri.parse('https://www.linkedin.com/jobs/view/123');
        final String jobId;
        if (fromSearch) {
          final result = await jobs.ingest(
            NormalizedListing(
              sourceFamily: 'linkedin',
              adapterId: 'linkedin_guest_search_v1',
              providerJobId: '123',
              title: 'Engineer',
              employerName: 'Example',
              normalizedEmployerName: 'example',
              location: 'Remote',
              description: '',
              contentHash: 'empty',
              sourceUrl: source,
              applicationUrl: source,
              observedAt: DateTime.now().toUtc(),
            ),
          );
          jobId = result.jobId;
          expect(await harnesses.dispatchSearchAnalysis([jobId]), 1);
        } else {
          jobId = await jobs.queueManualUrl(source);
          expect(
            (await harnesses.dispatchManualImport(jobId)).launched,
            isTrue,
          );
        }
        await _waitFor(() => runner.requests.isNotEmpty);
        final request = runner.requests.single;
        expect(request.jobId, jobId);
        expect(request.jobUrl, source.toString());
        expect(request.prompt, contains('Call `job_posting_fetch`'));
        expect(request.prompt, contains('with `confirmed: true`'));
        expect(
          request.prompt,
          contains(
            'If `blocked: true`, stop without retries or switching tools',
          ),
        );
        if (fromSearch) {
          expect(request.prompt, contains('skip steps 2 through 4'));
        }
        // Dispatch supplies retrieval instructions without fabricating content.
        expect((await jobs.getJob(jobId))!.description, isEmpty);
        runner.complete(0);
        await harnesses.watchConversations().firstWhere(
          (rows) => rows.every(
            (row) => row.status != 'running' && row.status != 'queued',
          ),
        );
      },
    );
  }

  test(
    'search queue continues after one job fails and skips jobs changed while waiting',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(
          await jobs.queueManualUrl(Uri.parse('https://example.test/queue/$i')),
        );
      }
      expect(await harnesses.dispatchSearchAnalysis(ids), 3);
      await _waitFor(() => runner.requests.length == 1);
      await database.customStatement(
        "UPDATE jobs SET review_state = 'discarded' WHERE id = ?",
        [ids[1]],
      );
      runner.complete(0); // No evaluation: fails only this job.
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.jobId, ids[2]);
      expect(runner.requests.last.existingSessionId, isNull);
      await database.customStatement(
        "UPDATE ai_work_items SET status = 'completed' WHERE subject_id = ?",
        [ids[2]],
      );
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (rows) => rows.every((r) => !['queued', 'running'].contains(r.status)),
      );
      final items = await database.select(database.aiWorkItems).get();
      expect(items.firstWhere((i) => i.subjectId == ids[0]).status, 'failed');
      expect(items.firstWhere((i) => i.subjectId == ids[1]).status, 'skipped');
      expect(
        items.firstWhere((i) => i.subjectId == ids[2]).status,
        'completed',
      );
    },
  );

  test('manual URL dispatch creates one scoped running work order', () async {
    await harnesses.saveProfile(
      const AiHarnessProfileDraft(
        name: 'Test harness',
        executable: '/bin/true',
        arguments: ['--acp'],
      ),
    );
    final jobId = await jobs.queueManualUrl(
      Uri.parse('https://jobs.example.test/roles/123'),
    );

    final first = await harnesses.dispatchManualImport(jobId);
    final second = await harnesses.dispatchManualImport(jobId);

    expect(first.launched, isTrue);
    expect(second.launched, isFalse);
    expect(second.workOrderId, first.workOrderId);
    final items = await database.select(database.aiWorkItems).get();
    await _waitFor(() => runner.requests.isNotEmpty);
    expect(
      (await database.select(database.aiWorkOrders).getSingle()).status,
      'running',
    );
    expect(items.single.subjectId, jobId);
    expect(items.single.status, 'running');
    expect(runner.requests, hasLength(1));
    expect(runner.requests.single.jobId, jobId);
    expect(
      runner.requests.single.prompt,
      contains('Work-order ID: `${first.workOrderId}`'),
    );
    expect(runner.requests.single.prompt, contains('careershopper_session'));
    expect(
      runner.requests.single.prompt,
      contains(jobEvaluationScoringInstructions),
    );
    expect(
      runner.requests.single.prompt,
      contains('Do not summarize, paraphrase, or omit sections.'),
    );
    await runner.requests.single.onSessionUpdate?.call({
      'update': {
        'sessionUpdate': 'session_info_update',
        'title':
            'Use the CareerShopper skill and this very long internal prompt',
      },
    }, false);
    final unchangedOrder = await database
        .select(database.aiWorkOrders)
        .getSingle();
    expect(unchangedOrder.title, 'Import jobs.example.test listing');
  });

  test(
    'interrupted listing work returns to the inbox and can be resumed',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final jobId = await jobs.queueManualUrl(
        Uri.parse('https://example.test/interrupt'),
      );
      final dispatch = await harnesses.dispatchManualImport(jobId);
      await _waitFor(() => runner.requests.isNotEmpty);
      await runner.requests.single.onSessionStarted!('import-session');
      await harnesses.interruptConversation(dispatch.workOrderId);
      final inbox = await jobs.watchInbox().first;
      expect(inbox.single.id, jobId);
      expect(inbox.single.aiError, contains('Interrupted by user'));
      await harnesses.sendMessage(
        dispatch.workOrderId,
        'Continue importing this job',
      );
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.existingSessionId, 'import-session');
      expect(
        (await database.select(database.aiWorkItems).getSingle()).status,
        'running',
      );
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (items) => items.single.status == 'failed',
      );
      expect(
        (await jobs.watchInbox().first).single.aiError,
        contains('without completing'),
      );
    },
  );

  for (final steer in [false, true]) {
    test(
      'active chat ${steer ? "steers" : "interrupts"} and preserves its session',
      () async {
        await harnesses.saveProfile(
          const AiHarnessProfileDraft(
            name: 'Test',
            executable: '/bin/true',
            arguments: [],
          ),
        );
        final id = await harnesses.startConversation(
          'Check the remote requirement',
        );
        await _waitFor(() => runner.requests.isNotEmpty);
        final first = runner.requests.single;
        await first.onSessionStarted!('saved-session');
        await first.onSessionUpdate!({
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Checking the listing.'},
          },
        }, false);
        if (steer) {
          await harnesses.sendMessage(id, 'Focus on the location requirement');
        } else {
          await harnesses.interruptConversation(id);
          expect(
            (await harnesses.watchConversations().first).single.status,
            'interrupted',
          );
          expect(
            (await harnesses.watchActivity(id).first).map((e) => e.kind),
            isNot(contains('error')),
          );
          await harnesses.sendMessage(id, 'Focus on the location requirement');
        }
        expect(first.control!.isCancelled, true);
        await _waitFor(() => runner.requests.length == 2);
        expect(runner.requests.last.existingSessionId, 'saved-session');
        expect(
          runner.requests.last.prompt,
          'Focus on the location requirement',
        );
        expect(
          (await harnesses.watchConversations().first).single.status,
          'running',
        );
        final entries = await harnesses.watchActivity(id).first;
        expect(entries.where((e) => e.kind == 'interrupted'), hasLength(1));
        expect(entries.map((e) => e.text), contains('Checking the listing.'));
        runner.complete(1);
        await harnesses.watchConversations().firstWhere(
          (items) => items.single.status == 'completed',
        );
      },
    );
  }

  test(
    'steering before a session starts retains the original question',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test',
          executable: '/bin/true',
          arguments: [],
        ),
      );
      final id = await harnesses.startConversation('Original question');
      await _waitFor(() => runner.requests.isNotEmpty);
      await harnesses.sendMessage(id, 'New direction');
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.existingSessionId, isNull);
      expect(runner.requests.last.prompt, contains('Original question'));
      expect(runner.requests.last.prompt, contains('New direction'));
      runner.complete(1);
      await harnesses.watchConversations().firstWhere(
        (items) => items.single.status == 'completed',
      );
    },
  );

  test(
    'interactive chat persists ACP activity and resumes its session',
    () async {
      await harnesses.saveProfile(
        const AiHarnessProfileDraft(
          name: 'Test harness',
          executable: '/bin/true',
          arguments: ['--acp'],
        ),
      );

      final conversationId = await harnesses.startConversation(
        'Review my career profile.',
      );
      await _waitFor(() => runner.requests.isNotEmpty);
      final firstRequest = runner.requests.single;
      await firstRequest.onSessionStarted?.call('session-123');
      await firstRequest.onSessionUpdate?.call({
        'sessionId': 'session-123',
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'Your profile is ready.'},
        },
      }, false);

      final activity = await harnesses.watchActivity(conversationId).first;
      expect(activity.map((entry) => entry.text), [
        'Review my career profile.',
        'Your profile is ready.',
      ]);

      runner.complete(0);
      await harnesses.watchConversations().firstWhere(
        (items) => items.single.status == 'completed',
      );
      await harnesses.sendMessage(conversationId, 'What should I add?');
      await _waitFor(() => runner.requests.length == 2);

      expect(runner.requests.last.existingSessionId, 'session-123');
      expect(runner.requests.last.scopedMcp, isFalse);
    },
  );
}

class _PendingAcpRunner implements AcpAgentRunner {
  final List<AcpRunRequest> requests = [];
  final List<Completer<void>> pending = [];

  @override
  Future<void> run(AcpRunRequest request) {
    requests.add(request);
    final completer = Completer<void>();
    pending.add(completer);
    unawaited(
      request.control?.whenCancelled.then((_) {
        if (!completer.isCompleted) {
          completer.completeError(const AcpRunCancelled());
        }
      }),
    );
    return completer.future;
  }

  void complete(int index) => pending[index].complete();
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}
