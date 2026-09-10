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
  'options': [
    {'optionId': 'allow', 'kind': 'allow_once'},
    {'optionId': 'deny', 'kind': 'reject_once'},
  ],
};
void main() {
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
