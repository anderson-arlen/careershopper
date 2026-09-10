import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/acp_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final ignoreCancel in [false, true]) {
    test(
      'ACP interruption sends a notification and stops (ignore: $ignoreCancel)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'acp-interrupt-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final helper = File(
          '${directory.path}/agent-plugin/bin/careershopper-agent',
        );
        await helper.parent.create(recursive: true);
        await helper.writeAsString('fixture');
        final log = File('${directory.path}/requests.jsonl');
        final started = Completer<void>();
        final control = AcpRunControl();
        final run = StdioAcpAgentRunner(dataDirectory: directory).run(
          AcpRunRequest(
            executable: 'dart',
            arguments: [
              File('test/fixtures/interruptible_acp_agent.dart').absolute.path,
              log.path,
              if (ignoreCancel) 'ignore-cancel',
            ],
            workOrderId: 'test',
            prompt: 'Work until interrupted',
            control: control,
            onSessionUpdate: (_, replaying) async {
              if (!started.isCompleted) started.complete();
            },
          ),
        );
        final stopped = expectLater(run, throwsA(isA<AcpRunCancelled>()));
        await started.future;
        control.cancel();
        await stopped.timeout(const Duration(seconds: 10));
        final requests = (await log.readAsLines()).map(
          (line) => jsonDecode(line) as Map,
        );
        final cancel = requests.singleWhere(
          (r) => r['method'] == 'session/cancel',
        );
        expect(cancel.containsKey('id'), false);
        expect(cancel['params'], {'sessionId': 'fixture-session'});
      },
    );
  }
}
