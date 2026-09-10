import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:drift/drift.dart';

// Explicit recovery of a known bad search analysis, without touching newer work.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply the search work-order ID.');
  final database = CareerShopperDatabase.openDefault();
  Completer<String?>? approval;
  final input = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final pending = approval;
        if (pending != null && !pending.isCompleted) {
          pending.complete(line.trim());
        }
      });
  final harness = AiHarnessRepository(
    database,
    runner: StdioAcpAgentRunner(
      permissionPrompt: (params, cancelled) async {
        final pending = Completer<String?>();
        approval = pending;
        stdout.writeln(jsonEncode({'approval_required': params}));
        unawaited(
          cancelled.then((_) {
            if (!pending.isCompleted) pending.complete(null);
          }),
        );
        final choice = await pending.future;
        approval = null;
        return choice;
      },
    ),
  );
  try {
    final batch = await (database.select(
      database.aiWorkOrders,
    )..where((r) => r.id.equals(args.single))).getSingle();
    if (batch.kind != 'search_analysis') {
      throw ArgumentError('Expected a search analysis work order.');
    }
    final ids = (jsonDecode(batch.scopeJson)['job_ids'] as List).cast<String>();
    var completed = 0;
    var skipped = 0;
    var failed = 0;
    for (final id in ids) {
      final eligible = await database
          .customSelect(
            '''
SELECT j.id FROM jobs j
JOIN job_evaluations e ON e.id = j.current_evaluation_id
LEFT JOIN employers employer ON employer.id = j.employer_id
WHERE j.id = ? AND e.work_order_id = ?
AND j.review_state IN ('pending_evaluation', 'inbox', 'hidden_low_score', 'hidden_by_search')
AND j.availability != 'closed' AND employer.blocked_at IS NULL
AND NOT EXISTS (SELECT 1 FROM applications a WHERE a.job_id = j.id
  AND (a.status NOT IN ('not_applied', 'ready_to_apply') OR a.outcome != 'active'))
''',
            variables: [Variable(id), Variable(args.single)],
          )
          .get();
      if (eligible.isEmpty) {
        skipped++;
        stdout.writeln('SKIP $id: newer evaluation or changed eligibility');
        continue;
      }
      final dispatch = await harness.dispatchManualImport(id);
      if (!dispatch.launched) {
        skipped++;
        stdout.writeln('SKIP $id: already running');
        continue;
      }
      stdout.writeln('START $id ${dispatch.workOrderId}');
      final activity = await harness
          .watchActivity(dispatch.workOrderId)
          .firstWhere((rows) => rows.any((row) => row.kind == 'run_summary'));
      final summary = activity.lastWhere((row) => row.kind == 'run_summary');
      if (summary.details['status'] == 'completed') {
        completed++;
      } else {
        failed++;
      }
      stdout.writeln('${summary.details['status']} $id: ${summary.text}');
    }
    stdout.writeln(
      'FINISHED: $completed reevaluated; $skipped preserved/skipped; $failed failed.',
    );
    if (failed > 0) exitCode = 1;
  } finally {
    await input.cancel();
    await database.close();
  }
}
