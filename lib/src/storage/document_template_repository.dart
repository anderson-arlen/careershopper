import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../documents/document_prompt.dart';

const defaultResumeTemplateId = 'resume-default';

class ResumeTemplateSettings {
  const ResumeTemplateSettings({
    required this.paperSize,
    required this.fontFamily,
    required this.nameFontSize,
    required this.bodyFontSize,
    required this.headingFontSize,
    required this.lineSpacing,
    required this.paragraphSpacing,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
    required this.marginLeft,
    required this.textColor,
    required this.accentColor,
    required this.showSectionRules,
    required this.pageNumbers,
    required this.sectionOrder,
    this.layout = 'classic',
    this.generationPrompt = defaultDocumentGenerationPrompt,
  });

  factory ResumeTemplateSettings.defaults() => ResumeTemplateSettings.fromJson({
    ...ResumeTemplateSettings.legacyDefaults().toJson(),
    'layout': 'pipeline-v1',
    'name_font_size': 21.0,
    'body_font_size': 9.3,
    'heading_font_size': 10.7,
    'line_spacing': 1.03,
    'paragraph_spacing': 2.4,
    'margin_top': 0.52,
    'margin_bottom': 0.52,
    'margin_left': 0.58,
    'margin_right': 0.58,
    'accent_color': '#152D46',
    'section_order': [
      'summary',
      'direct_match',
      'skills',
      'experience',
      'projects',
      'education',
      'patents',
      'publications',
    ],
  });

  factory ResumeTemplateSettings.legacyDefaults() =>
      const ResumeTemplateSettings(
        paperSize: 'letter',
        fontFamily: 'Arial',
        nameFontSize: 20,
        bodyFontSize: 10,
        headingFontSize: 11,
        lineSpacing: 1.05,
        paragraphSpacing: 3,
        marginTop: 0.6,
        marginRight: 0.65,
        marginBottom: 0.6,
        marginLeft: 0.65,
        textColor: '#191C1F',
        accentColor: '#15304A',
        showSectionRules: true,
        pageNumbers: true,
        sectionOrder: [
          'summary',
          'skills',
          'experience',
          'projects',
          'education',
          'patents',
          'publications',
        ],
      );

  factory ResumeTemplateSettings.fromJson(Map<String, Object?> json) {
    final fallback = ResumeTemplateSettings.legacyDefaults();
    double number(String key, double fallbackValue) =>
        (json[key] as num?)?.toDouble() ?? fallbackValue;
    return ResumeTemplateSettings(
      layout: json['layout']?.toString() ?? 'classic',
      generationPrompt:
          json['generation_prompt']?.toString() ??
          defaultDocumentGenerationPrompt,
      paperSize: json['paper_size']?.toString() ?? fallback.paperSize,
      fontFamily: json['font_family']?.toString() ?? fallback.fontFamily,
      nameFontSize: number('name_font_size', fallback.nameFontSize),
      bodyFontSize: number('body_font_size', fallback.bodyFontSize),
      headingFontSize: number('heading_font_size', fallback.headingFontSize),
      lineSpacing: number('line_spacing', fallback.lineSpacing),
      paragraphSpacing: number('paragraph_spacing', fallback.paragraphSpacing),
      marginTop: number('margin_top', fallback.marginTop),
      marginRight: number('margin_right', fallback.marginRight),
      marginBottom: number('margin_bottom', fallback.marginBottom),
      marginLeft: number('margin_left', fallback.marginLeft),
      textColor: json['text_color']?.toString() ?? fallback.textColor,
      accentColor: json['accent_color']?.toString() ?? fallback.accentColor,
      showSectionRules:
          json['show_section_rules'] as bool? ?? fallback.showSectionRules,
      pageNumbers: json['page_numbers'] as bool? ?? fallback.pageNumbers,
      sectionOrder: json['section_order'] is List
          ? (json['section_order'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : fallback.sectionOrder,
    );
  }

  final String paperSize;
  final String fontFamily;
  final double nameFontSize;
  final double bodyFontSize;
  final double headingFontSize;
  final double lineSpacing;
  final double paragraphSpacing;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;
  final String textColor;
  final String accentColor;
  final bool showSectionRules;
  final bool pageNumbers;
  final List<String> sectionOrder;
  final String layout;
  final String generationPrompt;

  /// Pipeline's letter layout differs from its compact resume. Preserve any
  /// individually customized values rather than resetting the whole template.
  ResumeTemplateSettings forCoverLetter() {
    final values = toJson();
    if (layout == 'pipeline-v1') {
      final defaults = ResumeTemplateSettings.defaults().toJson();
      for (final entry in <String, Object>{
        'body_font_size': 10.0,
        'line_spacing': 1.12,
        'paragraph_spacing': 8.0,
        'margin_top': 0.7,
        'margin_bottom': 0.7,
        'margin_left': 0.78,
        'margin_right': 0.78,
      }.entries) {
        if (values[entry.key] == defaults[entry.key]) {
          values[entry.key] = entry.value;
        }
      }
    } else if (paragraphSpacing < 10) {
      values['paragraph_spacing'] = 10.0;
    }
    values['page_numbers'] = false;
    return ResumeTemplateSettings.fromJson(values);
  }

  Map<String, Object?> toJson() => {
    'layout': layout,
    'generation_prompt': generationPrompt,
    'paper_size': paperSize,
    'font_family': fontFamily,
    'name_font_size': nameFontSize,
    'body_font_size': bodyFontSize,
    'heading_font_size': headingFontSize,
    'line_spacing': lineSpacing,
    'paragraph_spacing': paragraphSpacing,
    'margin_top': marginTop,
    'margin_right': marginRight,
    'margin_bottom': marginBottom,
    'margin_left': marginLeft,
    'text_color': textColor,
    'accent_color': accentColor,
    'show_section_rules': showSectionRules,
    'page_numbers': pageNumbers,
    'section_order': sectionOrder,
  };
}

class ResumeTemplateDefinition {
  const ResumeTemplateDefinition({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.formatVersion,
    required this.settings,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int formatVersion;
  final ResumeTemplateSettings settings;
  final DateTime updatedAt;
}

class ResumeTemplateDraft {
  const ResumeTemplateDraft({
    required this.id,
    required this.name,
    required this.settings,
  });

  final String id;
  final String name;
  final ResumeTemplateSettings settings;
}

abstract interface class DocumentTemplateStore {
  Stream<ResumeTemplateDefinition?> watchDefaultResumeTemplate();

  Future<void> ensureDefaults();

  Future<void> saveResumeTemplate(ResumeTemplateDraft draft);

  Future<void> resetResumeTemplate(String id);
}

class DocumentTemplateRepository implements DocumentTemplateStore {
  DocumentTemplateRepository(this.database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final CareerShopperDatabase database;
  final Uuid _uuid;

  @override
  Future<void> ensureDefaults() async {
    final existing =
        await (database.select(database.documentTemplates)
              ..where((row) => row.documentKind.equals('resume'))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      // Upgrade only the untouched former default. User-customized templates
      // remain intact and can adopt the pipeline preset from Documents.
      var settings = ResumeTemplateSettings.fromJson(
        _decodeObject(existing.settingsJson),
      );
      // Historical releases differed in paragraph spacing and line endings.
      // Compare words, preserving any actual edits to the user's instructions.
      String promptText(String value) =>
          value.replaceAll(RegExp(r'\s+'), ' ').trim();
      final savedPromptText = promptText(settings.generationPrompt);
      final oldPrompt = const [
        previousDefaultDocumentGenerationPrompt,
        previousAtsDocumentGenerationPrompt,
        previousEvidenceDocumentGenerationPrompt,
        previousOrderedDocumentGenerationPrompt,
        previousPipelineDocumentGenerationPrompt,
        previousRelevantHistoryDocumentGenerationPrompt,
        previousCoverLetterDocumentGenerationPrompt,
        previousRecruiterReviewDocumentGenerationPrompt,
        previousTargetRoleDocumentGenerationPrompt,
        previousCompactPatentDocumentGenerationPrompt,
        previousSpecializedHeadlineDocumentGenerationPrompt,
        previousDescriptiveProjectHeadingDocumentGenerationPrompt,
        previousBoldProjectStackDocumentGenerationPrompt,
      ].any((previous) => promptText(previous) == savedPromptText);
      if (oldPrompt) {
        settings = ResumeTemplateSettings.fromJson({
          ...settings.toJson(),
          'generation_prompt': defaultDocumentGenerationPrompt,
        });
      }
      if (existing.name == 'ATS Plain' &&
          jsonEncode(settings.toJson()) ==
              jsonEncode(ResumeTemplateSettings.legacyDefaults().toJson())) {
        await saveResumeTemplate(
          ResumeTemplateDraft(
            id: existing.id,
            name: 'Pipeline Classic',
            settings: ResumeTemplateSettings.defaults(),
          ),
        );
      } else if (oldPrompt) {
        if (jsonEncode(settings.sectionOrder) ==
            jsonEncode(ResumeTemplateSettings.legacyDefaults().sectionOrder)) {
          settings = ResumeTemplateSettings.fromJson({
            ...settings.toJson(),
            'section_order': ResumeTemplateSettings.defaults().sectionOrder,
          });
        }
        await saveResumeTemplate(
          ResumeTemplateDraft(
            id: existing.id,
            name: existing.name,
            settings: settings,
          ),
        );
      }
      return;
    }
    final now = DateTime.now().toUtc();
    await database
        .into(database.documentTemplates)
        .insert(
          DocumentTemplatesCompanion.insert(
            id: defaultResumeTemplateId,
            name: 'Pipeline Classic',
            documentKind: 'resume',
            isDefault: const Value(true),
            settingsJson: jsonEncode(
              ResumeTemplateSettings.defaults().toJson(),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  @override
  Stream<ResumeTemplateDefinition?> watchDefaultResumeTemplate() {
    final query = database.select(database.documentTemplates)
      ..where((row) => row.documentKind.equals('resume'))
      ..orderBy([
        (row) => OrderingTerm.desc(row.isDefault),
        (row) => OrderingTerm.asc(row.createdAt),
      ])
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : ResumeTemplateDefinition(
              id: row.id,
              name: row.name,
              isDefault: row.isDefault,
              formatVersion: row.formatVersion,
              settings: ResumeTemplateSettings.fromJson(
                _decodeObject(row.settingsJson),
              ),
              updatedAt: row.updatedAt,
            ),
    );
  }

  @override
  Future<void> saveResumeTemplate(ResumeTemplateDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) throw ArgumentError('Template name is required.');
    _validate(draft.settings);
    if (draft.settings.generationPrompt.trim().isEmpty ||
        draft.settings.generationPrompt.length > 20000) {
      throw ArgumentError(
        'Generation prompt must contain 1–20,000 characters.',
      );
    }
    final now = DateTime.now().toUtc();
    final existing = await (database.select(
      database.documentTemplates,
    )..where((row) => row.id.equals(draft.id))).getSingleOrNull();
    if (existing == null) {
      throw ArgumentError('Resume template no longer exists.');
    }
    await database.transaction(() async {
      await (database.update(
        database.documentTemplates,
      )..where((row) => row.id.equals(draft.id))).write(
        DocumentTemplatesCompanion(
          name: Value(name),
          settingsJson: Value(jsonEncode(draft.settings.toJson())),
          updatedAt: Value(now),
        ),
      );
      await _audit('document_template.edited', draft.id, now);
    });
  }

  @override
  Future<void> resetResumeTemplate(String id) async {
    final existing = await (database.select(
      database.documentTemplates,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing == null || existing.documentKind != 'resume') {
      throw ArgumentError('Resume template no longer exists.');
    }
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      await (database.update(
        database.documentTemplates,
      )..where((row) => row.id.equals(id))).write(
        DocumentTemplatesCompanion(
          name: const Value('Pipeline Classic'),
          settingsJson: Value(
            jsonEncode(ResumeTemplateSettings.defaults().toJson()),
          ),
          updatedAt: Value(now),
        ),
      );
      await _audit('document_template.reset', id, now);
    });
  }

  Future<void> _audit(String eventType, String id, DateTime now) => database
      .into(database.auditEvents)
      .insert(
        AuditEventsCompanion.insert(
          id: _uuid.v7(),
          eventType: eventType,
          subjectType: 'document_template',
          subjectId: id,
          actor: 'desktop_user',
          occurredAt: now,
        ),
      );
}

void _validate(ResumeTemplateSettings settings) {
  if (!{'letter', 'a4'}.contains(settings.paperSize)) {
    throw ArgumentError('Paper size must be Letter or A4.');
  }
  if (settings.fontFamily.trim().isEmpty) {
    throw ArgumentError('Font family is required.');
  }
  for (final entry in {
    'Name font size': settings.nameFontSize,
    'Body font size': settings.bodyFontSize,
    'Heading font size': settings.headingFontSize,
  }.entries) {
    if (entry.value < 6 || entry.value > 36) {
      throw ArgumentError('${entry.key} must be between 6 and 36 points.');
    }
  }
  for (final entry in {
    'Top margin': settings.marginTop,
    'Right margin': settings.marginRight,
    'Bottom margin': settings.marginBottom,
    'Left margin': settings.marginLeft,
  }.entries) {
    if (entry.value < 0.25 || entry.value > 2) {
      throw ArgumentError('${entry.key} must be between 0.25 and 2 inches.');
    }
  }
  if (settings.lineSpacing < 0.8 || settings.lineSpacing > 2) {
    throw ArgumentError('Line spacing must be between 0.8 and 2.');
  }
  if (settings.paragraphSpacing < 0 || settings.paragraphSpacing > 24) {
    throw ArgumentError('Paragraph spacing must be between 0 and 24 points.');
  }
  final color = RegExp(r'^#[0-9A-Fa-f]{6}$');
  if (!color.hasMatch(settings.textColor) ||
      !color.hasMatch(settings.accentColor)) {
    throw ArgumentError(
      'Colors must use six-digit hex values such as #15304A.',
    );
  }
  const allowedSections = {
    'summary',
    'direct_match',
    'skills',
    'experience',
    'projects',
    'education',
    'patents',
    'publications',
  };
  if (settings.sectionOrder.isEmpty ||
      settings.sectionOrder.toSet().length != settings.sectionOrder.length ||
      settings.sectionOrder.any(
        (section) => !allowedSections.contains(section),
      )) {
    throw ArgumentError(
      'Section order contains an unsupported or repeated section.',
    );
  }
}

Map<String, Object?> _decodeObject(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) return const {};
  return decoded.map((key, item) => MapEntry(key.toString(), item));
}
