import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/codex_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;
  late Directory data;
  late Map<String, String> environment;
  const sessionId = '01a088b7-4905-7373-ab57-8faa1af0e703';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('codex-storage-test-');
    source = await Directory(p.join(root.path, 'personal')).create();
    data = await Directory(p.join(root.path, 'careershopper')).create();
    environment = {
      'CODEX_HOME': source.path,
      'CODEX_SQLITE_HOME': source.path,
      'INITIAL_AGENT_MODE': 'agent',
      'CODEX_CONFIG': jsonEncode({
        'sqlite_home': source.path,
        'model': 'saved-model',
        'approval_policy': 'never',
        'approvals_reviewer': 'auto_review',
      }),
      'PATH': '/test/path',
    };
    await File(p.join(source.path, 'auth.json')).writeAsString('fixture-login');
    await File(
      p.join(source.path, 'config.toml'),
    ).writeAsString('personal-config');
    await File(
      p.join(source.path, 'session_index.jsonl'),
    ).writeAsString('personal-index');
  });
  tearDown(() => root.delete(recursive: true));

  Future<Map<String, String>> prepare({
    String? session,
    String executable = 'npx',
    List<String> arguments = const [
      '-y',
      '@agentclientprotocol/codex-acp@1.9.0',
    ],
  }) => codexSessionEnvironment(
    executable: executable,
    arguments: arguments,
    dataDirectory: data,
    environment: environment,
    existingSessionId: session,
  );

  test(
    'Codex state and SQLite index are isolated while login is shared',
    () async {
      final result = await prepare();
      final home = p.join(data.path, 'codex-home');
      expect(result['CODEX_HOME'], home);
      expect(result['CODEX_SQLITE_HOME'], home);
      expect(jsonDecode(result['CODEX_CONFIG']!)['sqlite_home'], home);
      expect(jsonDecode(result['CODEX_CONFIG']!)['model'], 'saved-model');
      expect(result['INITIAL_AGENT_MODE'], 'read-only');
      expect(
        jsonDecode(result['CODEX_CONFIG']!)['approval_policy'],
        'on-request',
      );
      expect(jsonDecode(result['CODEX_CONFIG']!)['approvals_reviewer'], 'user');
      expect(result['PATH'], environment['PATH']);
      expect(environment['CODEX_HOME'], source.path);
      expect(
        await Link(p.join(home, 'auth.json')).target(),
        p.join(source.path, 'auth.json'),
      );
      await File(
        p.join(source.path, 'auth.json'),
      ).writeAsString('refreshed-fixture-login');
      expect(
        await File(p.join(home, 'auth.json')).readAsString(),
        'refreshed-fixture-login',
      );
      expect(await File(p.join(home, 'config.toml')).exists(), false);
      expect(await File(p.join(home, 'session_index.jsonl')).exists(), false);
      expect(await prepare(), result);
    },
    skip: Platform.isWindows
        ? 'Symbolic links require Windows developer mode'
        : false,
  );

  for (final folder in ['sessions', 'archived_sessions']) {
    test(
      'resume copies only the requested $folder transcript and leaves originals alone',
      () async {
        final relative = p.join(
          '2026',
          '09',
          '09',
          'rollout-2026-09-09T18-28-28-$sessionId.jsonl',
        );
        final original = File(p.join(source.path, folder, relative));
        await original.parent.create(recursive: true);
        await original.writeAsString('old-context');
        await File(
          p.join(original.parent.path, 'unrelated.jsonl'),
        ).writeAsString('unrelated');
        final result = await prepare(session: sessionId);
        final copied = File(
          p.join(result['CODEX_HOME']!, 'sessions', relative),
        );
        expect(await copied.readAsString(), 'old-context');
        await copied.writeAsString('continued-in-careershopper');
        await prepare(session: sessionId);
        expect(await copied.readAsString(), 'continued-in-careershopper');
        expect(await original.readAsString(), 'old-context');
        expect(
          await File(p.join(copied.parent.path, 'unrelated.jsonl')).exists(),
          false,
        );
        expect(
          await File(p.join(source.path, 'session_index.jsonl')).readAsString(),
          'personal-index',
        );
      },
      skip: Platform.isWindows
          ? 'Symbolic links require Windows developer mode'
          : false,
    );
  }

  test('other ACP agents keep their existing environment', () async {
    expect(
      await prepare(executable: 'claude-agent-acp', arguments: []),
      environment,
    );
    expect(await Directory(p.join(data.path, 'codex-home')).exists(), false);
  });

  test(
    'direct and npm Codex adapters receive isolated storage without a file login',
    () async {
      await File(p.join(source.path, 'auth.json')).delete();
      for (final command in [
        'codex-acp',
        '/bin/codex-acp',
        'codex-acp-x64-linux',
        r'C:\bin\codex-acp.exe',
      ]) {
        expect(
          (await prepare(executable: command, arguments: []))['CODEX_HOME'],
          p.join(data.path, 'codex-home'),
        );
      }
    },
  );
}
