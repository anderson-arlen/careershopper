import 'dart:async';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'package:careershopper/src/domain/interview.dart';
import 'package:careershopper/src/features/interviews/interviews_panel.dart';
import 'package:careershopper/src/storage/ai_harness_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/interview_repository.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/interview_data.dart';

class _Harness implements AiHarnessStore {
  @override
  Stream<List<AiHarnessProfile>> watchProfiles() => Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CareerShopperDatabase db;
  late InterviewRepository repo;
  late String job;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    repo = InterviewRepository(db);
    job = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/ui'));
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> show(
    WidgetTester tester, {
    Future<void> Function()? onPrepare,
  }) async {
    if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_INTERVIEW_UI')) {
      await tester.runAsync(() async {
        final font = FontLoader('InterviewPreview')
          ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await font.load();
        await icons.load();
      });
    }
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'InterviewPreview',
          colorSchemeSeed: const Color(0xff335c67),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: Material(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: InterviewsPanel(
                  jobId: job,
                  jobTitle: 'Example engineer',
                  repository: repo,
                  harnesses: _Harness(),
                  onPrepare: onPrepare ?? () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openSection(WidgetTester tester, String name) async {
    final chip = find.widgetWithText(ChoiceChip, name);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('stage flow opens date/time and status controls', (tester) async {
    await tester.runAsync(
      () => repo.saveStages(job, 0, [
        {
          ...newInterviewStage('screen', 'Recruiter screen'),
          'status': 'completed',
        },
        {
          ...newInterviewStage('technical', 'Technical interview'),
          'status': 'scheduled',
          'scheduled_at': DateTime(2099, 4, 1, 10).toUtc().toIso8601String(),
        },
        newInterviewStage('manager', 'Hiring manager'),
      ]),
    );
    await show(tester);
    expect(find.text('Interview stages'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2));
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Not scheduled'), findsOneWidget);
    expect(find.text('Date not recorded'), findsOneWidget);
    if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_INTERVIEW_UI')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/careershopper-interview-schedule.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byKey(const ValueKey('interview-stage-technical')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change date and time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save stage'));
    await tester.pumpAndSettle();
    var saved = await tester.runAsync(() => repo.get(job));
    var technical = interviewMaps(saved!['ladder'])[1];
    expect(interviewStageStart(technical)!.toLocal(), DateTime(2099, 4, 2, 10));
    expect(technical['status'], 'scheduled');
    await tester.tap(find.byKey(const ValueKey('interview-stage-technical')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Stage status'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save stage'));
    await tester.pumpAndSettle();
    saved = await tester.runAsync(() => repo.get(job));
    technical = interviewMaps(saved!['ladder'])[1];
    expect(technical['status'], 'completed');
    expect(interviewMap(saved['current_stage'])['id'], 'manager');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('overview guides voice practice without creating a session', (
    tester,
  ) async {
    await tester.runAsync(
      () => repo.submitPreparation(job, 0, interviewIntel(), interviewBank()),
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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
    await show(tester);
    expect(find.text('Current stage: Technical interview'), findsOneWidget);
    expect(find.textContaining('Enable voice'), findsOneWidget);
    expect(find.text('Describe a technical tradeoff you made.'), findsNothing);
    expect(find.text('Application context'), findsNothing);
    expect(find.text('Practice history'), findsNothing);
    await tester.tap(find.text('Copy practice request'));
    await tester.pumpAndSettle();
    expect(
      copied,
      "Let's practice my interview for Example engineer.\nCareerShopper job ID: $job",
    );
    final history = await tester.runAsync(() => repo.practices(jobId: job));
    expect(history!['practices'], isEmpty);
    await tester.ensureVisible(find.text('Connect your harness'));
    await tester.tap(find.text('Connect your harness'));
    await tester.pumpAndSettle();
    expect(find.textContaining('make mcp-info'), findsOneWidget);
    await openSection(tester, 'Question bank');
    expect(
      find.text('Describe a technical tradeoff you made.'),
      findsOneWidget,
    );
    await openSection(tester, 'Progress');
    expect(find.text('Practice history'), findsOneWidget);
    expect(find.text('Describe a technical tradeoff you made.'), findsNothing);
    await openSection(tester, 'Settings');
    expect(find.text('Application context'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final automatic in [true, false]) {
    testWidgets(
      'practice setup uses current stage and ${automatic ? 'automatic' : 'fixed'} difficulty',
      (tester) async {
        await tester.runAsync(
          () =>
              repo.submitPreparation(job, 0, interviewIntel(), interviewBank()),
        );
        await show(tester);
        await tester.ensureVisible(find.text('Customize practice'));
        await tester.tap(find.text('Customize practice'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Current stage: Technical interview'),
          ),
          findsOneWidget,
        );
        expect(find.byType(Slider), findsNothing);
        if (!automatic) {
          await tester.tap(find.text('Increase difficulty as I practice'));
          await tester.pumpAndSettle();
          tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
          await tester.pump();
        }
        await tester.runAsync(() async {
          await tester.tap(find.text('Create practice'));
          for (var i = 0; i < 100; i++) {
            await tester.pump();
            if (find.text('Practice · active').evaluate().isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Difficulty: ${automatic ? 2 : 4} / 5 · ${automatic ? 'automatic' : 'fixed'}',
          ),
          findsOneWidget,
        );
        final saved = await tester.runAsync(() => repo.practices(jobId: job));
        final practice = interviewMaps(saved!['practices']).single;
        expect(practice['stage_id'], 'technical');
        expect(
          interviewMap(practice['settings'])['difficulty'],
          automatic ? 2 : 4,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('intel report displays a cached company logo', (tester) async {
    await tester.runAsync(() async {
      final now = DateTime.utc(2026);
      await db
          .into(db.employers)
          .insert(
            EmployersCompanion.insert(
              id: 'company',
              displayName: 'Example Company',
              normalizedName: 'example company',
              logoPng: Value(
                Uint8List.fromList(
                  img.encodePng(img.Image(width: 32, height: 16)),
                ),
              ),
              logoSourceUrl: const Value('https://example.test/logo.png'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(db.jobs)..where((r) => r.id.equals(job))).write(
        const JobsCompanion(employerId: Value('company')),
      );
      await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
    });
    await show(tester);
    final logo = find.byWidgetPredicate(
      (w) => w is Image && w.semanticLabel == 'Example Company logo',
    );
    expect(logo, findsOneWidget);
    expect(tester.widget<Image>(logo).image, isA<MemoryImage>());
    expect(
      tester.getTopLeft(logo).dy,
      lessThan(tester.getTopLeft(find.text('Company and interview intel')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'research shows immediate dispatch and live saved status transitions',
    (tester) async {
      await tester.runAsync(
        () => repo.submitPreparation(job, 0, interviewIntel(), interviewBank()),
      );
      final dispatch = Completer<void>();
      var calls = 0;
      await show(
        tester,
        onPrepare: () {
          calls++;
          return dispatch.future;
        },
      );
      await tester.ensureVisible(find.text('Refresh research'));
      await tester.tap(find.text('Refresh research'));
      await tester.pump();
      expect(find.text('Starting research…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Starting research…'),
            )
            .onPressed,
        isNull,
      );
      Future<void> state(String value, {String? error}) async {
        await tester.runAsync(
          () => db
              .update(db.interviewWorkspaces)
              .write(
                InterviewWorkspacesCompanion(
                  preparationState: Value(value),
                  preparationError: Value(error),
                ),
              ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }

      await state('queued');
      dispatch.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Research queued…'), findsOneWidget);
      await state('running');
      expect(find.text('Research in progress…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(calls, 1);
      await tester.runAsync(
        () => db
            .into(db.aiWorkOrders)
            .insert(
              AiWorkOrdersCompanion.insert(
                id: 'research',
                jobId: Value(job),
                kind: 'interview_preparation',
                status: 'running',
                scopeJson: '{}',
                promptVersion: 'test',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
      );
      await state('ready');
      expect(find.text('Research in progress…'), findsOneWidget);
      expect(find.text('Refresh research'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Research in progress…'),
            )
            .onPressed,
        isNull,
      );
      // Completion changes only the work order; no packet write is needed.
      await tester.runAsync(
        () => db
            .update(db.aiWorkOrders)
            .write(const AiWorkOrdersCompanion(status: Value('completed'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Research ready'), findsOneWidget);
      expect(find.text('Refresh research'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await state('failed', error: 'Agent disconnected');
      expect(find.text('Research failed. Retry to continue.'), findsOneWidget);
      expect(find.text('Agent disconnected'), findsOneWidget);
      await state('paused');
      expect(find.text('Research paused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'automatic preparation defaults on and can be disabled before agent setup',
    (tester) async {
      await show(tester);
      await openSection(tester, 'Settings');
      await tester.tap(find.text('Automatic preparation'));
      await tester.pumpAndSettle();
      expect(find.text('Use default agent'), findsWidgets);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.text('Prepare interviews automatically'));
      await tester.pumpAndSettle();
      expect((await repo.settings())['auto_prepare'], false);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('question editor saves prerequisites by question label', (
    tester,
  ) async {
    await tester.runAsync(
      () => repo.submitPreparation(job, 0, interviewIntel(), interviewBank()),
    );
    await show(tester);
    await openSection(tester, 'Question bank');
    await tester.ensureVisible(find.text('Add question'));
    await tester.tap(find.text('Add question'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Question or exercise'),
      'Extend the previous design.',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Topic'), 'Design');
    await tester.ensureVisible(find.text('Prerequisite questions'));
    await tester.tap(find.text('Prerequisite questions'));
    await tester.pumpAndSettle();
    final prerequisite = find.widgetWithText(
      CheckboxListTile,
      'Describe a technical tradeoff you made.',
    );
    await tester.ensureVisible(prerequisite);
    await tester.tap(prerequisite);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save question'));
    await tester.pumpAndSettle();
    final added = interviewMaps(
      (await repo.questions(job))['questions'],
    ).singleWhere((q) => q['prompt'] == 'Extend the previous design.');
    expect(added['depends_on'], ['tradeoffs']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('empty workspace offers preparation and stage creation', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Prepare with AI'), findsOneWidget);
    expect(find.text('No current stage yet'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit interview stages'));
    await tester.tap(find.text('Edit interview stages'));
    await tester.pumpAndSettle();
    expect(find.text('Add stage'), findsOneWidget);
    await tester.ensureVisible(find.text('Add stage'));
    await tester.tap(find.text('Add stage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Stage name'),
      'Hiring manager',
    );
    await tester.tap(find.text('Save stage'));
    await tester.pumpAndSettle();
    expect(
      interviewMaps((await repo.get(job))['ladder']).single['name'],
      'Hiring manager',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'prepared workspace shows intel, questions, history and a chart',
    (tester) async {
      await tester.runAsync(() async {
        await repo.submitPreparation(job, 0, interviewIntel(), interviewBank());
        final practice = await repo.startPractice(
          job,
          'technical',
          'ui',
          practiceSettings(),
        );
        final id = practice['practice_id']! as String;
        await repo.saveExchange(id, 'line', -1, practiceExchange());
        await repo.setPracticeState(
          id,
          1,
          'completed',
          'Use a measurable example.',
        );
      });
      await show(tester);
      if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_INTERVIEW_UI')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/careershopper-interview-overview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.text('A technical discussion is reported.'), findsNothing);
      await tester.ensureVisible(find.text('More…'));
      await tester.tap(find.text('More…'));
      await tester.pumpAndSettle();
      expect(find.text('A technical discussion is reported.'), findsOneWidget);
      expect(find.widgetWithText(ExpansionTile, 'Process'), findsNothing);
      if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_INTERVIEW_UI')) {
        await tester.ensureVisible(find.text('Company and interview intel'));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/careershopper-intel-ui.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.ensureVisible(find.text('Less'));
      await tester.tap(find.text('Less'));
      await tester.pumpAndSettle();
      expect(find.text('A technical discussion is reported.'), findsNothing);
      expect(find.text('Refresh research'), findsOneWidget);
      await openSection(tester, 'Settings');
      expect(find.text('1. Technical interview'), findsOneWidget);
      await openSection(tester, 'Question bank');
      expect(
        find.text('Describe a technical tradeoff you made.'),
        findsOneWidget,
      );
      await openSection(tester, 'Progress');
      await tester.ensureVisible(find.text('Performance over time'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 completed session'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_INTERVIEW_UI')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/careershopper-interview-ui.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
