import 'dart:io';

import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/documents/document_prompt.dart';
import 'package:careershopper/src/storage/document_template_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late DocumentTemplateRepository repository;

  setUp(() {
    database = CareerShopperDatabase(NativeDatabase.memory());
    repository = DocumentTemplateRepository(database);
  });

  tearDown(() => database.close());

  test(
    'upgrades historical defaults while preserving user edits and layout',
    () async {
      final legacy = File(
        'test/fixtures/legacy_document_prompt.txt',
      ).readAsStringSync();
      await repository.ensureDefaults();
      for (final prompt in [
        legacy,
        legacy.replaceAll('\n', '\r\n'),
        legacy.replaceAll(' ', '  '),
        '$legacy\nCustom instructions.',
      ]) {
        for (final order in [
          ResumeTemplateSettings.legacyDefaults().sectionOrder,
          ['experience', 'projects'],
        ]) {
          await repository.saveResumeTemplate(
            ResumeTemplateDraft(
              id: defaultResumeTemplateId,
              name: 'Custom layout',
              settings: ResumeTemplateSettings.fromJson({
                ...ResumeTemplateSettings.defaults().toJson(),
                'generation_prompt': prompt,
                'body_font_size': 11.0,
                'section_order': order,
              }),
            ),
          );
          await repository.ensureDefaults();
          final saved = (await repository.watchDefaultResumeTemplate().first)!;
          final custom = prompt.contains('Custom instructions.');
          expect(
            saved.settings.generationPrompt,
            custom ? prompt : defaultDocumentGenerationPrompt,
          );
          expect(saved.settings.bodyFontSize, 11.0);
          expect(saved.name, 'Custom layout');
          expect(
            saved.settings.sectionOrder,
            !custom && order.first == 'summary'
                ? ResumeTemplateSettings.defaults().sectionOrder
                : order,
          );
        }
      }
    },
  );

  test('letter defaults do not alter resume or customized layout values', () {
    final resume = ResumeTemplateSettings.defaults();
    final letter = resume.forCoverLetter();
    expect(letter.bodyFontSize, 10);
    expect(letter.lineSpacing, 1.12);
    expect(letter.paragraphSpacing, 8);
    expect(letter.marginTop, 0.7);
    expect(letter.marginLeft, 0.78);
    expect(letter.pageNumbers, false);
    expect(resume.bodyFontSize, 9.3);
    expect(resume.pageNumbers, true);
    final custom = ResumeTemplateSettings.fromJson({
      ...resume.toJson(),
      'font_family': 'Liberation Sans',
      'body_font_size': 11.0,
      'line_spacing': 1.2,
      'paragraph_spacing': 6.0,
      'margin_left': 0.9,
    }).forCoverLetter();
    expect(custom.fontFamily, 'Liberation Sans');
    expect(custom.bodyFontSize, 11);
    expect(custom.lineSpacing, 1.2);
    expect(custom.paragraphSpacing, 6);
    expect(custom.marginLeft, 0.9);
    expect(
      ResumeTemplateSettings.legacyDefaults().forCoverLetter().paragraphSpacing,
      10,
    );
  });

  test(
    'upgrades untouched old defaults but preserves custom templates and prompts',
    () async {
      await repository.ensureDefaults();
      await repository.saveResumeTemplate(
        ResumeTemplateDraft(
          id: defaultResumeTemplateId,
          name: 'ATS Plain',
          settings: ResumeTemplateSettings.legacyDefaults(),
        ),
      );
      await repository.ensureDefaults();
      expect(
        (await repository.watchDefaultResumeTemplate().first)!.settings.layout,
        'pipeline-v1',
      );
      await repository.saveResumeTemplate(
        ResumeTemplateDraft(
          id: defaultResumeTemplateId,
          name: 'Mine',
          settings: ResumeTemplateSettings.fromJson({
            ...ResumeTemplateSettings.legacyDefaults().toJson(),
            'generation_prompt': 'My wording instructions',
          }),
        ),
      );
      await repository.ensureDefaults();
      final saved = (await repository.watchDefaultResumeTemplate().first)!;
      expect(saved.name, 'Mine');
      expect(saved.settings.layout, 'classic');
      expect(saved.settings.generationPrompt, 'My wording instructions');
    },
  );

  test('creates the default editable resume template', () async {
    await repository.ensureDefaults();

    final template = await repository.watchDefaultResumeTemplate().first;
    expect(template, isNotNull);
    expect(template!.id, defaultResumeTemplateId);
    expect(template.name, 'Pipeline Classic');
    expect(template.settings.layout, 'pipeline-v1');
    expect(template.settings.bodyFontSize, 9.3);
    expect(template.settings.marginTop, 0.52);
    expect(template.settings.fontFamily, 'Arial');
    expect(template.settings.sectionOrder, contains('experience'));
  });

  test('saves template settings and records an audit event', () async {
    await repository.ensureDefaults();
    final current = (await repository.watchDefaultResumeTemplate().first)!;
    final settings = ResumeTemplateSettings.fromJson({
      ...current.settings.toJson(),
      'font_family': 'Liberation Sans',
      'body_font_size': 10.5,
      'margin_top': 0.75,
      'section_order': ['summary', 'experience', 'skills'],
      'generation_prompt': 'Lead with architecture and product outcomes.',
    });

    await repository.saveResumeTemplate(
      ResumeTemplateDraft(
        id: current.id,
        name: 'My Resume',
        settings: settings,
      ),
    );

    final saved = (await repository.watchDefaultResumeTemplate().first)!;
    expect(saved.name, 'My Resume');
    expect(
      saved.settings.generationPrompt,
      'Lead with architecture and product outcomes.',
    );
    expect(saved.settings.fontFamily, 'Liberation Sans');
    expect(saved.settings.bodyFontSize, 10.5);
    expect(saved.settings.marginTop, 0.75);
    expect(saved.settings.sectionOrder, ['summary', 'experience', 'skills']);
    expect(await database.select(database.auditEvents).get(), hasLength(1));
  });

  test('reset restores Pipeline Classic defaults', () async {
    await repository.ensureDefaults();
    final current = (await repository.watchDefaultResumeTemplate().first)!;
    await repository.saveResumeTemplate(
      ResumeTemplateDraft(
        id: current.id,
        name: 'Changed',
        settings: ResumeTemplateSettings.fromJson({
          ...current.settings.toJson(),
          'font_family': 'Serif',
        }),
      ),
    );

    await repository.resetResumeTemplate(current.id);

    final reset = (await repository.watchDefaultResumeTemplate().first)!;
    expect(reset.name, 'Pipeline Classic');
    expect(reset.settings.fontFamily, 'Arial');
  });
}
