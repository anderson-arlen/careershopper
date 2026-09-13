import 'package:careershopper/src/features/profile/resume_content_editor.dart';
import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'storage/resume_content_test.dart' as fixture;

void main() {
  testWidgets(
    'personal context can be added without a resume section heading',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profile = EditorProfileStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      final add = find.text('Add personal context');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Interest, domain or credential'),
        'Gardening',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirmed details and any limitations'),
        'I volunteer in a community garden.',
      );
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save fixed wording'));
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final saved = profile.saved!.value as Map;
      expect((saved['personal_context'] as List).single['topic'], 'Gardening');
      expect(saved['headings'], isNot(contains('personal_context')));
    },
  );

  testWidgets(
    'core skills precede work history and compact sections expand without changing content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final content = ResumeContent(fixture.fixedContent());
      content.data['skills'] = [
        for (var i = 1; i <= 5; i++)
          {
            'id': 'skill-$i',
            'enabled': i != 5,
            'name': 'Skill $i',
            'proficiency': 'Working knowledge',
            'notes': 'Context for skill $i.',
          },
      ];
      for (var i = 3; i <= 5; i++) {
        (content.data['experience'] as List).add({
          'id': 'role-$i',
          'enabled': true,
          'employer': 'Employer $i',
          'location': '',
          'titles': [
            {'title': 'Engineer', 'dates': '2020', 'achievements': []},
          ],
        });
      }
      final profile = EditorProfileStore()
        ..saved = CareerFactDraft(
          kind: resumeContentKind,
          value: content.data,
          visibility: 'resume',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Skill 1'), findsOneWidget);
      expect(find.text('Skill 4'), findsNothing);
      expect(find.text('Employer 4'), findsNothing);
      expect(find.text('Context for skill 1.'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Skill 1')).dy,
        lessThan(tester.getTopLeft(find.text('Current Company')).dy),
      );
      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.byKey(const ValueKey('toggle-skills')));
      expect(find.text('Skill 5'), findsOneWidget);
      expect(find.text('Context for skill 1.'), findsOneWidget);
      await tapVisible(find.byKey(const ValueKey('toggle-experience')));
      expect(find.text('Employer 5'), findsOneWidget);
      expect(find.text('Implemented a search feature.'), findsOneWidget);
      await tapVisible(find.byKey(const ValueKey('toggle-skills')));
      expect(find.text('Skill 4'), findsNothing);
      expect((profile.saved!.value as Map)['skills'][4]['enabled'], false);
      expect(find.text('Unsaved changes'), findsNothing);
    },
  );

  testWidgets(
    'project details link inline, reorder with links intact and protect prerequisites',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final content = ResumeContent(fixture.fixedContent());
      content.entries('projects').first['details'] = [
        {'id': 'base', 'text': 'Built an API.'},
        {'id': 'rollout', 'text': 'Rolled it out incrementally.'},
      ];
      content.entries('projects').last['details'] = [
        {'id': 'other', 'text': 'Other project.'},
      ];
      final profile = EditorProfileStore()
        ..saved = CareerFactDraft(
          kind: resumeContentKind,
          value: content.data,
          visibility: 'resume',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.byKey(const ValueKey('detail-link-rollout')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Built an API.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('detail-link-other')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('achievement-link-ci')),
            )
            .onPressed,
        isNull,
      );
      await tapVisible(find.byKey(const ValueKey('detail-select-base')));
      await tester.tap(find.text('Done linking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      expect(
        (profile.saved!.value as Map)['projects'][0]['details'][1]['requires'],
        ['base'],
      );
      await tapVisible(find.byTooltip('Edit detail').at(1));
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      await tapVisible(find.byTooltip('Remove detail').first);
      expect(
        find.text('Detail is required by other sentences'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Drag the prerequisite to the end; links must follow its ID.
      final handle = find.byKey(const ValueKey('detail-drag-base'));
      await tester.ensureVisible(handle);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final target = find.byKey(const ValueKey('detail-end-project'));
      await tester.ensureVisible(target);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final details =
          (profile.saved!.value as Map)['projects'][0]['details'] as List;
      expect(details.map((d) => d['id']), ['rollout', 'base']);
      expect(details.first['requires'], ['base']);
      expect(find.byTooltip('Move detail up'), findsNothing);
      expect(find.byTooltip('Move detail down'), findsNothing);
      await tapVisible(find.byKey(const ValueKey('detail-link-rollout')));
      await tapVisible(find.byKey(const ValueKey('detail-select-base')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tapVisible(find.byTooltip('Remove detail').at(1));
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final remaining =
          (profile.saved!.value as Map)['projects'][0]['details'] as List;
      expect(remaining.single['id'], 'rollout');
      expect(remaining.single['requires'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'achievement links save and prerequisites cannot be deleted while linked',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profile = EditorProfileStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.byKey(const ValueKey('achievement-link-ci')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Done linking'), findsOneWidget);
      // Only the original bullet appears; selection uses that same row.
      expect(find.text('Implemented a search feature.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('achievement-link-report-achievement')),
            )
            .onPressed,
        isNull,
      );
      await tapVisible(find.byKey(const ValueKey('achievement-select-search-achievement')));
      expect(
        find.byKey(const ValueKey('achievement-link-search-achievement')),
        findsOneWidget,
      );
      // Existing links remain attached through scrolling and resizing.
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Done linking'), findsNothing);
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final achievements =
          (profile.saved!.value
                  as Map)['experience'][0]['titles'][0]['achievements']
              as List;
      expect(achievements[1]['requires'], ['search-achievement']);
      // Wording edits leave saved links intact and no longer duplicate bullets.
      await tapVisible(find.byTooltip('Edit achievement').at(1));
      expect(find.text('Requires other achievements'), findsNothing);
      expect(find.byKey(const ValueKey('requires-search-achievement')), findsNothing);
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      await tapVisible(find.byTooltip('Remove achievement').first);
      expect(
        find.text('Achievement is required by other bullets'),
        findsOneWidget,
      );
      expect(find.textContaining('Added automated checks.'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tapVisible(find.byKey(const ValueKey('achievement-link-ci')));
      await tapVisible(find.byKey(const ValueKey('achievement-select-search-achievement')));
      await tester.tap(find.text('Done linking'));
      await tester.pumpAndSettle();
      await tapVisible(find.byTooltip('Remove achievement').first);
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final remaining =
          (profile.saved!.value
                  as Map)['experience'][0]['titles'][0]['achievements']
              as List;
      expect(remaining, hasLength(1));
      expect(remaining.single['id'], 'ci');
      expect(remaining.single['requires'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dated title sections support dragging achievements within and between sections',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profile = EditorProfileStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find
          .byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Remove title',
          )
          .first;
      await tester.ensureVisible(remove);
      await tester.pump();
      expect(tester.widget<IconButton>(remove).onPressed, isNull);
      await tester.tap(find.byTooltip('Edit title').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Date range'),
        '2020 to Present',
      );
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add title').first);
      await tester.pump();
      await tester.tap(find.text('Add title').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Exact job title'),
        'Senior Developer',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Date range'),
        '2019 to 2020',
      );
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      expect(profile.saved, isNull);
      expect(find.text('Senior Developer'), findsOneWidget);
      Future<void> drag(String id, String destination) async {
        final source = find.byKey(ValueKey('achievement-drag-$id'));
        final target = find.byKey(ValueKey(destination));
        await tester.ensureVisible(source);
        await tester.pump();
        final gesture = await tester.startGesture(tester.getCenter(source));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        await tester.ensureVisible(target);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(target));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      // Reorder within a title, then move the same unchanged achievement
      // into the newly added title section.
      await drag('ci', 'achievement-drop-search-achievement');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('achievement-drop-ci'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('achievement-drop-search-achievement')))
              .dy,
        ),
      );
      await drag('ci', 'achievement-end-current-1');
      // A different employer is not a valid target.
      await drag('ci', 'achievement-end-previous-0');
      final chain = find.byKey(const ValueKey('achievement-link-ci'));
      await tester.ensureVisible(chain);
      await tester.pump();
      await tester.tap(chain);
      await tester.pumpAndSettle();
      final prerequisite = find.byKey(
        const ValueKey('achievement-select-search-achievement'),
      );
      await tester.ensureVisible(prerequisite);
      await tester.pump();
      await tester.tap(prerequisite);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done linking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      final roles = (profile.saved!.value as Map)['experience'] as List;
      expect(roles, hasLength(2));
      final titles = roles.first['titles'] as List;
      expect(titles, hasLength(2));
      expect(titles[0]['title'], 'Engineer');
      expect(titles[0]['dates'], '2020 to Present');
      expect(titles[0]['achievements'], [
        {'id': 'search-achievement', 'text': 'Implemented a search feature.'},
      ]);
      expect(titles[1]['title'], 'Senior Developer');
      expect(titles[1]['dates'], '2019 to 2020');
      expect(titles[1]['achievements'], [
        {
          'id': 'ci',
          'text': 'Added automated checks.',
          'requires': ['search-achievement'],
        },
      ]);
      expect(roles.last['titles'], hasLength(1));
      expect(roles.last['titles'][0]['achievements'], hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resume layout edits role achievements and projects without generic fact fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final profile = EditorProfileStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResumeContentEditor(profile: profile)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alex Example'), findsOneWidget);
      expect(find.text('AI-generated professional headline'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit resume header'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Professional headline'),
        findsNothing,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('TAILORED FOR EACH JOB'), findsOneWidget);
      expect(find.text('Structured value (JSON)'), findsNothing);
      final achievement = find.byTooltip('Edit achievement').first;
      await tester.ensureVisible(achievement);
      await tester.pump();
      await tester.tap(achievement);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Exact achievement wording'),
        'Implemented a searchable catalog.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Priority points'),
        '101',
      );
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a whole number from 0 to 100.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Priority points'),
        '85',
      );
      await tester.tap(find.text('Required when this job is included'));
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      expect(profile.saved, isNull);
      expect(find.text('Implemented a searchable catalog.'), findsOneWidget);
      expect(
        find.text('85 points · Required when this job is included'),
        findsOneWidget,
      );
      final project = find.byTooltip('Edit project').first;
      await tester.ensureVisible(project);
      await tester.pump();
      await tester.tap(project);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project summary (always included)'),
        'Exact user-owned project description.',
      );
      await tester.tap(find.text('Use wording'));
      await tester.pumpAndSettle();
      for (final text in ['Built an API in Go.', 'Stored data in SQLite.']) {
        final addDetail = find.text('Add detail sentence').first;
        await tester.ensureVisible(addDetail);
        await tester.pump();
        await tester.tap(addDetail);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Detail sentence (exact wording)'),
          text,
        );
        await tester.tap(find.text('Use wording'));
        await tester.pumpAndSettle();
      }
      final handle = find.byTooltip('Drag to move detail').at(1);
      await tester.ensureVisible(handle);
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final target = find.text('Built an API in Go.');
      await tester.ensureVisible(target);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save fixed wording'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final saved = profile.saved!.value as Map;
      expect(
        (saved['experience'] as List)
            .first['titles'][0]['achievements'][0]['text'],
        'Implemented a searchable catalog.',
      );
      expect(
        (saved['experience'] as List)
            .last['titles'][0]['achievements'][0]['text'],
        'Updated a reporting tool.',
      );
      expect(
        (saved['experience'] as List)
            .first['titles'][0]['achievements'][0]['priority'],
        85,
      );
      expect(
        (saved['experience'] as List)
            .first['titles'][0]['achievements'][0]['required'],
        true,
      );
      expect(
        (saved['projects'] as List).first['description'],
        'Exact user-owned project description.',
      );
      final details = (saved['projects'] as List).first['details'] as List;
      expect(details.map((d) => d['text']), [
        'Stored data in SQLite.',
        'Built an API in Go.',
      ]);
      expect(details.map((d) => d['id']).toSet(), hasLength(2));
      expect(profile.saved!.expectedRevisionId, 'revision');
    },
  );
}

class EditorProfileStore implements ProfileStore {
  CareerFactDraft? saved;
  @override
  Stream<List<CareerProfileFact>> watchCareerFacts() => Stream.value([
    CareerProfileFact(
      id: 'fixed',
      revisionId: saved == null ? 'revision' : 'next',
      kind: resumeContentKind,
      value: saved?.value ?? fixture.fixedContent(),
      verificationStatus: 'confirmed',
      visibility: 'resume',
      createdAt: DateTime(2026),
    ),
  ]);
  @override
  Future<String> saveCareerFact(
    CareerFactDraft draft, {
    required String actor,
  }) async {
    saved = draft;
    return 'fixed';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
