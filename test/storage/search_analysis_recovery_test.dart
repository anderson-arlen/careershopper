import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late AiHarnessRepository harness;
  late _Runner runner;
  late List<String> jobs;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = CareerShopperDatabase(NativeDatabase.memory());
    runner = _Runner();
    harness = AiHarnessRepository(database, runner: runner);
    await harness.saveProfile(
      const AiHarnessProfileDraft(
        name: 'Test',
        executable: '/bin/true',
        arguments: [],
      ),
    );
    final now = DateTime.now().toUtc();
    await database
        .into(database.savedSearches)
        .insert(
          SavedSearchesCompanion.insert(
            id: 'engineering',
            name: 'Remote engineering',
            queryJson: '{}',
            createdAt: now,
            updatedAt: now,
          ),
        );
    jobs = [];
    for (var i = 0; i < 3; i++) {
      jobs.add(
        await JobRepository(
          database,
        ).queueManualUrl(Uri.parse('https://example.test/search/$i')),
      );
    }
  });
  tearDown(() async {
    await database.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  for (final checkpoint in [
    'before_first',
    'during_second',
    'after_second_saved',
  ]) {
    test('saved search resumes after reopening at $checkpoint', () async {
      expect(
        await harness.dispatchSearchAnalysis(
          jobs,
          savedSearchId: 'engineering',
        ),
        3,
      );
      await _waitFor(() => runner.requests.length == 1);
      final order = await database.select(database.aiWorkOrders).getSingle();
      expect(order.title, 'Evaluate search: Remote engineering');
      expect(
        await harness.dispatchSearchAnalysis(
          jobs,
          savedSearchId: 'engineering',
        ),
        0,
      );
      if (checkpoint != 'before_first') {
        await _evaluate(database, runner.requests.first);
        runner.complete(0);
        await _waitFor(() => runner.requests.length == 2);
        expect(runner.requests.last.existingSessionId, 'search-session');
      } else {
        await database.customStatement(
          "UPDATE ai_work_orders SET status = 'queued', acp_session_id = NULL",
        );
        await database.customStatement(
          "UPDATE ai_work_items SET status = 'queued'",
        );
      }
      if (checkpoint == 'after_second_saved') {
        await _evaluate(database, runner.requests.last);
        // Simulate an older helper that saved the result before item completion.
        await database.customStatement(
          "UPDATE ai_work_items SET status = 'running' WHERE subject_id = ?",
          [runner.requests.last.jobId],
        );
      }
      final expected = checkpoint == 'before_first'
          ? jobs
          : checkpoint == 'during_second'
          ? jobs.skip(1).toList()
          : [jobs.last];
      final directory = await Directory.systemTemp.createTemp(
        'careershopper-search-reopen-',
      );
      final file = File('${directory.path}/saved.sqlite');
      await database.customStatement(
        "UPDATE ai_work_orders SET leased_until = 1",
      );
      await database.customStatement(
        'UPDATE ai_harness_profiles SET config_values_json = ?',
        [
          jsonEncode({'engine': 'different-default'}),
        ],
      );
      await database.customStatement('VACUUM INTO ?', [file.path]);
      // The copied database captures an abrupt exit, independent of cleanup here.
      await harness.interruptConversation(order.id);
      final reopened = CareerShopperDatabase(NativeDatabase(file));
      final nextRunner = _Runner();
      final nextHarness = AiHarnessRepository(reopened, runner: nextRunner);
      try {
        expect(await nextHarness.resumePendingSearchAnalysis(), 1);
        await _waitFor(() => nextRunner.requests.length == 1);
        expect(await nextHarness.resumePendingSearchAnalysis(), 0);
        expect(await nextHarness.recoverExpiredWork(), 0);
        expect(
          nextRunner.requests.first.existingSessionId,
          checkpoint == 'before_first' ? isNull : 'search-session',
        );
        expect(nextRunner.requests.first.workOrderId, order.id);
        expect(
          nextRunner.requests.first.configValues,
          isEmpty,
          reason:
              'Resume retains this conversation settings, not changed agent defaults.',
        );
        for (var i = 0; i < expected.length; i++) {
          await _waitFor(() => nextRunner.requests.length == i + 1);
          expect(nextRunner.requests[i].jobId, expected[i]);
          await _evaluate(reopened, nextRunner.requests[i]);
          expect(
            (await reopened.select(reopened.aiWorkOrders).getSingle()).status,
            'running',
          );
          nextRunner.complete(i);
        }
        await nextHarness.watchConversations().firstWhere(
          (rows) => rows.single.status == 'completed',
        );
        expect(
          await reopened.select(reopened.jobEvaluations).get(),
          hasLength(3),
        );
        expect(
          (await reopened.select(reopened.aiWorkItems).get()).map(
            (i) => i.status,
          ),
          everyElement('completed'),
        );
        final read = await _call(reopened, 'ai_conversation_get', {
          'conversation_id': order.id,
        });
        final content = (read['result'] as Map)['structuredContent'] as Map;
        expect(content['title'], 'Evaluate search: Remote engineering');
        expect(content['work_items'], hasLength(3));
        expect(await nextHarness.resumePendingSearchAnalysis(), 0);
      } finally {
        await reopened.close();
        await directory.delete(recursive: true);
      }
    });
  }

  test(
    'explicit stop stays paused; continue resumes the same search without losing completed jobs',
    () async {
      await harness.dispatchSearchAnalysis(jobs, savedSearchId: 'engineering');
      await _waitFor(() => runner.requests.length == 1);
      final id = runner.requests.first.workOrderId;
      await _evaluate(database, runner.requests.first);
      runner.complete(0);
      await _waitFor(() => runner.requests.length == 2);
      await harness.interruptConversation(id);
      expect(
        (await database.select(database.aiWorkOrders).getSingle()).status,
        'interrupted',
      );
      expect(await harness.resumePendingSearchAnalysis(), 0);
      await harness.sendMessage(id, 'Continue the search');
      await _waitFor(() => runner.requests.length == 3);
      expect(runner.requests.last.workOrderId, id);
      expect(runner.requests.last.jobId, jobs[1]);
      expect(runner.requests.last.existingSessionId, 'search-session');
      expect(
        runner.requests.last.resumedPrompt,
        contains('Continue the search'),
      );
      await _evaluate(database, runner.requests.last);
      runner.complete(2);
      await _waitFor(() => runner.requests.length == 4);
      await _evaluate(database, runner.requests.last);
      runner.complete(3);
      await harness.watchConversations().firstWhere(
        (rows) => rows.single.status == 'completed',
      );
      expect(
        await database.select(database.jobEvaluations).get(),
        hasLength(3),
      );
    },
  );

  test(
    'harness failure retains pending work until explicitly continued',
    () async {
      await harness.dispatchSearchAnalysis(jobs, savedSearchId: 'engineering');
      await _waitFor(() => runner.requests.length == 1);
      final id = runner.requests.first.workOrderId;
      runner.pending.first.completeError(StateError('Harness disconnected'));
      await harness.watchConversations().firstWhere(
        (rows) => rows.single.status == 'failed',
      );
      expect(runner.requests, hasLength(1));
      expect(
        (await database.select(database.aiWorkItems).get()).map(
          (i) => i.status,
        ),
        everyElement('queued'),
      );
      expect(await harness.resumePendingSearchAnalysis(), 0);
      await harness.sendMessage(id, 'Continue after reconnecting');
      await _waitFor(() => runner.requests.length == 2);
      expect(runner.requests.last.jobId, runner.requests.first.jobId);
      expect(runner.requests.last.existingSessionId, 'search-session');
      await harness.interruptConversation(id);
    },
  );

  test('stopping a queued search prevents its automatic start', () async {
    await harness.dispatchSearchAnalysis([
      jobs.first,
    ], savedSearchId: 'engineering');
    await _waitFor(() => runner.requests.length == 1);
    await harness.dispatchSearchAnalysis(
      jobs.skip(1).toList(),
      savedSearchId: 'engineering',
    );
    final orders = await database.select(database.aiWorkOrders).get();
    final queued = orders.singleWhere((o) => o.status == 'queued');
    await harness.interruptConversation(queued.id);
    await _evaluate(database, runner.requests.first);
    runner.complete(0);
    await harness.watchConversations().firstWhere(
      (rows) => rows.every((r) => r.status != 'running'),
    );
    expect(await harness.resumePendingSearchAnalysis(), 0);
    expect(runner.requests, hasLength(1));
    expect(
      (await database.select(database.aiWorkOrders).get())
          .singleWhere((o) => o.id == queued.id)
          .status,
      'interrupted',
    );
  });

  test(
    'only the current assignment can be evaluated, once, and failed jobs do not stop the queue',
    () async {
      await harness.dispatchSearchAnalysis(jobs, savedSearchId: 'engineering');
      await _waitFor(() => runner.requests.length == 1);
      final first = runner.requests.first;
      final outside = await _call(
        database,
        'job_evaluation_submit',
        _evaluation(jobs.last),
        orderId: first.workOrderId,
      );
      expect(outside, contains('error'));
      runner.complete(0); // Missing evaluation fails this item only.
      await _waitFor(() => runner.requests.length == 2);
      await _evaluate(database, runner.requests.last);
      final duplicate = await _call(
        database,
        'job_evaluation_submit',
        _evaluation(jobs[1]),
        orderId: first.workOrderId,
      );
      expect(duplicate, contains('error'));
      runner.complete(1);
      await _waitFor(() => runner.requests.length == 3);
      await _evaluate(database, runner.requests.last);
      runner.complete(2);
      await harness.watchConversations().firstWhere(
        (rows) => rows.single.status == 'failed',
      );
      expect(
        await database.select(database.jobEvaluations).get(),
        hasLength(2),
      );
      expect(await harness.resumePendingSearchAnalysis(), 0);
    },
  );
}

Map<String, Object?> _evaluation(String jobId) => {
  'job_id': jobId,
  'personal_fit_score': 80,
  'attainability_score': 75,
  'confidence': 0.5,
  'summary': 'Synthetic evaluation for recovery testing.',
};
Future<void> _evaluate(CareerShopperDatabase db, AcpRunRequest request) async {
  final response = await _call(
    db,
    'job_evaluation_submit',
    _evaluation(request.jobId!),
    orderId: request.workOrderId,
  );
  expect(response, isNot(contains('error')));
  expect((response['result'] as Map)['isError'], false);
}

Future<Map> _call(
  CareerShopperDatabase db,
  String tool,
  Map<String, Object?> args, {
  String? orderId,
}) async {
  final controller = StreamController<List<int>>();
  final output = IOSink(controller.sink);
  final result = controller.stream.transform(utf8.decoder).join();
  await McpServer(db, workOrderId: orderId).serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {'name': tool, 'arguments': args},
        })}\n',
      ),
    ),
    output: output,
  );
  await output.close();
  return jsonDecode(await result) as Map;
}

class _Runner implements AcpAgentRunner {
  final requests = <AcpRunRequest>[];
  final pending = <Completer<void>>[];
  @override
  Future<void> run(AcpRunRequest request) async {
    await request.onSessionStarted?.call(
      request.existingSessionId ?? 'search-session',
    );
    requests.add(request);
    final done = Completer<void>();
    pending.add(done);
    await Future.any([
      done.future,
      if (request.control != null)
        request.control!.whenCancelled.then(
          (_) => throw const AcpRunCancelled(),
        ),
    ]);
  }

  void complete(int index) => pending[index].complete();
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var i = 0; i < 200 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(predicate(), true);
}
