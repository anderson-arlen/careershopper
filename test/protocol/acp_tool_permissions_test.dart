import 'dart:async';
import 'dart:io';
import 'package:careershopper/src/protocol/acp_tool_permissions.dart';
import 'package:careershopper/src/protocol/acp_permission.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> request({
  String session = 'one',
  String tool = 'application_materials_submit',
  String server = 'careershopper_session',
  bool mcp = true,
}) => {
  'sessionId': session,
  'toolCall': {
    'title': 'mcp.careershopper_session.application_materials_submit',
    '_meta': {'is_mcp_tool_call': mcp},
    'rawInput': {
      'server': server,
      'tool': tool,
      'arguments': {'draft': session},
    },
  },
  'options': [
    {'kind': 'allow_once', 'optionId': 'allow_once'},
    {'kind': 'allow_always', 'optionId': 'allow_session'},
    {'kind': 'allow_always', 'optionId': 'allow_always'},
    {'kind': 'reject_once', 'optionId': 'cancel'},
  ],
};
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tool-grants-test-');
  });
  tearDown(() => dir.delete(recursive: true));
  AcpToolPermissions store([String endpoint = 'local-helper']) =>
      AcpToolPermissions(dir, [endpoint]);
  Future<Map<String, Object?>> resolve(
    AcpToolPermissions s,
    Map<String, Object?> r,
    String choice,
    void Function() prompt,
  ) => s.resolve(
    r,
    prompt: (_, _) async {
      prompt();
      return choice;
    },
    cancelled: Completer<void>().future,
    onRemembered: () {},
  );

  for (final scope in [
    'allow_always',
    'allow_session',
    'allow_once',
    'cancel',
  ]) {
    test('$scope preserves exactly the selected lifetime', () async {
      var prompts = 0;
      void count() {
        prompts++;
      }

      await resolve(store(), request(), scope, count);
      await resolve(store(), request(), 'allow_once', count);
      expect(
        prompts,
        scope == 'allow_always' || scope == 'allow_session' ? 1 : 2,
      );
      await resolve(store(), request(session: 'two'), 'allow_once', count);
      expect(
        prompts,
        scope == 'allow_always'
            ? 1
            : scope == 'allow_session'
            ? 2
            : 3,
      );
    });
  }
  test(
    'tool, endpoint and server boundaries survive changing arguments',
    () async {
      var prompts = 0;
      void count() {
        prompts++;
      }

      await resolve(store(), request(), 'allow_always', count);
      await resolve(
        store(),
        request(session: 'different-draft'),
        'allow_once',
        count,
      );
      expect(prompts, 1);
      await resolve(
        store(),
        request(tool: 'application_apply'),
        'allow_once',
        count,
      );
      await resolve(store('different-helper'), request(), 'allow_once', count);
      await resolve(
        store(),
        request(server: 'other-server'),
        'allow_once',
        count,
      );
      await resolve(store(), request(mcp: false), 'allow_once', count);
      expect(prompts, 5);
    },
  );
  test('cancelled requests cannot consume or create a grant', () async {
    final stopped = Completer<void>()..complete();
    var prompts = 0;
    final result = await store().resolve(
      request(),
      prompt: (_, _) async {
        prompts++;
        return 'allow_always';
      },
      cancelled: stopped.future,
      onRemembered: () {},
    );
    expect(result, acpPermissionCancelled);
    expect(prompts, 0);
    expect(await dir.list().toList(), isEmpty);
  });
}
