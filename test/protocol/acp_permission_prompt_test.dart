import 'dart:async';
import 'package:careershopper/src/features/ai/acp_permission_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> request(String title) => {
  'conversationTitle': title,
  'toolCall': {
    'title': 'Read listing to prepare the application',
    'rawInput': {'url': 'https://employer.test/jobs/123'},
  },
  'options': <dynamic>[
    {'optionId': 'allow', 'kind': 'allow_once'},
    {'optionId': 'deny', 'kind': 'reject_once'},
  ],
};
void main() {
  testWidgets(
    'restores the window before presenting scheduled agent approval',
    (tester) async {
      var restored = false;
      final prompter = AcpPermissionPrompter(
        onPrompt: () async {
          restored = true;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(),
        ),
      );
      final cancelled = Completer<void>();
      final result = prompter.request(
        request('Scheduled search'),
        cancelled.future,
      );
      await tester.pumpAndSettle();
      expect(restored, isTrue);
      expect(find.text('Agent approval required'), findsOneWidget);
      cancelled.complete();
      await tester.pumpAndSettle();
      expect(await result, isNull);
    },
  );

  for (final selection in ['allow_session', 'allow_always']) {
    testWidgets(
      'session and persistent choices retain distinct labels and exact responses ($selection)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final prompter = AcpPermissionPrompter();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: prompter.navigatorKey,
            home: const Scaffold(),
          ),
        );
        final value = request('Writer');
        value['toolCall'] = {
          'title': 'Save drafts',
          'rawInput': {
            'resume': List.filled(200, 'Long generated content.').join('\n'),
          },
        };
        (value['options'] as List).addAll([
          {
            'optionId': 'allow_session',
            'name': 'Allow for this session',
            'kind': 'allow_always',
            '_meta': {
              'permission': {
                'version': 1,
                'description': 'Remember this choice for this session.',
              },
            },
          },
          {
            'optionId': 'allow_always',
            'name': 'Always allow',
            'kind': 'allow_always',
            '_meta': {
              'permission': {
                'version': 1,
                'description': 'Remember this choice for future tool calls.',
              },
            },
          },
        ]);
        final done = prompter.request(value, Completer<void>().future);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(OutlinedButton, 'Allow for this session'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Always allow'),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(
                find.textContaining('Remember this choice for this session.'),
              )
              .dy,
          lessThan(tester.getTopLeft(find.text('Arguments')).dy),
        );
        await tester.tap(
          find.widgetWithText(
            OutlinedButton,
            selection == 'allow_session'
                ? 'Allow for this session'
                : 'Always allow',
          ),
        );
        await tester.pumpAndSettle();
        expect(await done, selection);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'identical agent labels remain distinguishable without inventing scopes',
    (tester) async {
      final prompter = AcpPermissionPrompter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(),
        ),
      );
      final value = request('Writer');
      (value['options'] as List).addAll([
        {'optionId': 'first', 'kind': 'allow_always', 'name': 'Always allow'},
        {'optionId': 'second', 'kind': 'allow_always', 'name': 'Always allow'},
      ]);
      final done = prompter.request(value, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Always allow (first)'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Always allow (second)'),
      );
      await tester.pumpAndSettle();
      expect(await done, 'second');
    },
  );

  testWidgets(
    'shows the exact MCP action and exposes the offered always permission',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prompter = AcpPermissionPrompter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(),
        ),
      );
      final value = request('Writer: Software Developer');
      value['workingDirectory'] = '/tmp/careershopper-work';
      value['toolCall'] = {
        'title': 'mcp.careershopper_session.application_materials_submit',
        'toolCallId': 'exec-example',
        'kind': 'execute',
        'rawInput': {
          'job_id': 'job-123',
          'cover_letter_markdown': 'The complete draft',
        },
      };
      (value['options'] as List).add({
        'optionId': 'allow-session',
        'kind': 'allow_always',
        'name': 'Allow this tool for this session',
      });
      final done = prompter.request(value, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(
        find.text('mcp.careershopper_session.application_materials_submit'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not submit an application to the employer'),
        findsOneWidget,
      );
      expect(find.textContaining('job-123'), findsOneWidget);
      expect(find.text('/tmp/careershopper-work'), findsOneWidget);
      expect(
        find.textContaining('Allow this tool for this session:'),
        findsOneWidget,
      );
      expect(find.textContaining('exec-example'), findsNothing);
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Allow this tool for this session'),
      );
      await tester.pumpAndSettle();
      expect(await done, 'allow-session');
    },
  );

  testWidgets(
    'a request with only opaque metadata cannot be approved blindly',
    (tester) async {
      final prompter = AcpPermissionPrompter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(),
        ),
      );
      final value = request('Writer');
      value['toolCall'] = {
        'toolCallId': 'exec-opaque',
        'kind': 'execute',
        'status': 'pending',
      };
      (value['options'] as List).add({
        'optionId': 'always',
        'kind': 'allow_always',
      });
      final done = prompter.request(value, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(find.text('Action details unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Allow once'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Always allow'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(await done, 'deny');
    },
  );

  testWidgets(
    'background approval overlays the current view with job and action context',
    (tester) async {
      final prompter = AcpPermissionPrompter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(body: Text('Statistics page')),
        ),
      );
      final done = prompter.request(
        request('Writer: Engineer at Pearson'),
        Completer<void>().future,
      );
      await tester.pumpAndSettle();
      expect(find.text('Statistics page'), findsOneWidget);
      expect(find.text('Agent approval required'), findsOneWidget);
      expect(find.text('Writer: Engineer at Pearson'), findsOneWidget);
      expect(
        find.textContaining('https://employer.test/jobs/123'),
        findsOneWidget,
      );
      await tester.tap(find.text('Allow once'));
      await tester.pumpAndSettle();
      expect(await done, 'allow');
      expect(find.text('Statistics page'), findsOneWidget);
    },
  );
  testWidgets(
    'concurrent approvals queue and cancelled work closes only its prompt',
    (tester) async {
      final prompter = AcpPermissionPrompter();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: prompter.navigatorKey,
          home: const Scaffold(body: Text('Inbox')),
        ),
      );
      final stopFirst = Completer<void>();
      final stopSecond = Completer<void>();
      final first = prompter.request(request('First job'), stopFirst.future);
      final second = prompter.request(request('Second job'), stopSecond.future);
      await tester.pumpAndSettle();
      expect(find.text('First job'), findsOneWidget);
      expect(find.text('Second job'), findsNothing);
      stopFirst.complete();
      await tester.pumpAndSettle();
      expect(await first, isNull);
      expect(find.text('Second job'), findsOneWidget);
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(await second, 'deny');
      expect(find.text('Agent approval required'), findsNothing);
    },
  );
  testWidgets('a queued cancelled request never appears or grants access', (
    tester,
  ) async {
    final prompter = AcpPermissionPrompter();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: prompter.navigatorKey, home: const Scaffold()),
    );
    final stop = Completer<void>();
    final first = prompter.request(request('First'), Completer<void>().future);
    final second = prompter.request(request('Cancelled'), stop.future);
    await tester.pumpAndSettle();
    stop.complete();
    await tester.pumpAndSettle();
    expect(await second, isNull);
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect(await first, 'deny');
    expect(find.text('Cancelled'), findsNothing);
  });
}
