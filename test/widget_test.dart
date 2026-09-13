import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/storage/database.dart';
import 'dart:io';
import 'package:careershopper/src/features/ai/chat_transcript.dart';
import 'package:careershopper/src/domain/chat_image.dart';
import 'dart:async';

import 'package:careershopper/src/app.dart';
import 'package:careershopper/src/features/inbox/job_chat_panel.dart';
import 'package:careershopper/src/features/statistics/statistics_page.dart';
import 'package:careershopper/src/documents/document_prompt.dart';
import 'package:careershopper/src/documents/application_exporter.dart';
import 'package:careershopper/src/storage/application_material_repository.dart';
import 'package:careershopper/src/features/ai/agent_settings_dialog.dart';
import 'package:careershopper/src/features/ai/ai_harnesses_page.dart';
import 'package:careershopper/src/features/ai/ai_page.dart';
import 'package:careershopper/src/features/documents/application_materials_panel.dart';
import 'package:careershopper/src/features/documents/job_application_actions.dart';
import 'package:careershopper/src/protocol/acp_configuration.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/domain/job_statistics.dart';
import 'package:careershopper/src/protocol/acp_registry.dart';
import 'package:careershopper/src/sources/job_source_adapter.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/ai_agent_purpose.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:careershopper/src/storage/document_template_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:careershopper/src/storage/listing_availability_service.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final page in [0, 1]) {
    testWidgets(
      'live search filters title, body, and employer on jobs page $page',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final jobs = _InboxQueueStore()
          ..current = [
            _queueJob(
              'one',
              title: 'Backend Engineer',
              employer: 'Oak',
              description: 'Build APIs with 100%_coverage.',
            ),
            _queueJob(
              'two',
              title: 'Data Engineer',
              employer: 'Pine',
              description: 'Maintain PostgreSQL clusters.',
            ),
            _queueJob(
              'three',
              title: 'Designer',
              employer: 'Coral',
              description: 'Design interfaces.',
            ),
          ];
        addTearDown(jobs.close);
        await tester.pumpWidget(
          CareerShopperApp(
            jobs: jobs,
            configuration: _EmptyConfigurationStore(),
            profile: _EmptyProfileStore(),
            templates: _EmptyDocumentTemplateStore(),
            harnesses: _EmptyAiHarnessStore(),
          ),
        );
        await tester.pumpAndSettle();
        if (page == 1) {
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .onDestinationSelected!(1);
          await tester.pumpAndSettle();
        }
        expect(find.text('Job ID: one'), findsOneWidget);
        expect(find.byTooltip('Copy job ID'), findsOneWidget);
        final search = find.byKey(const ValueKey('job-list-search'));
        expect(
          tester.getBottomLeft(search).dy,
          lessThan(tester.getTopLeft(find.text('Backend Engineer').first).dy),
        );
        for (final (term, title) in [
          (' BACKEND ', 'Backend Engineer'),
          ('postgre', 'Data Engineer'),
          ('CORAL', 'Designer'),
          ('%_', 'Backend Engineer'),
          ('two', 'Data Engineer'),
        ]) {
          await tester.enterText(search, term);
          await tester.pumpAndSettle();
          expect(find.text(title), findsNWidgets(2));
          for (final other in [
            'Backend Engineer',
            'Data Engineer',
            'Designer',
          ].where((s) => s != title)) {
            expect(find.text(other), findsNothing);
          }
        }
        await tester.enterText(search, 'Engineer PostgreSQL');
        await tester.pumpAndSettle();
        expect(find.text('Designer'), findsNothing);
        expect(
          tester.getTopLeft(find.text('Data Engineer').first).dy,
          lessThan(tester.getTopLeft(find.text('Backend Engineer').first).dy),
        );
        await tester.enterText(search, 'no such job');
        await tester.pumpAndSettle();
        expect(find.text('No matching jobs'), findsOneWidget);
        expect(search, findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Designer'), findsOneWidget);
        await tester.tap(find.text('Data Engineer'));
        await tester.pumpAndSettle();
        await tester.enterText(search, 'Engineer');
        await tester.pumpAndSettle();
        expect(find.text('Data Engineer'), findsNWidgets(2));
        expect(find.text('Backend Engineer'), findsOneWidget);
        expect(find.text('Designer'), findsNothing);
        if (page == 0) {
          jobs.current = [jobs.current[1]];
          await tester.tap(find.text('Refresh'));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(search).controller!.text, 'Engineer');
          expect(find.text('Data Engineer'), findsNWidgets(2));
        }
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('inbox-count'))).data,
          '3',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'inbox count updates without moving jobs and header actions are organized',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final jobs = _InboxQueueStore();
      addTearDown(jobs.close);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _InboxQueueHarness(jobs),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        true,
      );
      final count = find.byKey(const ValueKey('inbox-count'));
      expect(tester.widget<Text>(count).data, '3');
      final approve = find.widgetWithText(FilledButton, 'Approve');
      final export = find.widgetWithText(OutlinedButton, 'Export documents');
      expect(approve, findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(
        tester.getTopLeft(approve).dx,
        lessThan(tester.getTopLeft(export).dx),
      );
      expect(find.text('Approval required'), findsNothing);
      expect(find.text('Outcome: Active'), findsNothing);
      expect(find.text('Refresh & reanalyze'), findsNothing);
      expect(find.text('Block employer'), findsNothing);
      final stage = find.byTooltip('Change application stage');
      final chat = find.widgetWithText(OutlinedButton, 'Chat about this job');
      expect(tester.getTopLeft(stage).dy, lessThan(tester.getTopLeft(chat).dy));
      expect(
        tester.getTopRight(stage).dx,
        closeTo(tester.getTopRight(chat).dx, 1),
      );
      expect(tester.getTopRight(chat).dx, greaterThan(1800));
      await tester.tap(find.byTooltip('More job actions'));
      await tester.pumpAndSettle();
      expect(find.text('Refresh & reanalyze'), findsOneWidget);
      expect(find.text('Block employer'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      jobs.update([_queueJob('new'), ...jobs.current]);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(count).data, '4');
      expect(find.text('Job new'), findsNothing);
      expect(find.text('Job one'), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.work_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('All jobs'), findsNWidgets(2));
      jobs.update([]);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(count).data, '0');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final jobChat in [false, true]) {
    testWidgets(
      'generate from scratch starts and opens a new document conversation ($jobChat)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harnesses = _RetryChatHarness('interrupted');
        addTearDown(harnesses.changes.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: jobChat
                  ? JobChatPanel(job: _OneJobStore.job, harnesses: harnesses)
                  : AiActivityPage(harnesses: harnesses),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Resume generation'), findsOneWidget);
        await tester.tap(find.text('Generate from scratch'));
        await tester.pumpAndSettle();
        expect(harnesses.freshJobs, [_OneJobStore.job.id]);
        expect(harnesses.retried, isEmpty);
        expect(find.text('Documents generated.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final jobChat in [false, true]) {
    for (final status in ['failed', 'interrupted']) {
      testWidgets(
        'retry resumes the selected document conversation ($jobChat, $status)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final harnesses = _RetryChatHarness(status);
          addTearDown(harnesses.changes.close);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: jobChat
                    ? JobChatPanel(job: _OneJobStore.job, harnesses: harnesses)
                    : AiActivityPage(harnesses: harnesses),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Keep my draft');
          await tester.tap(find.text('Resume generation'));
          await tester.pump();
          expect(harnesses.retried, ['failed-materials']);
          expect(find.text('Starting document generation…'), findsOneWidget);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Resume generation'),
                )
                .onPressed,
            isNull,
          );
          harnesses.resuming.complete();
          await tester.pumpAndSettle();
          expect(harnesses.sent, isEmpty);
          expect(harnesses.started, isEmpty);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Keep my draft',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final jobChat in [false, true]) {
    testWidgets(
      'chat shows work and accepts steering and interruption (job: $jobChat)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harnesses = _RunningChatHarness();
        addTearDown(harnesses.changes.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: jobChat
                  ? JobChatPanel(job: _OneJobStore.job, harnesses: harnesses)
                  : AiActivityPage(harnesses: harnesses),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Agent is working…'), findsOneWidget);
        expect(find.text('Steer'), findsOneWidget);
        final input = find.byType(TextField);
        expect(tester.widget<TextField>(input).enabled, true);
        await tester.enterText(input, 'Focus on office attendance');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(harnesses.sent, [('discussion', 'Focus on office attendance')]);
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        harnesses.stopping = Completer<void>();
        await tester.enterText(input, 'Keep this unsent draft');
        await tester.tap(find.text('Interrupt'));
        await tester.pump();
        expect(find.text('Interrupting current turn…'), findsOneWidget);
        harnesses.stopping!.complete();
        await tester.pumpAndSettle();
        expect(harnesses.interrupted, ['discussion']);
        expect(
          find.text('Interrupted. Send a message to continue.'),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Keep this unsent draft',
        );
        expect(tester.widget<TextField>(input).enabled, true);
        expect(find.text('Steer'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final jobChat in [false, true]) {
    testWidgets('paste images and text in chat (job: $jobChat)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _ContextHarnessStore();
      addTearDown(harnesses.changes.close);
      harnesses.current = [
        AiConversation(
          id: 'discussion',
          title: 'Job chat',
          kind: 'job_chat',
          status: 'completed',
          updatedAt: DateTime(2026),
        ),
      ];
      Uint8List? clipboardImage = File(
        'test/fixtures/chat-image.png',
      ).readAsBytesSync();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': 'pasted text'};
          }
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const channel = MethodChannel('pasteboard');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => clipboardImage,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: jobChat
                ? JobChatPanel(job: _OneJobStore.job, harnesses: harnesses)
                : AiActivityPage(harnesses: harnesses),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.tap(input);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove image 1'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byTooltip('Remove image 1'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byTooltip('Paste image'));
      await tester.pumpAndSettle();
      await tester.tap(input);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harnesses.sent, [('discussion', '')]);
      expect(harnesses.sentImages.single.single.bytes, clipboardImage);
      expect(find.byTooltip('Remove image 1'), findsNothing);
      clipboardImage = null;
      await Clipboard.setData(const ClipboardData(text: 'pasted text'));
      await tester.enterText(input, 'replace me');
      tester.widget<TextField>(input).controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 10);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'pasted text');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'transcript follows appended and streaming output only at the bottom',
    (tester) async {
      final harnesses = _StreamingTranscriptHarness();
      addTearDown(harnesses.activity.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTranscript(conversationId: 'chat', harnesses: harnesses),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(controller.position.extentAfter, lessThan(1));
      harnesses.update(31);
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, lessThan(1));
      harnesses.update(31, lastLines: 20);
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, lessThan(1));
      controller.jumpTo(controller.position.maxScrollExtent - 350);
      await tester.pumpAndSettle();
      final offset = controller.offset;
      harnesses.update(32);
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(offset, 1));
      expect(controller.position.extentAfter, greaterThan(100));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      harnesses.update(33);
      await tester.pumpAndSettle();
      expect(controller.position.extentAfter, lessThan(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final decision in [
    'applied',
    'discard',
    'keep',
    'later',
    'browser_error',
  ]) {
    testWidgets('Apply completion flow: $decision', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _ApplyDecisionStore();
      final harnesses = _HeaderExportHarness(succeed: true);
      final opened = <Uri>[];
      final busy = <bool>[];
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobApplicationActions(
              job: InboxJob(
                id: 'apply-job',
                title: 'Engineer',
                employerName: 'Example',
                location: 'Remote',
                description: 'Build things',
                applicationUrl: Uri.parse('https://example.test/apply'),
                availability: JobAvailability.open,
                reviewState: ReviewState.approved,
                applicationStatus: ApplicationStatus.readyToApply,
                observedAt: DateTime(2026),
              ),
              harnesses: harnesses,
              repository: jobs,
              dirty: false,
              onBusyChanged: busy.add,
              onChanged: () async {
                expect(busy.last, false);
                changes++;
              },
              openUrl: (url) async {
                opened.add(url);
                if (decision == 'browser_error') {
                  throw StateError('Browser unavailable');
                }
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://example.test/apply');
      expect(jobs.applied, isEmpty);
      expect(jobs.discarded, isEmpty);
      if (decision == 'browser_error') {
        expect(find.text('Did you complete the application?'), findsNothing);
        expect(find.textContaining('Browser unavailable'), findsOneWidget);
      } else {
        expect(find.text('Did you complete the application?'), findsOneWidget);
        await tester.tap(
          find.text(
            decision == 'applied'
                ? 'Yes, applied'
                : decision == 'later'
                ? 'Not now'
                : 'No',
          ),
        );
        await tester.pumpAndSettle();
        if (decision == 'discard' || decision == 'keep') {
          expect(find.text('Discard this job listing?'), findsOneWidget);
          await tester.tap(
            find.text(decision == 'discard' ? 'Discard job' : 'Keep job'),
          );
          await tester.pumpAndSettle();
        }
      }
      expect(jobs.applied, decision == 'applied' ? ['apply-job'] : isEmpty);
      expect(jobs.discarded, decision == 'discard' ? ['apply-job'] : isEmpty);
      expect(changes, decision == 'applied' || decision == 'discard' ? 1 : 0);
      expect(busy, [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'central chat Enter sends while Shift Enter preserves multiline input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _KeyboardChatHarness();
      addTearDown(harnesses.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AiActivityPage(harnesses: harnesses)),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.widgetWithText(TextField, 'Message the agent…');
      await tester.enterText(input, 'First line');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(harnesses.sent, isEmpty);
      // Simulate the platform text input's newline update after Shift+Enter.
      tester.testTextInput.enterText('First line\nSecond line');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harnesses.sent, [('analysis', 'First line\nSecond line')]);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(harnesses.sent, hasLength(1));
      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Ask about your profile, searches, or jobs…',
        ),
        'New question',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harnesses.newMessages, ['New question']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'job notes are separate from chat and both retain their context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _ContextJobStore();
      addTearDown(jobs.noteChanges.close);
      final harnesses = _ContextHarnessStore();
      addTearDown(harnesses.changes.close);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add notes'));
      await tester.tap(find.text('Add notes'));
      await tester.pumpAndSettle();
      expect(harnesses.started, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Ask about office visits',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved notes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save notes'));
      await tester.pumpAndSettle();
      expect(jobs.notes, 'Ask about office visits');
      expect(find.text('Ask about office visits'), findsOneWidget);
      await tester.ensureVisible(find.text('Chat about this job'));
      await tester.tap(find.text('Chat about this job'));
      await tester.pumpAndSettle();
      expect(harnesses.watchedJob, 'job-1');
      expect(find.text('Prior remote assessment'), findsOneWidget);
      expect(
        find
            .byType(TabBar)
            .evaluate()
            .where(
              (element) => (element.widget as TabBar).tabs.any(
                (tab) => tab is Tab && tab.text == 'Notes',
              ),
            ),
        isEmpty,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Message about this job'),
        'Is this remote?',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harnesses.started, [('job-1', 'Is this remote?', 'analysis')]);
      await tester.tap(find.byTooltip('Close job chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat about this job'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Message about this job'),
        'What should I ask?',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harnesses.sent, [('discussion', 'What should I ask?')]);
      await tester.tap(find.byTooltip('Close job chat'));
      await tester.pumpAndSettle();
      expect(find.text('Ask about office visits'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('assigns agent purposes and duplicates a named configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harnesses = _PurposeAiHarnessStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiHarnessesPage(harnesses: harnesses)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Agents by purpose'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fast matcher').last);
    await tester.pumpAndSettle();
    expect(harnesses.assignments, [(AiAgentPurpose.jobMatching, 'fast')]);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Writer').last);
    await tester.pumpAndSettle();
    expect(harnesses.assignments.last, (
      AiAgentPurpose.applicationWriting,
      'writer',
    ));
    await tester.ensureVisible(find.byTooltip('Duplicate configuration').first);
    await tester.tap(find.byTooltip('Duplicate configuration').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Quick screening');
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(harnesses.duplicates, [('writer', 'Quick screening')]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'partial success shows completion and actual request/response bodies',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _EmptyJobStore(),
          configuration: _PartialSearchConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.tap(find.byIcon(Icons.manage_search).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run history & diagnostics'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indeed: Completed with skipped records'),
        findsOneWidget,
      );
      expect(find.textContaining('Needs attention'), findsNothing);
      await tester.tap(find.text('Request 1 and response'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"query": "actual query"'), findsOneWidget);
      expect(find.textContaining('"results": []'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final clearFromSearch in [true, false]) {
    testWidgets(
      'shows blocks on sources and searches; clears from ${clearFromSearch ? 'searches' : 'sources'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final configuration = _BlockedSourceConfigurationStore();
        addTearDown(configuration.changes.close);
        await tester.pumpWidget(
          CareerShopperApp(
            jobs: _EmptyJobStore(),
            configuration: configuration,
            profile: _EmptyProfileStore(),
            templates: _EmptyDocumentTemplateStore(),
            harnesses: _EmptyAiHarnessStore(),
          ),
        );
        await tester.tap(find.byIcon(Icons.hub_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Indeed: Blocked'), findsOneWidget);
        expect(find.text('Provider returned a CAPTCHA.'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.manage_search).first);
        await tester.pumpAndSettle();
        expect(find.text('Indeed: Blocked'), findsOneWidget);
        if (!clearFromSearch) {
          await tester.tap(find.byIcon(Icons.hub_outlined));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Clear block'));
        await tester.pumpAndSettle();
        expect(configuration.cleared, ['blocked']);
        expect(find.text('Indeed: Blocked'), findsNothing);
        expect(find.text('Clear block'), findsNothing);
        expect(configuration.runIds, isEmpty);
        expect(configuration.enabledChanges, isEmpty);
        expect(tester.widget<Switch>(find.byType(Switch)).value, false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('blocked employers navigation exposes reasons and unblock', (
    tester,
  ) async {
    final jobs = _BlockedEmployerJobStore();
    addTearDown(jobs.employers.close);
    await tester.binding.setSurfaceSize(const Size(1300, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: jobs,
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.business_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Example employer'), findsOneWidget);
    expect(find.textContaining('Not a suitable employer'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('No blocked employers.'), findsOneWidget);
    expect(jobs.unblockedId, 'blocked');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('statistics defaults to all time and filters the funnel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final jobs = _StatisticsJobStore();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: jobs,
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.tap(find.byIcon(Icons.query_stats_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Application statistics'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All time'))
          .selected,
      true,
    );
    await tester.binding.setSurfaceSize(const Size(1900, 2400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Application statistics')).dy, 32);
    await tester.binding.setSurfaceSize(const Size(1900, 1000));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Dates select jobs by their last state change'),
      findsNothing,
    );
    await tester.tap(find.byTooltip('About Application funnel'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Dates select jobs by their last state change'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Listing refreshes and note edits'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('About Application flow'));
    await tester.tap(find.byTooltip('About Application flow'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Each selected job enters through its first recorded source',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All time'));
    await tester.pumpAndSettle();
    expect(jobs.since, isNull);
    expect(find.byKey(const ValueKey('application-sankey')), findsOneWidget);
    expect(find.byKey(const ValueKey('application-funnel')), findsOneWidget);
    final chart = find.byKey(const ValueKey('application-sankey'));
    expect(tester.getSize(chart).width, greaterThan(1420));
    final finalLabel = tester.getRect(
      find.byKey(const ValueKey('sankey-offer_waiting')),
    );
    expect(finalLabel.right, lessThanOrEqualTo(tester.getRect(chart).right));
    expect(finalLabel.left, greaterThanOrEqualTo(tester.getRect(chart).left));
    expect(find.text('AI rejected'), findsOneWidget);
    expect(find.text('Accepted offer'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('application-sankey'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('application-funnel'))).dy,
      ),
    );
    expect(find.text('120'), findsNWidgets(3));
    expect(find.text('30'), findsNWidgets(2));
    expect(find.text('12'), findsNWidgets(2));
    expect(find.text('3'), findsNWidgets(3));
    for (final period in [
      StatisticsPeriod.today,
      StatisticsPeriod.thisMonth,
      StatisticsPeriod.thisYear,
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, period.label));
      await tester.pumpAndSettle();
      expect(jobs.since, period.start(DateTime.now()));
      expect(
        find.text('No jobs changed state in this period.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(StatisticsPage),
          matching: find.text('0'),
        ),
        findsNWidgets(20),
      );
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'All time'));
    await tester.pumpAndSettle();
    expect(find.text('120'), findsNWidgets(3));
    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final format in ApplicationDocumentFormat.values) {
    testWidgets('export $format works without review or a listing URL', (
      tester,
    ) async {
      final harnesses = _HeaderExportHarness(succeed: true);
      final busy = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JobApplicationActions(
              repository: _EmptyJobStore(),
              onChanged: () async {},
              job: InboxJob(
                id: 'job',
                title: 'Engineer',
                employerName: 'Example',
                location: 'Remote',
                description: 'Build things',
                applicationUrl: null,
                availability: JobAvailability.open,
                reviewState: ReviewState.approved,
                applicationStatus: ApplicationStatus.notApplied,
                observedAt: DateTime(2026),
              ),
              harnesses: harnesses,
              dirty: false,
              onBusyChanged: busy.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (format == ApplicationDocumentFormat.pdf) {
        await tester.tap(
          find.byType(PopupMenuButton<ApplicationDocumentFormat>),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('PDF').last);
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Export documents'));
      await tester.pumpAndSettle();
      expect(harnesses.exported, ['job', 'draft', format]);
      expect(busy, [true, false]);
      expect(
        find.text('Application files: /test/Documents/CareerShopper'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No listing opened or application status changed.'),
        findsOneWidget,
      );
      expect(harnesses.savedResume, isNull);
    });
  }
  testWidgets('job header Apply calls the existing export service', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harnesses = _HeaderExportHarness();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _ApprovedAppliedJobStore(status: ApplicationStatus.notApplied),
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: harnesses,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(harnesses.exported, [
      'approved-job',
      'draft',
      ApplicationDocumentFormat.docx,
    ]);
    expect(
      find.text('Bad state: Fixture export stopped before browser launch.'),
      findsOneWidget,
    );
  });

  for (final status in <String?>[null, 'failed']) {
    testWidgets('job header explains missing documents ($status)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _ApprovedAppliedJobStore(status: ApplicationStatus.notApplied),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _MissingDraftHarness(status: status),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(find.text('Approval required'), findsNothing);
    });
  }
  for (final scenario in [
    (reviewed: true, status: null, label: 'Ready to apply', enabled: true),
    (reviewed: false, status: null, label: 'Ready to apply', enabled: true),
    (
      reviewed: true,
      status: 'running',
      label: 'Generating documents…',
      enabled: false,
    ),
  ]) {
    testWidgets(
      'job header shows ${scenario.label} (reviewed: ${scenario.reviewed}) before opening documents',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          CareerShopperApp(
            jobs: _ApprovedAppliedJobStore(
              status: ApplicationStatus.notApplied,
            ),
            configuration: _EmptyConfigurationStore(),
            profile: _EmptyProfileStore(),
            templates: _EmptyDocumentTemplateStore(),
            harnesses: _DraftHarness(
              reviewed: scenario.reviewed,
              status: scenario.status,
            ),
          ),
        );
        // Running state includes a progress animation, so do not pumpAndSettle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final apply = find.widgetWithText(FilledButton, 'Apply');
        expect(apply, scenario.enabled ? findsOneWidget : findsNothing);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
        expect(
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Export documents'),
                  )
                  .onPressed !=
              null,
          scenario.enabled,
        );
        if (scenario.enabled) {
          expect(
            tester.getTopLeft(apply).dx,
            lessThan(
              tester
                  .getTopLeft(
                    find.widgetWithText(OutlinedButton, 'Export documents'),
                  )
                  .dx,
            ),
          );
        }
        expect(
          find.descendant(
            of: find.byType(ApplicationMaterialsPanel),
            matching: find.byType(TextField),
          ),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(Tab, 'Application documents'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Save & mark reviewed'), findsOneWidget);
        expect(apply, scenario.enabled ? findsOneWidget : findsNothing);
      },
    );
  }

  testWidgets(
    'prompt-only reset restores defaults without resetting layout or saving early',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final templates = _RecordingDocumentTemplateStore();
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _EmptyJobStore(),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: templates,
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.tap(find.byIcon(Icons.description_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cover letter export:'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Template name'),
        'Personal layout',
      );
      await tester.tap(find.text('Document generation prompt'));
      await tester.pumpAndSettle();
      final prompt = find.widgetWithText(TextFormField, 'Generation prompt');
      await tester.enterText(prompt, 'My custom writing prompt');
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();
      final before = templates.savedDraft!.settings.toJson()
        ..remove('generation_prompt');
      await tester.ensureVisible(find.text('Reset prompt to default'));
      await tester.tap(find.text('Reset prompt to default'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(prompt).controller!.text,
        defaultDocumentGenerationPrompt,
      );
      expect(
        templates.savedDraft!.settings.generationPrompt,
        'My custom writing prompt',
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();
      expect(
        templates.savedDraft!.settings.generationPrompt,
        defaultDocumentGenerationPrompt,
      );
      expect(templates.savedDraft!.name, 'Personal layout');
      expect(
        templates.savedDraft!.settings.toJson()..remove('generation_prompt'),
        before,
      );
    },
  );
  testWidgets(
    'job document tabs show editable Markdown and retain edits across tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DraftHarness(reviewed: true);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _ApprovedAppliedJobStore(
            status: ApplicationStatus.readyToApply,
          ),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ApplicationMaterialsPanel),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(Tab, 'Application documents'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(ApplicationMaterialsPanel),
              matching: find.byType(TextField),
            )
            .first,
        'Edited inline',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Refresh'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(minutes: 4));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export documents'),
            )
            .onPressed,
        isNull,
      );
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Generate from scratch'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(Tab, 'Job details'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Application documents'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byType(ApplicationMaterialsPanel),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        contains('Edited inline'),
      );
      await tester.ensureVisible(find.text('Save & mark reviewed'));
      await tester.tap(find.text('Save & mark reviewed'));
      await tester.pumpAndSettle();
      expect(harnesses.savedResume, contains('Edited inline'));
    },
  );

  testWidgets(
    'opening an older approval queues its first drafts automatically',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DispatchRecordingAiHarnessStore();
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _ApprovedAppliedJobStore(status: ApplicationStatus.notApplied),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();
      expect(harnesses.dispatchedJobId, 'approved-job');
    },
  );

  testWidgets(
    'approval advances inbox selection without navigation or return-job focus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _InboxQueueStore();
      addTearDown(jobs.close);
      final harnesses = _InboxQueueHarness(jobs);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Job two'));
      await tester.pumpAndSettle();
      expect(find.text('Description for two'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(harnesses.approved, ['two']);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
      );
      expect(find.text('Job two'), findsNothing);
      expect(find.text('Description for three'), findsOneWidget);
      expect(find.text('Job description'), findsOneWidget);

      // Completing documents restores a higher-ranked job without stealing focus.
      jobs.update([
        _queueJob('one'),
        _queueJob('two', ready: true),
        _queueJob('three'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Job two'), findsNothing);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Job two'), findsOneWidget);
      expect(find.text('Description for three'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(harnesses.approved, ['two', 'three']);
      expect(find.text('Description for two'), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
      );

      jobs.update([]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing needs your attention'), findsOneWidget);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
      );
    },
  );
  for (final (status, readyToApply, label) in [
    (ApplicationStatus.notApplied, false, 'Approved'),
    (ApplicationStatus.readyToApply, false, 'Approved'),
    (ApplicationStatus.notApplied, true, 'Ready to apply'),
    (ApplicationStatus.readyToApply, true, 'Ready to apply'),
    (ApplicationStatus.interviewing, false, 'Interviewing'),
    (ApplicationStatus.unknown, false, 'Stage not recorded'),
    (ApplicationStatus.offer, false, 'Offer'),
    (ApplicationStatus.hired, false, 'Hired'),
  ]) {
    testWidgets('approved job shows only $label for ${status.name}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _ApprovedAppliedJobStore(
            status: status,
            readyToApply: readyToApply,
          ),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('Stage: $label'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Not applied'), findsNothing);
      if (label != 'Approved') expect(find.text('Approved'), findsNothing);
    });
  }
  testWidgets('Applied replaces approval everywhere in the job UI', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _ApprovedAppliedJobStore(),
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Approved'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Not applied'), findsNothing);
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Stage: Applied'), findsOneWidget);
    expect(find.text('Queued'), findsNothing);
    expect(find.text('Queued for application'), findsNothing);
  });
  testWidgets(
    'outcome control retains the interview stage in list and detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _ApprovedAppliedJobStore(
        status: ApplicationStatus.interviewing,
        outcome: ApplicationOutcome.rejected,
      );
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Interviewing'), findsOneWidget);
      expect(find.text('Rejected by employer'), findsOneWidget);
      expect(find.text('Stage: Interviewing'), findsOneWidget);
      expect(find.text('Outcome: Rejected by employer'), findsNothing);
      await tester.tap(find.byTooltip('Change application stage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Withdrawn by me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Withdrawn by me'));
      await tester.pumpAndSettle();
      expect(jobs.recordedOutcome, ApplicationOutcome.withdrawn);
      expect(find.text('Stage: Interviewing'), findsOneWidget);
    },
  );
  testWidgets(
    'document panel focuses on generating and reviewing, not applying',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DraftHarness();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApplicationMaterialsPanel(
              job: _OneJobStore.job,
              harnesses: harnesses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Apply'), findsNothing);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Cover letter'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Edited name');
      await tester.tap(find.text('Save & mark reviewed'));
      await tester.pumpAndSettle();
      expect(harnesses.savedResume, startsWith('# Edited name'));
      expect(harnesses.savedResume, '# Edited name <!-- facts: identity -->');
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Generate from scratch'));
      await tester.pumpAndSettle();
      expect(harnesses.generated, isTrue);
    },
  );
  testWidgets(
    'Copy Markdown copies the entire current document from preview and source without saving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final harnesses = _DraftHarness();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApplicationMaterialsPanel(
              job: _OneJobStore.job,
              harnesses: harnesses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Edited name');
      await tester.tap(find.text('Copy Markdown'));
      await tester.pumpAndSettle();
      expect(clipboard, '# Edited name <!-- facts: identity -->');
      expect(harnesses.savedResume, isNull);

      await tester.tap(find.text('Markdown source'));
      await tester.pumpAndSettle();
      const fullResume =
          '# Edited name <!-- facts: identity -->\n\n## Experience <!-- facts: identity -->\n\n- Complete resume text with unsaved changes. <!-- facts: experience -->';
      await tester.enterText(find.byType(TextField).first, fullResume);
      await tester.tap(find.text('Copy Markdown'));
      await tester.pumpAndSettle();
      expect(clipboard, fullResume);

      await tester.tap(find.text('Cover letter'));
      await tester.pumpAndSettle();
      const fullLetter =
          '# Edited name <!-- facts: identity -->\n\nMy full cover letter. <!-- facts: experience -->';
      await tester.enterText(find.byType(TextField).first, fullLetter);
      await tester.tap(find.text('Copy Markdown'));
      await tester.pumpAndSettle();
      expect(clipboard, fullLetter);
      await tester.tap(find.text('Markdown source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Markdown'));
      await tester.pumpAndSettle();
      expect(clipboard, fullLetter);
      expect(harnesses.savedResume, isNull);
      expect(harnesses.generated, isFalse);
    },
  );

  testWidgets(
    'failed regeneration labels retained documents instead of reporting new drafts ready',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DraftHarness(status: 'failed');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApplicationMaterialsPanel(
              job: _OneJobStore.job,
              harnesses: harnesses,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Your previous documents and new staged work are preserved.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Documents ready to apply. You can optionally review or edit them here.',
        ),
        findsNothing,
      );
      expect(find.text('Alex'), findsOneWidget);
      expect(harnesses.generated, isFalse);
      await tester.tap(find.text('Resume generation'));
      await tester.pumpAndSettle();
      expect(harnesses.generated, isTrue);
      expect(harnesses.freshRequested, isFalse);
      await tester.tap(find.text('Generate from scratch'));
      await tester.pumpAndSettle();
      expect(harnesses.freshRequested, isTrue);
    },
  );
  testWidgets('agent settings refresh dependent controls and save on Done', (
    tester,
  ) async {
    final harnesses = _ConfiguringAiHarnessStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgentSettings(context, harnesses),
              child: const Text('Settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Agent defaults'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();
    expect(find.text('Fast mode'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(harnesses.values, {'model': 'beta', 'fast': true});
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(harnesses.saved, isTrue);
  });

  testWidgets('starts with the CareerShopper inbox shell', (tester) async {
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.pump();

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Nothing needs your attention'), findsOneWidget);
    expect(find.text('Add listing'), findsOneWidget);
  });

  testWidgets(
    'job list replaces company placeholder and source tag with source icon',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _OneJobStore(),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LinkedIn'), findsNothing);
      expect(find.byTooltip('Source: LinkedIn'), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/sources/linkedin.png')),
        findsOneWidget,
      );
      expect(find.text('EX'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('exposes source and saved-search setup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Add source'), findsWidgets);

    await tester.tap(find.byIcon(Icons.manage_search).first);
    await tester.pumpAndSettle();
    expect(find.text('Add search'), findsWidgets);
    expect(
      find.text('AI-assisted or manual—it is your strategy'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.badge_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Career facts'), findsNothing);
    expect(find.text('Add fact'), findsNothing);
    expect(find.text('Resume content'), findsOneWidget);
    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Add preference'), findsOneWidget);
  });

  testWidgets(
    'an evaluated job can be refreshed and fully scrolled',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DispatchRecordingAiHarnessStore();
      final jobs = _OneJobStore();
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Refresh & reanalyze'), findsNothing);
      final openButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Open listing in browser'),
      );
      expect(openButton.onPressed, isNotNull);
      expect(find.byType(Scrollbar), findsWidgets);
      final detailView = find.byType(SingleChildScrollView);
      final detailPosition = tester
          .state<ScrollableState>(
            find
                .descendant(of: detailView, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(detailView),
          scrollDelta: const Offset(0, 400),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(detailPosition.pixels, greaterThan(0));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(detailView),
          scrollDelta: const Offset(0, -400),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(detailPosition.pixels, 0);
      await tester.tap(find.byTooltip('Change application stage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Applied').last);
      await tester.pumpAndSettle();
      expect(jobs.recordedStatus, ApplicationStatus.applied);
      await tester.tap(find.byTooltip('More job actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh & reanalyze'));
      await tester.pumpAndSettle();

      expect(harnesses.dispatchedJobId, 'job-1');
      expect(find.text('Activity'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'failed AI job shows an inbox error and retries without navigating away',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harnesses = _DispatchRecordingAiHarnessStore();
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _ApprovedAppliedJobStore(
            status: ApplicationStatus.notApplied,
            aiError: 'Run interrupted. Retry required.',
          ),
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: harnesses,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI failed · action needed'), findsOneWidget);
      expect(find.text('Run interrupted. Retry required.'), findsOneWidget);
      await tester.tap(find.text('Retry AI'));
      await tester.pumpAndSettle();
      expect(harnesses.dispatchedJobId, 'approved-job');
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('All encountered jobs'), findsNothing);
    },
  );

  testWidgets(
    'inbox stays stable during window activity and refreshes fresh data when idle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _InboxQueueStore();
      addTearDown(jobs.close);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Job two'));
      await tester.pumpAndSettle();
      jobs.update([_queueJob('new'), _queueJob('three'), _queueJob('two')]);
      await tester.pumpAndSettle();
      expect(find.text('Job new'), findsNothing);
      expect(find.text('Job one'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Job new'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(30, 150));
      await mouse.moveTo(const Offset(35, 155));
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Job new'), findsNothing);
      await mouse.removePointer();
      // A fresh query must also see writes that never notified the original stream.
      jobs.current = [_queueJob('fresh'), _queueJob('two'), _queueJob('three')];
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Job fresh'), findsOneWidget);
      expect(find.text('Job one'), findsNothing);
      expect(find.text('Description for two'), findsOneWidget);
      jobs.current = [_queueJob('second'), _queueJob('two')];
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      expect(find.text('Job second'), findsOneWidget);
      expect(find.text('Description for two'), findsOneWidget);
      jobs.current = [];
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing needs your attention'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      jobs.current = [_queueJob('back')];
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Job back'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'resuming activity prevents an in-flight idle refresh from moving the inbox',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final jobs = _DelayedInboxStore();
      addTearDown(jobs.close);
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: jobs,
          configuration: _EmptyConfigurationStore(),
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.pumpAndSettle();
      jobs.pending = Completer<List<InboxJob>>();
      await tester.pump(const Duration(minutes: 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      jobs.pending!.complete([_queueJob('late')]);
      await tester.pumpAndSettle();
      expect(find.text('Job late'), findsNothing);
      expect(find.text('Job one'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('returning to inbox does not cache the all-jobs list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final jobs = _ViewSwitchInboxStore();
    addTearDown(jobs.close);
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: jobs,
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected!(1);
    await tester.pumpAndSettle();
    expect(find.text('Job outside'), findsWidgets);
    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected!(0);
    await tester.pumpAndSettle();
    expect(find.text('Job outside'), findsNothing);
    expect(find.text('Job one'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('runs a paused search manually without enabling it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configuration = _PausedSearchConfigurationStore();
    final harnesses = _SearchAnalysisHarness();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: configuration,
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: harnesses,
      ),
    );
    await tester.tap(find.byIcon(Icons.manage_search).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byTooltip('Run search now'));
    await tester.pumpAndSettle();
    expect(configuration.runIds, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(configuration.runIds, isEmpty);
    await tester.tap(find.byTooltip('Run search now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run search'));
    await tester.pumpAndSettle();
    expect(configuration.runIds, ['paused-search']);
    expect(harnesses.analyzedIds, ['new-job']);
    expect(find.text('Search results: Backend'), findsOneWidget);
    expect(find.text('Test: Completed'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run history & diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Run history: Backend'), findsOneWidget);
    expect(find.text('No recorded runs yet.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(configuration.enabledChanges, isEmpty);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('search failure is readable immediately and again in history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: _FailedSearchConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _SearchAnalysisHarness(),
      ),
    );
    await tester.tap(find.byIcon(Icons.manage_search).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Run search now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run search'));
    await tester.pumpAndSettle();
    expect(find.text('Indeed: Failed'), findsOneWidget);
    expect(find.text('Provider denied access (HTTP 403).'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run history & diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Provider denied access (HTTP 403).'), findsOneWidget);
    await tester.tap(find.text('Request 1 and response'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"http_status": 403'), findsOneWidget);
    expect(
      find.text(
        'Request and response bodies were not saved for this older run.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('allows a saved search to be created manually', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configuration = _RecordingConfigurationStore();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: configuration,
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.manage_search).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add search').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Search name'),
      'Backend and platform',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Target titles'),
      'Backend Engineer, Platform Engineer',
    );
    await tester.tap(find.text('Save search'));
    await tester.pumpAndSettle();

    expect(configuration.savedDraft?.name, 'Backend and platform');
    expect(configuration.savedDraft?.query.includedTitles, [
      'Backend Engineer',
      'Platform Engineer',
    ]);
    expect(configuration.savedDraft?.scoreThreshold, 70);
    expect(configuration.savedDraft?.pollIntervalMinutes, 360);
    expect(configuration.savedDraft?.scheduleCron, '0 9 * * *');
    expect(configuration.savedDraft?.sourceConfigIds, {'test-source'});
  });

  testWidgets('editing a saved search preserves its interval schedule', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configuration = _RecordingConfigurationStore(
      existing: const SavedSearchDefinition(
        id: 'search',
        name: 'Interval search',
        enabled: true,
        pollIntervalMinutes: 720,
        scoreThreshold: 70,
        query: SavedSearchQuery(name: 'Interval search'),
        sourceConfigIds: {'test-source'},
      ),
    );
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: configuration,
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: _EmptyAiHarnessStore(),
      ),
    );
    await tester.tap(find.byIcon(Icons.manage_search).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit search'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Interval (minutes)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Time (HH:mm)'), findsNothing);
    await tester.tap(find.text('Save search'));
    await tester.pumpAndSettle();
    expect(configuration.savedDraft?.scheduleCron, isNull);
    expect(configuration.savedDraft?.pollIntervalMinutes, 720);
    expect(configuration.savedDraft?.sourceConfigIds, {'test-source'});
  });

  testWidgets(
    'saved search supports custom cron and validates it before saving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final configuration = _RecordingConfigurationStore();
      await tester.pumpWidget(
        CareerShopperApp(
          jobs: _EmptyJobStore(),
          configuration: configuration,
          profile: _EmptyProfileStore(),
          templates: _EmptyDocumentTemplateStore(),
          harnesses: _EmptyAiHarnessStore(),
        ),
      );
      await tester.tap(find.byIcon(Icons.manage_search).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add search').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Search name'),
        'Weekday search',
      );
      final schedule = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Schedule',
      );
      await tester.ensureVisible(schedule);
      await tester.tap(schedule);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom cron').last);
      await tester.pumpAndSettle();
      final cron = find.widgetWithText(TextFormField, 'Cron expression');
      await tester.enterText(cron, 'not cron');
      await tester.tap(find.text('Save search'));
      await tester.pumpAndSettle();
      expect(configuration.savedDraft, isNull);
      await tester.enterText(cron, '0 9,17 * * 1-5');
      await tester.tap(find.text('Save search'));
      await tester.pumpAndSettle();
      expect(configuration.savedDraft?.scheduleCron, '0 9,17 * * 1-5');
      expect(configuration.savedDraft?.sourceConfigIds, {'test-source'});
    },
  );

  testWidgets('configures Codex from the ACP Registry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harnesses = _RecordingAiHarnessStore();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: _EmptyConfigurationStore(),
        profile: _EmptyProfileStore(),
        templates: _EmptyDocumentTemplateStore(),
        harnesses: harnesses,
      ),
    );

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(find.text('ACP agents'), findsOneWidget);
    expect(find.text('No ACP agent selected'), findsOneWidget);
    await tester.tap(find.text('Browse ACP Registry'));
    await tester.pumpAndSettle();
    expect(find.text('Official ACP Registry'), findsOneWidget);
    expect(find.text('Codex 1.8.0'), findsOneWidget);
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();

    expect(harnesses.savedRegistryAgent?.id, 'codex-acp');
  });

  testWidgets('shows and edits the resume template', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final templates = _RecordingDocumentTemplateStore();
    await tester.pumpWidget(
      CareerShopperApp(
        jobs: _EmptyJobStore(),
        configuration: _EmptyConfigurationStore(),
        profile: _IdentityProfileStore(),
        templates: templates,
        harnesses: _EmptyAiHarnessStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.description_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Document templates'), findsOneWidget);
    expect(find.text('Layout preview'), findsOneWidget);
    expect(find.text('Template settings'), findsOneWidget);
    expect(find.text('ALICE EXAMPLE'), findsOneWidget);
    expect(find.text('Boulder, Colorado · alice@example.test'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Template name'),
      'My resume',
    );
    await tester.tap(find.text('Document generation prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Generation prompt'),
      'Focus on systems ownership and measurable outcomes.',
    );
    await tester.tap(find.text('Save template'));
    await tester.pumpAndSettle();

    expect(templates.savedDraft?.name, 'My resume');
    expect(templates.savedDraft?.settings.fontFamily, 'Arial');
    expect(
      templates.savedDraft?.settings.generationPrompt,
      'Focus on systems ownership and measurable outcomes.',
    );
    await tester.tap(find.text('Use pipeline template'));
    await tester.pumpAndSettle();
    expect(templates.savedDraft?.settings.layout, 'pipeline-v1');
    expect(
      templates.savedDraft?.settings.generationPrompt,
      'Focus on systems ownership and measurable outcomes.',
    );
  });
}

class _EmptyAiHarnessStore implements AiHarnessStore {
  @override
  Future<void> resumeMaterialGeneration(String conversationId) async {}
  @override
  Future<void> interruptConversation(String conversationId) async {}
  @override
  Future<String> startJobConversation(
    String jobId,
    String message, {
    String? contextConversationId,
    List<ChatImage> images = const [],
  }) async => 'job-chat';
  @override
  Future<void> setPurposeProfile(AiAgentPurpose purpose, String? id) async {}
  @override
  Future<String> duplicateProfile(String id, String name) async => 'copy';
  @override
  Future<int> dispatchSearchAnalysis(List<String> jobIds) async => 0;
  @override
  Future<AiDispatchResult> queueApplication(
    String jobId, {
    bool fromScratch = false,
  }) => dispatchManualImport(jobId);
  @override
  Stream<ApplicationMaterials?> watchMaterials(String jobId) =>
      Stream.value(null);
  @override
  Stream<String?> watchMaterialStatus(String jobId) => Stream.value(null);
  @override
  Future<String> saveMaterials(
    String jobId,
    String materialId,
    String resume,
    String coverLetter,
  ) async => 'draft';
  @override
  Future<String> exportApplication(
    String jobId,
    String materialId,
    ApplicationDocumentFormat format,
    ApplicationDocumentRenderer renderer,
  ) async => '/tmp/test-output';
  @override
  Future<void> configureAgent(
    AcpConfigure configure, {
    String? profileId,
    String? conversationId,
  }) async {}
  @override
  Future<void> deleteProfile(String id) async {}

  @override
  Future<AiDispatchResult> dispatchManualImport(String jobId) async =>
      const AiDispatchResult(
        workOrderId: 'work-order',
        profileName: 'Test harness',
        launched: true,
      );

  @override
  Future<AcpRegistrySnapshot> fetchRegistry({bool refresh = false}) async =>
      AcpRegistrySnapshot(
        agents: const [],
        fetchedAt: DateTime.utc(2026, 9, 4),
        fromCache: false,
      );

  @override
  Future<String> saveRegistryAgent(AcpRegistryAgent agent) async => 'harness';

  @override
  Future<String> saveProfile(AiHarnessProfileDraft draft) async => 'harness';

  @override
  Future<void> setDefaultProfile(String id) async {}

  @override
  Future<void> sendMessage(
    String conversationId,
    String message, {
    List<ChatImage> images = const [],
  }) async {}

  @override
  Future<String> startConversation(
    String message, {
    List<ChatImage> images = const [],
  }) async => 'conversation';

  @override
  Stream<List<AiActivityEntry>> watchActivity(String conversationId) =>
      Stream.value(const []);

  @override
  Stream<List<AiConversation>> watchConversations({String? jobId}) =>
      Stream.value(const []);

  @override
  Stream<List<AiHarnessProfile>> watchProfiles() => Stream.value(const []);
}

class _DraftHarness extends _EmptyAiHarnessStore {
  _DraftHarness({this.reviewed = false, this.status});
  final bool reviewed;
  final String? status;
  @override
  Stream<String?> watchMaterialStatus(String jobId) => Stream.value(status);
  String? savedResume;
  bool generated = false;
  bool freshRequested = false;
  @override
  Stream<ApplicationMaterials?> watchMaterials(String jobId) => Stream.value(
    ApplicationMaterials(
      id: 'draft',
      resume: '# Alex <!-- facts: identity -->',
      coverLetter: 'Hello <!-- facts: identity -->',
      reviewed: reviewed,
      createdAt: DateTime.now(),
    ),
  );
  @override
  Future<String> saveMaterials(
    String jobId,
    String materialId,
    String resume,
    String coverLetter,
  ) async {
    savedResume = resume;
    return 'reviewed';
  }

  @override
  Future<AiDispatchResult> queueApplication(
    String jobId, {
    bool fromScratch = false,
  }) {
    generated = true;
    freshRequested = fromScratch;
    return super.queueApplication(jobId, fromScratch: fromScratch);
  }
}

class _ApplyDecisionStore extends _EmptyJobStore {
  final applied = <String>[];
  final discarded = <String>[];
  @override
  Future<void> setApplicationStatus(
    String jobId,
    ApplicationStatus status, {
    required String actor,
    required String origin,
  }) async {
    expect(status, ApplicationStatus.applied);
    applied.add(jobId);
  }

  @override
  Future<void> setReviewState(
    String jobId,
    ReviewState state, {
    required String actor,
    required String origin,
  }) async {
    expect(state, ReviewState.discarded);
    discarded.add(jobId);
  }
}

class _HeaderExportHarness extends _DraftHarness {
  _HeaderExportHarness({this.succeed = false}) : super(reviewed: false);
  final bool succeed;
  List<Object>? exported;
  @override
  Future<String> exportApplication(
    String jobId,
    String materialId,
    ApplicationDocumentFormat format,
    ApplicationDocumentRenderer renderer,
  ) async {
    exported = [jobId, materialId, format];
    if (succeed) return '/test/Documents/CareerShopper';
    throw StateError('Fixture export stopped before browser launch.');
  }
}

class _MissingDraftHarness extends _DraftHarness {
  _MissingDraftHarness({super.status});
  @override
  Stream<ApplicationMaterials?> watchMaterials(String jobId) =>
      Stream.value(null);
}

class _ConfiguringAiHarnessStore extends _EmptyAiHarnessStore {
  final values = <String, Object>{'model': 'alpha', 'fast': false};
  bool saved = false;
  List<AcpConfigOption> options() => AcpConfigOption.parse([
    {
      'id': 'model',
      'name': 'Model',
      'type': 'select',
      'currentValue': values['model'],
      'options': [
        {'value': 'alpha', 'name': 'Alpha'},
        {'value': 'beta', 'name': 'Beta'},
      ],
    },
    if (values['model'] == 'beta')
      {
        'id': 'fast',
        'name': 'Fast mode',
        'type': 'boolean',
        'currentValue': values['fast'],
      },
  ]);
  @override
  Future<void> configureAgent(
    AcpConfigure configure, {
    String? profileId,
    String? conversationId,
  }) async {
    final session = AcpConfigurationSession(options(), (id, value) async {
      values[id] = value;
      return options();
    });
    await configure(session);
    saved = true;
    await session.close();
  }
}

class _RecordingAiHarnessStore extends _EmptyAiHarnessStore {
  AcpRegistryAgent? savedRegistryAgent;

  @override
  Future<AcpRegistrySnapshot> fetchRegistry({bool refresh = false}) async =>
      AcpRegistrySnapshot(
        agents: const [
          AcpRegistryAgent(
            id: 'codex-acp',
            name: 'Codex',
            version: '1.8.0',
            description: 'Codex adapter for ACP.',
            distribution: {
              'npx': {'package': '@agentclientprotocol/codex-acp@1.8.0'},
            },
          ),
        ],
        fetchedAt: DateTime.utc(2026, 9, 4),
        fromCache: false,
      );

  @override
  Future<String> saveRegistryAgent(AcpRegistryAgent agent) async {
    savedRegistryAgent = agent;
    return 'harness';
  }
}

class _DispatchRecordingAiHarnessStore extends _EmptyAiHarnessStore {
  String? dispatchedJobId;

  @override
  Future<AiDispatchResult> dispatchManualImport(String jobId) async {
    dispatchedJobId = jobId;
    return const AiDispatchResult(
      workOrderId: 'work-order',
      profileName: 'Test harness',
      launched: true,
    );
  }
}

class _EmptyDocumentTemplateStore implements DocumentTemplateStore {
  static final template = ResumeTemplateDefinition(
    id: defaultResumeTemplateId,
    name: 'ATS Plain',
    isDefault: true,
    formatVersion: 1,
    settings: ResumeTemplateSettings.defaults(),
    updatedAt: DateTime.utc(2026, 9, 4),
  );

  @override
  Future<void> ensureDefaults() async {}

  @override
  Future<void> resetResumeTemplate(String id) async {}

  @override
  Future<void> saveResumeTemplate(ResumeTemplateDraft draft) async {}

  @override
  Stream<ResumeTemplateDefinition?> watchDefaultResumeTemplate() =>
      Stream.value(template);
}

class _RecordingDocumentTemplateStore extends _EmptyDocumentTemplateStore {
  ResumeTemplateDraft? savedDraft;

  @override
  Future<void> saveResumeTemplate(ResumeTemplateDraft draft) async {
    savedDraft = draft;
  }
}

class _EmptyProfileStore implements ProfileStore {
  @override
  Future<void> deleteCareerPreference(String id) async {}

  @override
  Future<void> retireCareerFact(String factId, {required String actor}) async {}

  @override
  Future<String> saveCareerFact(
    CareerFactDraft draft, {
    required String actor,
  }) async => 'fact';

  @override
  Future<String> saveCareerPreference(CareerPreferenceDraft draft) async =>
      'preference';

  @override
  Future<void> setFactVerificationStatus(
    String factId,
    String status, {
    required String actor,
  }) async {}

  @override
  Stream<List<CareerProfileFact>> watchCareerFacts() => Stream.value(const []);

  @override
  Stream<List<CareerPreferenceValue>> watchCareerPreferences() =>
      Stream.value(const []);
}

class _IdentityProfileStore extends _EmptyProfileStore {
  @override
  Stream<List<CareerProfileFact>> watchCareerFacts() => Stream.value([
    CareerProfileFact(
      id: 'resume',
      revisionId: 'resume-revision',
      kind: 'resume_content',
      value: {
        ...ResumeContent.empty(),
        'header': {
          'name': 'Alice Example',
          'contact': 'Boulder, Colorado · alice@example.test',
        },
      },
      verificationStatus: 'confirmed',
      visibility: 'resume',
      createdAt: DateTime.utc(2026, 9, 4),
    ),
    CareerProfileFact(
      id: 'identity-name',
      revisionId: 'identity-name-revision',
      kind: 'identity',
      value: const {'field': 'name', 'text': 'Alice Example'},
      verificationStatus: 'confirmed',
      visibility: 'resume',
      createdAt: DateTime.utc(2026, 9, 4),
    ),
    CareerProfileFact(
      id: 'identity-location',
      revisionId: 'identity-location-revision',
      kind: 'identity',
      value: const {'field': 'location', 'text': 'Boulder, Colorado'},
      verificationStatus: 'confirmed',
      visibility: 'resume',
      createdAt: DateTime.utc(2026, 9, 4),
    ),
    CareerProfileFact(
      id: 'identity-email',
      revisionId: 'identity-email-revision',
      kind: 'identity',
      value: const {'field': 'email', 'text': 'alice@example.test'},
      verificationStatus: 'confirmed',
      visibility: 'resume',
      createdAt: DateTime.utc(2026, 9, 4),
    ),
    CareerProfileFact(
      id: 'identity-private-phone',
      revisionId: 'identity-private-phone-revision',
      kind: 'identity',
      value: const {'field': 'phone', 'text': '555-0100'},
      verificationStatus: 'confirmed',
      visibility: 'private',
      createdAt: DateTime.utc(2026, 9, 4),
    ),
  ]);
}

class _EmptyConfigurationStore implements ConfigurationStore {
  @override
  Future<bool> clearSourceBlock(String id) async => false;
  @override
  Stream<List<SearchRunRecord>> watchSearchRuns({
    String? savedSearchId,
    int limit = 50,
  }) => Stream.value(const []);
  @override
  Future<void> deleteSavedSearch(String id) async {}

  @override
  Future<void> deleteSourceConfiguration(String id) async {}

  @override
  Future<SavedSearchRunResult> runSavedSearch(String id) async =>
      const SavedSearchRunResult([]);

  @override
  Future<String> saveSavedSearch(SavedSearchDraft draft) async => 'search';

  @override
  Future<String> saveSourceConfiguration(
    SourceConfigurationDraft draft,
  ) async => 'source';

  @override
  Future<void> setSavedSearchEnabled(String id, bool enabled) async {}

  @override
  Future<void> setSourceConfigurationEnabled(String id, bool enabled) async {}

  @override
  Stream<List<SavedSearchDefinition>> watchSavedSearches() =>
      Stream.value(const []);

  @override
  Stream<List<SourceConfiguration>> watchSourceConfigurations() =>
      Stream.value(const []);
}

class _PurposeAiHarnessStore extends _EmptyAiHarnessStore {
  final assignments = <(AiAgentPurpose, String?)>[];
  final duplicates = <(String, String)>[];
  @override
  Future<void> setPurposeProfile(AiAgentPurpose purpose, String? id) async {
    assignments.add((purpose, id));
  }

  @override
  Future<String> duplicateProfile(String id, String name) async {
    duplicates.add((id, name));
    return 'copy';
  }

  @override
  Stream<List<AiHarnessProfile>> watchProfiles() => Stream.value([
    for (final (id, name) in [('writer', 'Writer'), ('fast', 'Fast matcher')])
      AiHarnessProfile(
        id: id,
        name: name,
        executable: '/bin/true',
        arguments: const [],
        protocol: 'acp_stdio',
        isDefault: id == 'writer',
        updatedAt: DateTime(2026),
      ),
  ]);
}

class _SearchAnalysisHarness extends _EmptyAiHarnessStore {
  List<String> analyzedIds = [];
  @override
  Future<int> dispatchSearchAnalysis(List<String> jobIds) async {
    analyzedIds = jobIds;
    return jobIds.length;
  }

  @override
  Stream<List<AiHarnessProfile>> watchProfiles() => Stream.value([
    AiHarnessProfile(
      id: 'test',
      name: 'Test',
      executable: '/bin/true',
      arguments: [],
      protocol: 'acp_stdio',
      isDefault: true,
      updatedAt: DateTime.utc(2026),
    ),
  ]);
}

class _PausedSearchConfigurationStore extends _EmptyConfigurationStore {
  final runIds = <String>[];
  final enabledChanges = <bool>[];

  @override
  Stream<List<SavedSearchDefinition>> watchSavedSearches() => Stream.value([
    const SavedSearchDefinition(
      id: 'paused-search',
      name: 'Backend',
      enabled: false,
      pollIntervalMinutes: 60,
      scoreThreshold: 70,
      query: SavedSearchQuery(name: 'Backend'),
      sourceConfigIds: {},
    ),
  ]);

  @override
  Future<SavedSearchRunResult> runSavedSearch(String id) async {
    runIds.add(id);
    return const SavedSearchRunResult([
      SourceRunResult(
        sourceName: 'Test',
        status: 'succeeded',
        candidateJobIds: ['new-job'],
      ),
    ]);
  }

  @override
  Future<void> setSavedSearchEnabled(String id, bool enabled) async {
    enabledChanges.add(enabled);
  }
}

class _BlockedSourceConfigurationStore extends _PausedSearchConfigurationStore {
  final changes = StreamController<List<SourceConfiguration>>.broadcast();
  final cleared = <String>[];
  bool blocked = true;
  List<SourceConfiguration> get sources => [
    SourceConfiguration(
      id: 'blocked',
      sourceFamily: 'indeed',
      adapterId: 'indeed_public_search_v1',
      enabled: false,
      values: const {'country_site': 'www.indeed.com'},
      healthState: blocked ? 'unavailable' : 'not_checked',
      healthDetail: blocked ? 'Provider returned a CAPTCHA.' : null,
    ),
  ];

  @override
  Stream<List<SourceConfiguration>> watchSourceConfigurations() async* {
    yield sources;
    yield* changes.stream;
  }

  @override
  Stream<List<SavedSearchDefinition>> watchSavedSearches() => Stream.value([
    const SavedSearchDefinition(
      id: 'paused-search',
      name: 'Backend',
      enabled: false,
      pollIntervalMinutes: 60,
      scoreThreshold: 70,
      query: SavedSearchQuery(name: 'Backend'),
      sourceConfigIds: {'blocked'},
    ),
  ]);

  @override
  Future<bool> clearSourceBlock(String id) async {
    cleared.add(id);
    blocked = false;
    changes.add(sources);
    return true;
  }

  @override
  Future<void> setSourceConfigurationEnabled(String id, bool enabled) async {
    enabledChanges.add(enabled);
  }
}

class _FailedSearchConfigurationStore extends _PausedSearchConfigurationStore {
  static const details = 'Provider denied access (HTTP 403).';
  static const diagnostics = {
    'requests': [
      {'http_status': 403, 'url': 'https://apis.indeed.com/graphql'},
    ],
  };

  @override
  Future<SavedSearchRunResult> runSavedSearch(String id) async =>
      const SavedSearchRunResult([
        SourceRunResult(
          sourceName: 'Indeed',
          status: 'failed',
          detail: details,
          diagnostics: diagnostics,
        ),
      ]);

  @override
  Stream<List<SearchRunRecord>> watchSearchRuns({
    String? savedSearchId,
    int limit = 50,
  }) => Stream.value([
    SearchRunRecord(
      id: 'failed',
      savedSearchId: 'paused-search',
      sourceName: 'Indeed',
      status: 'failed',
      startedAt: DateTime(2026, 9, 8),
      observations: 0,
      detail: details,
      diagnostics: diagnostics,
    ),
  ]);
}

class _PartialSearchConfigurationStore extends _PausedSearchConfigurationStore {
  @override
  Stream<List<SearchRunRecord>> watchSearchRuns({
    String? savedSearchId,
    int limit = 50,
  }) => Stream.value([
    SearchRunRecord(
      id: 'partial',
      savedSearchId: 'paused-search',
      sourceName: 'Indeed',
      status: 'warning',
      startedAt: DateTime(2026),
      observations: 100,
      detail: 'Search completed. 93 records processed; 7 skipped.',
      diagnostics: const {
        'normalization_failures': 7,
        'warnings': [],
        'requests': [
          {
            'request': {
              'method': 'POST',
              'body': {'query': 'actual query'},
            },
            'response': {
              'status': 200,
              'body': {'results': []},
            },
          },
        ],
      },
    ),
  ]);
}

class _RecordingConfigurationStore extends _EmptyConfigurationStore {
  _RecordingConfigurationStore({this.existing});
  final SavedSearchDefinition? existing;
  SavedSearchDraft? savedDraft;

  @override
  Stream<List<SavedSearchDefinition>> watchSavedSearches() =>
      Stream.value([?existing]);

  @override
  Stream<List<SourceConfiguration>> watchSourceConfigurations() =>
      Stream.value([
        const SourceConfiguration(
          id: 'test-source',
          sourceFamily: 'linkedin',
          adapterId: 'linkedin_guest_search_v1',
          enabled: true,
          values: {},
          healthState: 'not_checked',
        ),
      ]);

  @override
  Future<String> saveSavedSearch(SavedSearchDraft draft) async {
    savedDraft = draft;
    return 'search';
  }
}

class _StatisticsJobStore extends _EmptyJobStore {
  DateTime? since;

  @override
  Stream<JobStatistics> watchStatistics({DateTime? changedSince}) {
    since = changedSince;
    return Stream.value(
      changedSince == null
          ? const JobStatistics(
              found: 120,
              applied: 30,
              interviewed: 12,
              offers: 3,
            )
          : const JobStatistics(
              found: 0,
              applied: 0,
              interviewed: 0,
              offers: 0,
            ),
    );
  }
}

class _BlockedEmployerJobStore extends _EmptyJobStore {
  final employers = StreamController<List<EmployerRow>>();
  String? unblockedId;

  @override
  Stream<List<EmployerRow>> watchBlockedEmployers() async* {
    yield [
      EmployerRow(
        id: 'blocked',
        displayName: 'Example employer',
        normalizedName: 'example employer',
        blockedAt: DateTime(2026),
        blockReason: 'Not a suitable employer',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    yield* employers.stream;
  }

  @override
  Future<void> setEmployerBlocked(
    String employerId, {
    required bool blocked,
    required String actor,
    required String origin,
    String? reason,
  }) async {
    expect(blocked, false);
    expect(actor, 'user');
    unblockedId = employerId;
    employers.add([]);
  }
}

class _EmptyJobStore implements JobStore {
  @override
  Stream<List<EmployerRow>> watchBlockedEmployers() => Stream.value([]);
  @override
  Future<ListingAvailabilityResult> checkAvailability(String jobId) async =>
      const ListingAvailabilityResult(
        'inconclusive',
        'No closure message.',
        '',
      );
  @override
  Future<void> clearAvailabilityBlock(String jobId) async {}
  @override
  Stream<String> watchJobNotes(String jobId) => Stream.value('');
  @override
  Future<void> saveJobNotes(
    String jobId,
    String notes, {
    required String expectedNotes,
  }) async {}
  @override
  Stream<JobStatistics> watchStatistics({DateTime? changedSince}) =>
      Stream.value(
        const JobStatistics(found: 0, applied: 0, interviewed: 0, offers: 0),
      );

  ApplicationOutcome? recordedOutcome;
  @override
  Future<void> setApplicationOutcome(
    String jobId,
    ApplicationOutcome outcome, {
    required String actor,
    required String origin,
  }) async {
    recordedOutcome = outcome;
  }

  @override
  Future<void> setApplicationStatus(
    String jobId,
    ApplicationStatus status, {
    required String actor,
    required String origin,
  }) async {}
  @override
  Future<String> queueManualUrl(Uri url) async => 'queued';

  @override
  Future<void> setEmployerBlocked(
    String employerId, {
    required bool blocked,
    required String actor,
    required String origin,
    String? reason,
  }) async {}

  @override
  Future<void> setReviewState(
    String jobId,
    ReviewState state, {
    required String actor,
    required String origin,
  }) async {}

  @override
  Stream<List<InboxJob>> watchAllJobs() => Stream.value(const []);

  @override
  Stream<List<InboxJob>> watchInbox() => Stream.value(const []);
}

class _ApprovedAppliedJobStore extends _EmptyJobStore {
  _ApprovedAppliedJobStore({
    this.status = ApplicationStatus.applied,
    this.readyToApply = false,
    this.outcome = ApplicationOutcome.active,
    this.aiError,
  });
  final String? aiError;
  final ApplicationStatus status;
  final bool readyToApply;
  final ApplicationOutcome outcome;
  @override
  Stream<List<InboxJob>> watchInbox() => Stream.value([
    InboxJob(
      id: 'approved-job',
      applicationUrl: Uri.parse('https://example.test/job'),
      title: 'Engineer',
      employerName: 'Example',
      location: 'Remote',
      description: 'Build systems.',
      availability: JobAvailability.open,
      reviewState: ReviewState.approved,
      applicationStatus: status,
      readyToApply: readyToApply,
      applicationOutcome: outcome,
      aiError: aiError,
      observedAt: DateTime.utc(2026, 9, 4),
    ),
  ]);
}

class _ContextJobStore extends _OneJobStore {
  String notes = '';
  final noteChanges = StreamController<String>.broadcast();
  @override
  Stream<String> watchJobNotes(String jobId) async* {
    yield notes;
    yield* noteChanges.stream;
  }

  @override
  Future<void> saveJobNotes(
    String jobId,
    String value, {
    required String expectedNotes,
  }) async {
    expect(jobId, 'job-1');
    expect(expectedNotes, notes);
    notes = value;
    noteChanges.add(value);
  }
}

class _KeyboardChatHarness extends _ContextHarnessStore {
  final newMessages = <String>[];
  @override
  Future<String> startConversation(
    String message, {
    List<ChatImage> images = const [],
  }) async {
    newMessages.add(message);
    return 'new-chat';
  }
}

class _ContextHarnessStore extends _EmptyAiHarnessStore {
  String? watchedJob;
  final started = <(String, String, String?)>[];
  final sent = <(String, String)>[];
  final sentImages = <List<ChatImage>>[];
  final changes = StreamController<List<AiConversation>>.broadcast();
  List<AiConversation> current = [
    AiConversation(
      id: 'analysis',
      title: 'Matching run',
      kind: 'search_analysis',
      status: 'completed',
      updatedAt: DateTime(2026),
    ),
  ];
  @override
  Stream<List<AiConversation>> watchConversations({String? jobId}) async* {
    watchedJob = jobId;
    yield current;
    yield* changes.stream;
  }

  @override
  Stream<List<AiActivityEntry>> watchActivity(String conversationId) =>
      Stream.value([
        AiActivityEntry(
          id: 'entry',
          role: 'assistant',
          kind: 'message',
          text: 'Prior remote assessment',
          status: 'completed',
          sequence: 1,
          updatedAt: DateTime(2026),
        ),
      ]);
  @override
  Future<String> startJobConversation(
    String jobId,
    String message, {
    String? contextConversationId,
    List<ChatImage> images = const [],
  }) async {
    started.add((jobId, message, contextConversationId));
    current = [
      AiConversation(
        id: 'discussion',
        title: 'Discuss Backend Engineer',
        kind: 'job_chat',
        jobId: jobId,
        status: 'completed',
        updatedAt: DateTime(2026),
      ),
      ...current,
    ];
    changes.add(current);
    return 'discussion';
  }

  @override
  Future<void> sendMessage(
    String conversationId,
    String message, {
    List<ChatImage> images = const [],
  }) async {
    sent.add((conversationId, message));
    sentImages.add(images);
  }
}

class _OneJobStore extends _EmptyJobStore {
  ApplicationStatus? recordedStatus;
  @override
  Future<void> setApplicationStatus(
    String jobId,
    ApplicationStatus status, {
    required String actor,
    required String origin,
  }) async {
    recordedStatus = status;
  }

  static final job = InboxJob(
    id: 'job-1',
    sourceFamily: 'linkedin',
    employerId: 'employer-1',
    title: 'Backend Engineer',
    employerName: 'Example',
    location: 'Remote',
    description: List.filled(80, 'Complete listing section.').join('\n'),
    applicationUrl: Uri.parse('https://jobs.example.test/1'),
    availability: JobAvailability.open,
    reviewState: ReviewState.inbox,
    applicationStatus: ApplicationStatus.notApplied,
    observedAt: DateTime.utc(2026, 9, 4),
    overallScore: 85,
    personalFitScore: 85,
    attainabilityScore: 85,
    evaluationSummary: 'Strong match.',
  );

  @override
  Stream<List<InboxJob>> watchAllJobs() => Stream.value([job]);

  @override
  Stream<List<InboxJob>> watchInbox() => Stream.value([job]);
}

InboxJob _queueJob(
  String id, {
  bool ready = false,
  String? title,
  String? employer,
  String? description,
}) => InboxJob(
  id: id,
  title: title ?? 'Job $id',
  employerName: employer ?? 'Example',
  location: 'Remote',
  description: description ?? 'Description for $id',
  applicationUrl: Uri.parse('https://example.test/$id'),
  availability: JobAvailability.open,
  reviewState: ready ? ReviewState.approved : ReviewState.inbox,
  applicationStatus: ApplicationStatus.notApplied,
  readyToApply: ready,
  observedAt: DateTime.utc(2026, 9, 7),
);

class _InboxQueueStore extends _EmptyJobStore {
  List<InboxJob> current = [
    _queueJob('one'),
    _queueJob('two'),
    _queueJob('three'),
  ];
  late final StreamController<List<InboxJob>> _changes =
      StreamController<List<InboxJob>>.broadcast(
        onListen: () => _changes.add(current),
      );
  void update(List<InboxJob> jobs) {
    current = jobs;
    _changes.add(current);
  }

  Future<void> close() => _changes.close();
  @override
  Stream<List<InboxJob>> watchInbox() async* {
    yield current;
    yield* _changes.stream;
  }

  @override
  Stream<List<InboxJob>> watchAllJobs() => Stream.value(current);
}

class _ViewSwitchInboxStore extends _InboxQueueStore {
  @override
  Stream<List<InboxJob>> watchAllJobs() => Stream.value([_queueJob('outside')]);
}

class _DelayedInboxStore extends _InboxQueueStore {
  Completer<List<InboxJob>>? pending;
  @override
  Stream<List<InboxJob>> watchInbox() =>
      pending == null ? super.watchInbox() : Stream.fromFuture(pending!.future);
}

class _InboxQueueHarness extends _EmptyAiHarnessStore {
  _InboxQueueHarness(this.jobs);
  final _InboxQueueStore jobs;
  final approved = <String>[];
  @override
  Future<AiDispatchResult> queueApplication(
    String jobId, {
    bool fromScratch = false,
  }) async {
    approved.add(jobId);
    jobs.update(jobs.current.where((job) => job.id != jobId).toList());
    return const AiDispatchResult(
      workOrderId: 'order',
      profileName: 'Test',
      launched: true,
    );
  }

  @override
  Stream<ApplicationMaterials?> watchMaterials(String jobId) => Stream.value(
    ApplicationMaterials(
      id: 'docs-$jobId',
      resume: '# Example',
      coverLetter: '# Example',
      reviewed: false,
      createdAt: DateTime.utc(2026, 9, 7),
    ),
  );
}

class _RunningChatHarness extends _ContextHarnessStore {
  _RunningChatHarness() {
    _status('running');
  }
  final interrupted = <String>[];
  Completer<void>? stopping;
  void _status(String status) {
    current = [
      AiConversation(
        id: 'discussion',
        title: 'Discuss remote requirements',
        kind: 'job_chat',
        jobId: 'job-1',
        status: status,
        updatedAt: DateTime(2026),
      ),
    ];
    changes.add(current);
  }

  @override
  Future<void> interruptConversation(String conversationId) async {
    interrupted.add(conversationId);
    await stopping?.future;
    _status('interrupted');
  }
}

class _StreamingTranscriptHarness extends _EmptyAiHarnessStore {
  final activity = StreamController<List<AiActivityEntry>>.broadcast();
  List<AiActivityEntry> entries(int count, int lastLines) => List.generate(
    count,
    (i) => AiActivityEntry(
      id: '$i',
      role: 'assistant',
      kind: 'message',
      text: List.filled(
        i == count - 1 ? lastLines : 3,
        'Message $i',
      ).join('\n'),
      status: null,
      sequence: i,
      updatedAt: DateTime(2026),
    ),
  );
  void update(int count, {int lastLines = 3}) =>
      activity.add(entries(count, lastLines));
  @override
  Stream<List<AiActivityEntry>> watchActivity(String conversationId) async* {
    yield entries(30, 3);
    yield* activity.stream;
  }
}

class _RetryChatHarness extends _ContextHarnessStore {
  _RetryChatHarness(String status) {
    current = [
      AiConversation(
        id: 'failed-materials',
        jobId: _OneJobStore.job.id,
        title: 'Draft application',
        kind: 'application_materials',
        status: status,
        updatedAt: DateTime(2026),
      ),
    ];
  }
  final freshJobs = <String>[];
  @override
  Future<AiDispatchResult> queueApplication(
    String jobId, {
    bool fromScratch = false,
  }) async {
    if (fromScratch) freshJobs.add(jobId);
    current = [
      AiConversation(
        id: 'fresh-generation',
        title: 'Fresh application',
        kind: 'application_materials',
        jobId: jobId,
        status: 'completed',
        updatedAt: DateTime.now(),
      ),
      ...current,
    ];
    changes.add(current);
    return const AiDispatchResult(
      workOrderId: 'fresh-generation',
      profileName: 'Writer',
      launched: true,
    );
  }

  final retried = <String>[];
  final resuming = Completer<void>();
  @override
  Future<void> resumeMaterialGeneration(String conversationId) async {
    retried.add(conversationId);
    await resuming.future;
  }
}
