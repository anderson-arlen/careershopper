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
    'generation instructions delegate assembly and use short IDs for prose support',
    () {
      expect(
        defaultDocumentGenerationPrompt,
        contains('structured resume_plan and cover_letter_plan'),
      );
      expect(
        defaultDocumentGenerationPrompt,
        contains('same short IDs from generation_content'),
      );
      expect(
        defaultDocumentGenerationPrompt,
        contains('write only the body paragraphs'),
      );
      expect(
        defaultDocumentGenerationPrompt,
        isNot(contains('### **Project Name**')),
      );
      expect(defaultDocumentGenerationPrompt, isNot(contains('<!-- facts:')));
    },
  );

  for (final previous in [
    (
      'company-aware structured plans',
      previousStructuredDocumentGenerationPrompt,
    ),
    ('structured document plans', previousMarkdownDocumentGenerationPrompt),
    (
      'regular-weight project stacks',
      previousBoldProjectStackDocumentGenerationPrompt,
    ),
    (
      'saved default with different paragraph spacing',
      File(
        'test/fixtures/document-prompt-descriptive-project-headings.txt',
      ).readAsStringSync(),
    ),
    (
      'saved default with Windows line endings',
      File(
        'test/fixtures/document-prompt-descriptive-project-headings.txt',
      ).readAsStringSync().replaceAll('\n', '\r\n'),
    ),
    (
      'concise project headings',
      previousDescriptiveProjectHeadingDocumentGenerationPrompt,
    ),
    ('shared-style split', previousCompactPatentDocumentGenerationPrompt),
    (
      'generalized headline',
      previousSpecializedHeadlineDocumentGenerationPrompt,
    ),
  ]) {
    test('${previous.$1} upgrades only untouched prompts', () async {
      await repository.ensureDefaults();
      for (final custom in [false, true]) {
        final prompt =
            previous.$2 + (custom ? '\nMy custom instructions.' : '');
        await repository.saveResumeTemplate(
          ResumeTemplateDraft(
            id: defaultResumeTemplateId,
            name: 'My template',
            settings: ResumeTemplateSettings.fromJson({
              ...ResumeTemplateSettings.defaults().toJson(),
              'generation_prompt': prompt,
              'body_font_size': 11.0,
            }),
          ),
        );
        await repository.ensureDefaults();
        final saved = (await repository.watchDefaultResumeTemplate().first)!;
        expect(
          saved.settings.generationPrompt,
          custom ? prompt : defaultDocumentGenerationPrompt,
        );
        expect(saved.settings.bodyFontSize, 11.0);
      }
      expect(defaultDocumentGenerationPrompt.length, lessThanOrEqualTo(20000));
    });
  }

  test(
    'target-role headline default upgrades without changing custom prompts',
    () async {
      await repository.ensureDefaults();
      for (final custom in [false, true]) {
        final prompt =
            previousRecruiterReviewDocumentGenerationPrompt +
            (custom ? '\nMy custom instructions.' : '');
        await repository.saveResumeTemplate(
          ResumeTemplateDraft(
            id: defaultResumeTemplateId,
            name: 'My template',
            settings: ResumeTemplateSettings.fromJson({
              ...ResumeTemplateSettings.defaults().toJson(),
              'generation_prompt': prompt,
              'body_font_size': 11.0,
            }),
          ),
        );
        await repository.ensureDefaults();
        final saved = (await repository.watchDefaultResumeTemplate().first)!;
        expect(
          saved.settings.generationPrompt,
          custom ? prompt : defaultDocumentGenerationPrompt,
        );
        expect(saved.settings.bodyFontSize, 11.0);
      }
      expect(defaultDocumentGenerationPrompt.length, lessThanOrEqualTo(20000));
    },
  );

  test(
    'recruiter-perspective default upgrades only untouched writing prompts',
    () async {
      await repository.ensureDefaults();
      for (final custom in [false, true]) {
        final prompt =
            previousCoverLetterDocumentGenerationPrompt +
            (custom ? '\nMy custom instructions.' : '');
        await repository.saveResumeTemplate(
          ResumeTemplateDraft(
            id: defaultResumeTemplateId,
            name: 'My template',
            settings: ResumeTemplateSettings.fromJson({
              ...ResumeTemplateSettings.defaults().toJson(),
              'generation_prompt': prompt,
              'body_font_size': 11.0,
            }),
          ),
        );
        await repository.ensureDefaults();
        final saved = (await repository.watchDefaultResumeTemplate().first)!;
        expect(
          saved.settings.generationPrompt,
          custom ? prompt : defaultDocumentGenerationPrompt,
        );
        expect(saved.settings.bodyFontSize, 11.0);
      }
      expect(defaultDocumentGenerationPrompt.length, lessThanOrEqualTo(20000));
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

  test('upgrades previous writing default to focused cover letters', () async {
    await repository.ensureDefaults();
    await repository.saveResumeTemplate(
      ResumeTemplateDraft(
        id: defaultResumeTemplateId,
        name: 'My template',
        settings: ResumeTemplateSettings.fromJson({
          ...ResumeTemplateSettings.defaults().toJson(),
          'generation_prompt': previousRelevantHistoryDocumentGenerationPrompt,
        }),
      ),
    );
    await repository.ensureDefaults();
    final saved = (await repository.watchDefaultResumeTemplate().first)!;
    expect(saved.settings.generationPrompt, defaultDocumentGenerationPrompt);
    expect(defaultDocumentGenerationPrompt.length, lessThanOrEqualTo(20000));
  });

  test(
    'upgrades untouched pipeline prompt and preserves its customizations',
    () async {
      await repository.ensureDefaults();
      for (final customized in [false, true]) {
        final prompt =
            previousPipelineDocumentGenerationPrompt +
            (customized ? '\nMy additional instructions.' : '');
        await repository.saveResumeTemplate(
          ResumeTemplateDraft(
            id: defaultResumeTemplateId,
            name: 'My layout',
            settings: ResumeTemplateSettings.fromJson({
              ...ResumeTemplateSettings.defaults().toJson(),
              'generation_prompt': prompt,
              'margin_top': 0.75,
            }),
          ),
        );
        await repository.ensureDefaults();
        final saved = (await repository.watchDefaultResumeTemplate().first)!;
        expect(
          saved.settings.generationPrompt,
          customized ? prompt : defaultDocumentGenerationPrompt,
        );
        expect(saved.settings.marginTop, 0.75);
        expect(saved.name, 'My layout');
      }
    },
  );

  test(
    'upgrades the former default to pipeline writing and direct match while preserving custom order',
    () async {
      await repository.ensureDefaults();
      for (final order in [
        ResumeTemplateSettings.legacyDefaults().sectionOrder,
        ['experience', 'projects', 'patents'],
      ]) {
        await repository.saveResumeTemplate(
          ResumeTemplateDraft(
            id: defaultResumeTemplateId,
            name: 'My layout',
            settings: ResumeTemplateSettings.fromJson({
              ...ResumeTemplateSettings.defaults().toJson(),
              'section_order': order,
              'generation_prompt': previousOrderedDocumentGenerationPrompt,
            }),
          ),
        );
        await repository.ensureDefaults();
        final saved = (await repository.watchDefaultResumeTemplate().first)!;
        expect(
          saved.settings.generationPrompt,
          defaultDocumentGenerationPrompt,
        );
        expect(
          saved.settings.sectionOrder,
          order.first == 'summary'
              ? ResumeTemplateSettings.defaults().sectionOrder
              : order,
        );
      }
    },
  );

  test('upgrades project ordering in the untouched evidence default', () async {
    await repository.ensureDefaults();
    await repository.saveResumeTemplate(
      ResumeTemplateDraft(
        id: defaultResumeTemplateId,
        name: 'My layout',
        settings: ResumeTemplateSettings.fromJson({
          ...ResumeTemplateSettings.defaults().toJson(),
          'body_font_size': 10.5,
          'generation_prompt': previousEvidenceDocumentGenerationPrompt,
        }),
      ),
    );
    await repository.ensureDefaults();
    final upgraded = (await repository.watchDefaultResumeTemplate().first)!;
    expect(upgraded.settings.generationPrompt, defaultDocumentGenerationPrompt);
    expect(
      upgraded.settings.generationPrompt,
      contains('saved order are handled by the assembler'),
    );
    expect(upgraded.name, 'My layout');
    expect(upgraded.settings.bodyFontSize, 10.5);
    final audits = (await database.select(database.auditEvents).get()).length;
    await repository.ensureDefaults();
    expect((await database.select(database.auditEvents).get()).length, audits);
  });

  test(
    'upgrades the untouched ATS default and retains layout without repeated saves',
    () async {
      await repository.ensureDefaults();
      await repository.saveResumeTemplate(
        ResumeTemplateDraft(
          id: defaultResumeTemplateId,
          name: 'My layout',
          settings: ResumeTemplateSettings.fromJson({
            ...ResumeTemplateSettings.defaults().toJson(),
            'body_font_size': 10.5,
            'section_order': ['summary', 'experience', 'projects', 'patents'],
            'generation_prompt': previousAtsDocumentGenerationPrompt,
          }),
        ),
      );
      await repository.ensureDefaults();
      final upgraded = (await repository.watchDefaultResumeTemplate().first)!;
      expect(
        upgraded.settings.generationPrompt,
        defaultDocumentGenerationPrompt,
      );
      expect(upgraded.name, 'My layout');
      expect(upgraded.settings.bodyFontSize, 10.5);
      expect(upgraded.settings.sectionOrder, [
        'summary',
        'experience',
        'projects',
        'patents',
      ]);
      final audits = (await database.select(database.auditEvents).get()).length;
      await repository.ensureDefaults();
      expect(
        (await database.select(database.auditEvents).get()).length,
        audits,
      );
    },
  );

  test(
    'updates the old default prompt without replacing custom layout and preserves custom prompts',
    () async {
      await repository.ensureDefaults();
      await repository.saveResumeTemplate(
        ResumeTemplateDraft(
          id: defaultResumeTemplateId,
          name: 'My layout',
          settings: ResumeTemplateSettings.fromJson({
            ...ResumeTemplateSettings.defaults().toJson(),
            'margin_top': 0.8,
            'generation_prompt': previousDefaultDocumentGenerationPrompt,
          }),
        ),
      );
      await repository.ensureDefaults();
      final upgraded = (await repository.watchDefaultResumeTemplate().first)!;
      expect(upgraded.name, 'My layout');
      expect(upgraded.settings.marginTop, 0.8);
      expect(
        upgraded.settings.generationPrompt,
        defaultDocumentGenerationPrompt,
      );
      await repository.saveResumeTemplate(
        ResumeTemplateDraft(
          id: upgraded.id,
          name: upgraded.name,
          settings: ResumeTemplateSettings.fromJson({
            ...upgraded.settings.toJson(),
            'generation_prompt': 'My own prompt',
          }),
        ),
      );
      await repository.ensureDefaults();
      expect(
        (await repository.watchDefaultResumeTemplate().first)!
            .settings
            .generationPrompt,
        'My own prompt',
      );
    },
  );

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
