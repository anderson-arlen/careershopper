import 'dart:async';
import 'package:careershopper/src/protocol/acp_permission.dart';
import 'package:flutter_test/flutter_test.dart';

const params = <String, Object?>{
  'toolCall': {
    'title': 'Run command mentioning careershopper and job-123',
    'rawInput': {'command': 'touch /tmp/example'},
  },
  'options': [
    {'optionId': 'yes', 'kind': 'allow_once'},
    {'optionId': 'no', 'kind': 'reject_once'},
    {'optionId': 'always', 'kind': 'allow_always'},
  ],
};

void main() {
  test(
    'matching task text never authorizes without an explicit decision',
    () async {
      final chosen = Completer<String?>();
      var completed = false;
      final result =
          requestAcpPermission(
            params,
            cancelled: Completer<void>().future,
            prompt: (request, _) async {
              expect(
                (request['options'] as List).any(
                  (o) => o['kind'] == 'allow_always',
                ),
                true,
              );
              return chosen.future;
            },
          ).then((value) {
            completed = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      chosen.complete('yes');
      expect(await result, {
        'outcome': {'outcome': 'selected', 'optionId': 'yes'},
      });
    },
  );
  for (final choice in ['no', 'made-up', null]) {
    test('denial or invalid choice cannot grant access ($choice)', () async {
      expect(
        await requestAcpPermission(
          params,
          cancelled: Completer<void>().future,
          prompt: (_, _) async => choice,
        ),
        choice == 'no'
            ? {
                'outcome': {'outcome': 'selected', 'optionId': 'no'},
              }
            : acpPermissionCancelled,
      );
    });
  }
  test(
    'an explicit always choice returns the exact agent option without an automatic grant',
    () async {
      expect(
        await requestAcpPermission(
          params,
          cancelled: Completer<void>().future,
          prompt: (_, _) async => 'always',
        ),
        {
          'outcome': {'outcome': 'selected', 'optionId': 'always'},
        },
      );
    },
  );
  test('a cancelled request never opens a prompt', () async {
    final stopped = Completer<void>()..complete();
    var prompts = 0;
    expect(
      await requestAcpPermission(
        params,
        cancelled: stopped.future,
        prompt: (_, _) async {
          prompts++;
          return 'yes';
        },
      ),
      acpPermissionCancelled,
    );
    expect(prompts, 0);
  });
  test('ambiguous option IDs cannot turn a denial into approval', () async {
    expect(
      await requestAcpPermission(
        {
          ...params,
          'options': [
            {'kind': 'allow_once', 'optionId': 'same'},
            {'kind': 'reject_once', 'optionId': 'same'},
          ],
        },
        cancelled: Completer<void>().future,
        prompt: (_, _) async => 'same',
      ),
      acpPermissionCancelled,
    );
  });
  test('headless requests fail closed', () async {
    await expectLater(
      requestAcpPermission(
        params,
        cancelled: Completer<void>().future,
        prompt: null,
      ),
      throwsStateError,
    );
  });
  test('interruption cancels a pending decision', () async {
    final stop = Completer<void>();
    final choice = Completer<String?>();
    final result = requestAcpPermission(
      params,
      cancelled: stop.future,
      prompt: (_, _) => choice.future,
    );
    stop.complete();
    expect(await result, acpPermissionCancelled);
    choice.complete('yes');
  });
}
