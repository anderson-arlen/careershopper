import 'dart:io';
import 'dart:ui' as ui;

import 'package:careershopper/src/features/documents/application_answers_panel.dart';
import 'package:careershopper/src/storage/application_answer_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('save, review, copy and update an application answer', (
    tester,
  ) async {
    final db = CareerShopperDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ApplicationAnswerRepository(db);
    final job = await JobRepository(
      db,
    ).queueManualUrl(Uri.parse('https://example.test/answers'));
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_ANSWERS_UI')) {
      await tester.runAsync(() async {
        final font = FontLoader('Preview')
          ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await font.load();
        await icons.load();
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'Preview',
          colorSchemeSeed: const Color(0xff80cfe0),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ApplicationAnswersPanel(jobId: job, repository: repo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No saved answers yet.'), findsOneWidget);
    await tester.tap(find.text('Save answer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Application question'),
      'Why this role?',
    );
    const original =
        'I enjoy making complex tools easier to use.\n\nThis role would let me focus on that work.';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Exact answer'),
      original,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await repo.list(job)).single.status, 'draft');
    await tester.tap(find.text('Why this role?'));
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);
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
    await tester.tap(find.text('Copy answer'));
    await tester.pumpAndSettle();
    expect(copied, original);
    await tester.tap(find.text('Edit answer'));
    await tester.pumpAndSettle();
    const finalText =
        'I enjoy making complex tools easier to use. This role would let me focus on developer workflows, building on my experience simplifying internal tools.';
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Exact answer'),
      finalText,
    );
    await tester.tap(find.text('I submitted this answer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = (await repo.list(job)).single;
    expect(saved.status, 'submitted');
    expect(saved.answer, finalText);
    expect(saved.revision, 2);
    expect(find.text(finalText), findsOneWidget);
    expect(find.textContaining('Submitted · Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAREERSHOPPER_CAPTURE_ANSWERS_UI')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/careershopper-application-answers.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
