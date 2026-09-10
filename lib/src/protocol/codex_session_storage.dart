import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

bool isCodexAcpAdapter(String executable, List<String> arguments) {
  bool matches(String value) =>
      RegExp(
        r'^(?:@agentclientprotocol/)?codex-acp(?:@[^/]+|-(?:x64|arm64)-(?:linux|darwin|windows))?(?:\.exe)?$',
      ).hasMatch(value.replaceAll('\\', '/').split('/').last) ||
      RegExp(r'^@agentclientprotocol/codex-acp(?:@[^/]+)?$').hasMatch(value);
  return matches(executable) || arguments.any(matches);
}

/// Keeps Codex ACP history separate from the user's interactive Codex clients.
Future<Map<String, String>> codexSessionEnvironment({
  required String executable,
  required List<String> arguments,
  required Directory dataDirectory,
  required Map<String, String> environment,
  String? existingSessionId,
}) async {
  if (!isCodexAcpAdapter(executable, arguments)) {
    return environment;
  }
  final userHome = environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  final sourcePath =
      environment['CODEX_HOME'] ??
      (userHome == null ? null : p.join(userHome, '.codex'));
  final home = Directory(p.join(dataDirectory.absolute.path, 'codex-home'));
  await home.create(recursive: true);
  final source = sourcePath == null ? null : Directory(p.absolute(sourcePath));
  if (source != null && !p.equals(source.path, home.path)) {
    // Share the login cache, not config, memories, session indexes, or transcripts.
    // A link lets both clients see refreshed credentials without copying tokens.
    final auth = File(p.join(source.path, 'auth.json'));
    final target = Link(p.join(home.path, 'auth.json'));
    if (await auth.exists() &&
        await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
      try {
        await target.create(auth.path);
      } on FileSystemException {
        if (await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.notFound) {
          throw StateError(
            'Could not share the Codex login with CareerShopper. Sign in to Codex using CODEX_HOME=${home.path}, then retry.',
          );
        }
      }
    }
    if (existingSessionId != null) {
      await _copySession(source, home, existingSessionId);
    }
  }
  final configText = environment['CODEX_CONFIG'];
  final config = configText == null || configText.isEmpty
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(jsonDecode(configText) as Map);
  // Explicit settings take precedence over the SQLite environment override.
  config['sqlite_home'] = home.path;
  config['approval_policy'] = 'on-request';
  config['approvals_reviewer'] = 'user';
  if (config.containsKey('log_dir')) {
    config['log_dir'] = p.join(home.path, 'logs');
  }
  return {
    ...environment,
    'CODEX_HOME': home.path,
    'CODEX_SQLITE_HOME': home.path,
    'CODEX_CONFIG': jsonEncode(config),
    // The adapter otherwise defaults to "Approve for me" and overrides config
    // with approvalsReviewer=auto_review on every turn.
    'INITIAL_AGENT_MODE': 'read-only',
    if (environment.containsKey('APP_SERVER_LOGS'))
      'APP_SERVER_LOGS': p.join(home.path, 'logs'),
  };
}

Future<void> _copySession(Directory source, Directory home, String id) async {
  if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) return;
  Future<File?> find(Directory root) async {
    if (!await root.exists()) return null;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File && p.basename(entry.path).endsWith('-$id.jsonl')) {
        return entry;
      }
    }
    return null;
  }

  if (await find(Directory(p.join(home.path, 'sessions'))) != null ||
      await find(Directory(p.join(home.path, 'archived_sessions'))) != null) {
    return;
  }
  final original =
      await find(Directory(p.join(source.path, 'sessions'))) ??
      await find(Directory(p.join(source.path, 'archived_sessions')));
  if (original == null) return;
  final sourceRoot = p.isWithin(p.join(source.path, 'sessions'), original.path)
      ? p.join(source.path, 'sessions')
      : p.join(source.path, 'archived_sessions');
  final target = File(
    p.join(home.path, 'sessions', p.relative(original.path, from: sourceRoot)),
  );
  await target.parent.create(recursive: true);
  final temporary = await target.parent.createTemp('.import-');
  try {
    final copy = await original.copy(p.join(temporary.path, 'session.jsonl'));
    // copy() is used instead of a link so future turns cannot update the original.
    await copy.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}
