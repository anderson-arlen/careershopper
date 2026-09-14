import 'dart:io';
import 'dart:async';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'interview updates detect commits from a separate MCP connection',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'careershopper-external-test-',
      );
      final file = File('${dir.path}/db.sqlite3');
      final db = CareerShopperDatabase(NativeDatabase(file));
      final external = CareerShopperDatabase(NativeDatabase(file));
      StreamIterator<void>? events;
      try {
        final id = await JobRepository(
          db,
        ).queueManualUrl(Uri.parse('https://example.test/external'));
        final repo = InterviewRepository(db);
        await repo.ensure(id);
        events = StreamIterator(repo.watchPreparationChanges(id));
        expect(await events.moveNext(), true);
        await external.customStatement(
          "UPDATE interview_workspaces SET preparation_state = 'ready' WHERE job_id = ?",
          [id],
        );
        expect(
          await events.moveNext().timeout(const Duration(seconds: 6)),
          true,
        );
        expect((await repo.summary(id))['preparation_state'], 'ready');
      } finally {
        await events?.cancel();
        await external.close();
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('v18 upgrade adds read indexes and preserves retained jobs', () async {
    final dir = await Directory.systemTemp.createTemp(
      'careershopper-index-test-',
    );
    final file = File('${dir.path}/db.sqlite3');
    var db = CareerShopperDatabase(NativeDatabase(file));
    try {
      final id = await JobRepository(
        db,
      ).queueManualUrl(Uri.parse('https://example.test/retained'));
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND sql LIKE 'CREATE INDEX%'",
          )
          .get();
      for (final index in indexes) {
        await db.customStatement('DROP INDEX "${index.read<String>('name')}"');
      }
      await db.customStatement('PRAGMA user_version = 18');
      await db.close();
      db = CareerShopperDatabase(NativeDatabase(file));
      expect((await JobRepository(db).getJob(id))!.id, id);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        19,
      );
      for (final query in [
        "SELECT * FROM job_observations WHERE job_id='job' ORDER BY observed_at,rowid LIMIT 1",
        "SELECT * FROM ai_work_orders WHERE job_id='job' AND kind='interview_preparation' ORDER BY created_at DESC,id DESC LIMIT 1",
        "SELECT * FROM ai_work_items WHERE work_order_id='work'",
        "SELECT * FROM ai_activity_entries WHERE work_order_id='work' ORDER BY sequence,id",
        "SELECT * FROM interview_revisions WHERE job_id='job' ORDER BY created_at DESC,id DESC",
      ]) {
        final plan = (await db.customSelect('EXPLAIN QUERY PLAN $query').get())
            .map((r) => r.read<String>('detail'))
            .join('\n');
        expect(plan, contains('SEARCH'), reason: query);
        expect(plan, isNot(contains('SCAN ')), reason: query);
        expect(plan, isNot(contains('TEMP B-TREE')), reason: query);
      }
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'conversation and transcript pages retain ordering and MCP totals',
    () async {
      final db = CareerShopperDatabase(NativeDatabase.memory());
      final harness = AiHarnessRepository(db);
      try {
        final now = DateTime.utc(2026);
        for (var i = 0; i < 5; i++) {
          await db
              .into(db.aiWorkOrders)
              .insert(
                AiWorkOrdersCompanion.insert(
                  id: 'conversation-$i',
                  kind: 'chat',
                  status: 'completed',
                  scopeJson: '{}',
                  promptVersion: 'test',
                  createdAt: now,
                  updatedAt: now.add(Duration(seconds: i)),
                ),
              );
        }
        for (var i = 0; i < 12; i++) {
          await db
              .into(db.aiActivityEntries)
              .insert(
                AiActivityEntriesCompanion.insert(
                  id: 'message-$i',
                  workOrderId: 'conversation-0',
                  role: 'assistant',
                  kind: 'message',
                  sequence: i,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        expect(
          (await harness.watchConversations(limit: 2, offset: 2).first).map(
            (r) => r.id,
          ),
          ['conversation-2', 'conversation-1'],
        );
        expect(
          (await harness
                  .watchActivity('conversation-0', limit: 3, offset: 4)
                  .first)
              .map((r) => r.sequence),
          [4, 5, 6],
        );
        expect(
          (await harness
                  .watchActivity('conversation-0', limit: 3, latest: true)
                  .first)
              .map((r) => r.sequence),
          [9, 10, 11],
        );
        final tools = McpUiTools(db);
        final list = await tools.call('ai_conversations_list', {
          'limit': 2,
          'offset': 2,
        });
        expect((list['conversations'] as List).length, 2);
        expect(list['next_offset'], 4);
        final transcript = await tools.call('ai_conversation_get', {
          'conversation_id': 'conversation-0',
          'limit': 3,
          'offset': 4,
        });
        expect(transcript['total'], 12);
        expect(transcript['next_offset'], 7);
        expect(
          (transcript['activity'] as List).map((r) => (r as Map)['sequence']),
          [4, 5, 6],
        );
      } finally {
        await db.close();
      }
    },
  );
}
