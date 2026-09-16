import 'dart:convert';

import 'material_markdown.dart';

const resumeContentKind = 'resume_content';

Map<String, Object> _objectSchema(
  Map<String, Object> properties, {
  List<String> optional = const [],
}) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.where((key) => !optional.contains(key)).toList(),
  'additionalProperties': false,
};
const _textSchema = {'type': 'string', 'maxLength': 10000};
Map<String, Object> _entrySchema(
  Map<String, Object> properties, {
  List<String> optional = const [],
}) => {
  'type': 'array',
  'maxItems': 100,
  'items': _objectSchema({
    'id': _textSchema,
    'enabled': {'type': 'boolean'},
    ...properties,
  }, optional: optional),
};
final _achievementSchema = _objectSchema(
  {
    'id': _textSchema,
    'text': _textSchema,
    'priority': {
      'type': 'integer',
      'minimum': 0,
      'maximum': 100,
      'description':
          'Relative importance, 0 to 100; higher points guide AI selection among relevant achievements. Defaults to 0.',
    },
    'requires': {
      'type': 'array',
      'uniqueItems': true,
      'items': _textSchema,
      'description':
          'IDs of other achievements in this employment entry that must also be selected when this achievement is selected. Defaults to an empty list. Dependencies are directional and may chain.',
    },
    'required': {
      'type': 'boolean',
      'description':
          'Must be included whenever this employment entry is included. Defaults to false.',
    },
  },
  optional: ['priority', 'required', 'requires'],
);
final resumeContentSchema = _objectSchema(
  {
    'header': {
      ..._objectSchema({'name': _textSchema, 'contact': _textSchema}),
      'properties': {
        'name': _textSchema,
        'contact': _textSchema,
        'headline': {
          ..._textSchema,
          'description':
              'Legacy saved value; ignored. The professional headline is generated per resume.',
        },
      },
    },
    'headings': _objectSchema({
      for (final k in [
        'direct_match',
        'skills',
        'experience',
        'projects',
        'patents',
        'education',
      ])
        k: _textSchema,
    }),
    'skills': _entrySchema({
      'name': _textSchema,
      'proficiency': _textSchema,
      'notes': _textSchema,
    }),
    'experience': {
      'type': 'array',
      'maxItems': 100,
      'items': {
        'type': 'object',
        'properties': {
          'id': _textSchema,
          'enabled': {'type': 'boolean'},
          'verification_status': {
            'type': 'string',
            'enum': ['confirmed', 'pending'],
            'description':
                'Defaults to confirmed. Pending imported work history remains uncertain matching context and must stay disabled until the user reviews it.',
          },
          'employer': _textSchema,
          'location': _textSchema,
          'titles': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 100,
            'description':
                'Exact titles and their date ranges, in resume display order. All titles remain when the employment entry is selected.',
            'items': _objectSchema({
              'title': _textSchema,
              'dates': _textSchema,
              'achievements': {
                'type': 'array',
                'maxItems': 100,
                'items': _achievementSchema,
              },
            }),
          },
          'title': {
            ..._textSchema,
            'description':
                'Legacy single-title input; use titles for new content.',
          },
          'dates': {
            ..._textSchema,
            'description':
                'Legacy single-title date range; use titles for new content.',
          },
          'achievements': {
            'type': 'array',
            'maxItems': 100,
            'items': _achievementSchema,
          },
        },
        'required': ['id', 'enabled', 'employer', 'location'],
        'additionalProperties': false,
      },
    },
    'projects': _entrySchema(
      {
        for (final k in ['name', 'stack', 'dates', 'url', 'description'])
          k: _textSchema,
        'details': {
          'type': 'array',
          'maxItems': 100,
          'description':
              'Optional exact detail sentences, in display order. AI selects any, all or none by ID; description is the always-included summary.',
          'items': _objectSchema(
            {
              'id': _textSchema,
              'text': _textSchema,
              'requires': {
                'type': 'array',
                'uniqueItems': true,
                'items': _textSchema,
                'description':
                    'IDs of other detail sentences in this project that must also be selected. Defaults to an empty list. Dependencies are directional and may chain.',
              },
            },
            optional: ['requires'],
          ),
        },
      },
      optional: ['details'],
    ),
    'patents': _entrySchema({'text': _textSchema}),
    'education': _entrySchema({'heading': _textSchema, 'details': _textSchema}),
    'personal_context': {
      ..._entrySchema({'topic': _textSchema, 'text': _textSchema}),
      'description':
          'User-confirmed interests, domain connections and credentials. Enabled entries may support tailored prose; they are not printed automatically as resume sections. Do not infer facts or credential currency.',
    },
  },
  optional: ['skills', 'personal_context'],
);
final supportedTextSchema = _objectSchema(
  {
    'text': {
      ..._textSchema,
      'description':
          'Plain prose, without headings, bullets or citation comments. Whitespace is normalized into one paragraph.',
    },
    'support_ids': {
      'type': 'array',
      'minItems': 1,
      'uniqueItems': true,
      'items': _textSchema,
      'description':
          'Supporting enabled entry, achievement or project-detail IDs from Resume content. Use short IDs such as F1 from generation_content; never UUIDs.',
    },
    'label': {
      ..._textSchema,
      'description':
          'Optional plain-text label; CareerShopper formats it in bold.',
    },
  },
  optional: ['label'],
);
final _supportedTextListSchema = {
  'type': 'array',
  'minItems': 1,
  'maxItems': 100,
  'items': supportedTextSchema,
};
final resumePlanSchema = _objectSchema({
  'professional_headline': {
    'type': 'string',
    'maxLength': 200,
    'description':
        'Broad target occupation with conventional seniority. Plain text; empty omits it.',
  },
  'summary': supportedTextSchema,
  'direct_match': _supportedTextListSchema,
  'core_skills': _supportedTextListSchema,
  'selected_ids': {
    'type': 'array',
    'uniqueItems': true,
    'items': _textSchema,
    'description':
        'Enabled experience entry/achievement and optional project-detail IDs to include. CareerShopper groups them, adds required achievements and all prerequisites, and fills uncovered titles using highest priority (saved order breaks ties). All enabled project summaries, patents and education are included automatically.',
  },
});
final coverLetterPlanSchema = _objectSchema({
  'paragraphs': {
    ..._supportedTextListSchema,
    'minItems': 2,
    'description':
        'Complete tailored body paragraphs with supporting saved-content IDs. CareerShopper supplies the applicant header, greeting, signoff, layout and citations.',
  },
});

const fixedResumeGenerationInstructions =
    '''CareerShopper generates document Markdown programmatically. This contract overrides older Markdown-writing instructions.
Submit resume_plan and cover_letter_plan. Do not write complete Markdown documents, citation comments, frontmatter, fixed headings, contact details, greetings or signatures.
resume_plan contains professional_headline, summary, direct_match, core_skills and selected_ids. summary is one {text, support_ids} object; direct_match and core_skills are lists of these objects. Optional label is formatted in bold by CareerShopper. Write plain prose. Each support_ids list selects short IDs (F1, F2, etc.) in the supplied generation_content that support the text. Never copy UUIDs or invent IDs. Short IDs are bound to this work order and must be used for both selections and support_ids. CareerShopper binds them to the exact saved revision and inserts every citation.
Generate professional_headline as a broad target occupation with conventional seniority, without team, technology, specialty, location or internal grades. This is application positioning, not a past employment title.
Preserve time scope in all generated prose, including summaries and cover letters. Saved "have led" describes accumulated experience, not necessarily a current responsibility; historical peak team size or scale is not today's size or scale. A current employer or role does not make every claim ongoing. Use present tense only when the specific responsibility is supported as ongoing, and preserve past or present-perfect meaning from the latest saved evidence. Do not copy superseded wording from older drafts or volunteer unrelated current staffing limitations.
Personal context supplies confirmed interests, preferences, domain connections and credentials for matching and tailored prose. A useful personal connection establishes firsthand familiarity with this employer's users, workflow or domain; general hobbies, broad traits and a preference for building things do not qualify. Include a genuine connection where it strengthens the case, without forcing it into every opening or displacing stronger direct professional evidence. When direct implementation experience exists, use it as the principal professional evidence in the opening rather than burying it later while leading with an adjacent project. Use short IDs as support. Do not infer product use, current license status or professional domain experience from an interest or credential. Do not add a fixed personal-context resume section; if no personal connection fits, use professional evidence alone.
Core skills supply proficiency and context as evidence, not fixed resume paragraphs. Lead with the strongest relevant skills, using expertise descriptors only where supported. Describe other supported skills as "experience in" or "additional experience in" without publishing proficiency grades or weakness labels such as "low proficiency," "weak," "novice," or "beginner" in resumes or cover letters. Saved assessments constrain claims; they are not copy to publish. Keep expertise descriptors scoped to the skills they support and never upgrade experience. Use their short IDs in support_ids for generated skill groups, summaries and letters.
Select relevant achievements and optional project details by their simple IDs in selected_ids. Selecting an experience entry ID also includes that job. CareerShopper finds their employers/titles and saved order, adds every required achievement for included jobs, closes all prerequisite dependencies (including cycles), and fills any title lacking a selected bullet with its highest-priority saved achievement (saved order breaks ties). Titles without saved bullets keep their exact title and dates. You do not need to repeat required IDs or solve dependencies. Priority scores guide relevance choices; never rewrite or reorder fixed wording. Enabled project summaries, patents and education appear automatically; optional project details and their prerequisites are appended verbatim.
cover_letter_plan contains paragraphs, a list of {text, support_ids} objects for the complete tailored body. CareerShopper supplies name/contact, greeting, signoff and citations. Use only enabled saved content as evidence. Disabled entries are matching context only and must never appear in generated materials.
Choose a concrete applicant experience or personal connection that gives a useful perspective on this employer's product, users, workflow or actual role responsibilities. Explain what transfers and why it matters. A product name attached to broad traits such as being a builder or noticing friction, or shared vocabulary such as "data," does not establish a connection. Do not substitute "natural fit" for that explanation. Let the opening develop naturally rather than forcing the connection into its first sentence. Assume the reader knows their products; keep the opening focused on relevance and put detailed career history, technologies and metrics in supporting paragraphs. Check whether swapping the applicant and company names would leave the opening equally applicable to almost anyone: if so, replace the generic premise with specific supported evidence. If no distinctive connection is supported, use a concrete match to an actual role responsibility without pretending it is unique. Never invent company details, enthusiasm or product use.
Compare candidate examples by the actual problem solved and the applicant's responsibility. Direct implementation or ownership of the employer's core problem takes priority over newer but adjacent projects, shared technology or a loose analogy. Distinguish building a capability from using it: respecting permission boundaries or sharing an API is not evidence of designing authorization rules. Use recency to choose between similarly relevant examples, not to displace stronger direct work. Pair the professional evidence with a supported personal or domain connection when one adds a distinct perspective. Do not make an old, no-longer-maintained project the opening's centerpiece merely because it offers the closest product analogy. Preserve useful older experience and its accurate time scope without implying ongoing maintenance or activity.
For revisions submit a revised structured pair. Existing draft/material handles and exact-text edits remain available for small edits to already assembled documents, but a new plan is needed to change selections. Reviewer feedback does not authorize changing fixed wording or inventing claims.''';

/// User-owned wording, stored as a versioned career fact. IDs are selection keys,
/// not model-authored text or positions that change when entries are reordered.
class ResumeContent {
  ResumeContent(Map<String, dynamic> value)
    : data = jsonDecode(jsonEncode(value)) as Map<String, dynamic> {
    data.putIfAbsent('skills', () => <dynamic>[]);
    data.putIfAbsent('personal_context', () => <dynamic>[]);
    // Existing saved facts retain their revision and exact single-title output.
    final experience = data['experience'];
    if (experience is List) {
      for (final role in experience) {
        if (role is Map && !role.containsKey('titles')) {
          role['titles'] = [
            {
              'title': role.remove('title'),
              'dates': role.remove('dates'),
              'achievements': role.remove('achievements'),
            },
          ];
        }
      }
    }
  }
  final Map<String, dynamic> data;

  static Map<String, dynamic> empty() => {
    'header': {'name': '', 'contact': ''},
    'headings': {
      'direct_match': 'DIRECT MATCH',
      'skills': 'CORE SKILLS',
      'experience': 'RELEVANT WORK HISTORY',
      'projects': 'OPEN-SOURCE & INDEPENDENT PRODUCTS',
      'patents': 'PATENTS',
      'education': 'EDUCATION',
    },
    'skills': <dynamic>[],
    'personal_context': <dynamic>[],
    'experience': <dynamic>[],
    'projects': <dynamic>[],
    'patents': <dynamic>[],
    'education': <dynamic>[],
  };

  Map get header => data['header'] as Map;
  Map get headings => data['headings'] as Map;
  List<Map> entries(String section) => (data[section] as List).cast<Map>();

  void validate() {
    final ids = <String>{};
    void fields(Map value, List<String> required, List<String> optional) {
      if (value.keys.any((k) => ![...required, ...optional].contains(k))) {
        throw const FormatException('Unknown fixed resume field.');
      }
      for (final key in [...required, ...optional]) {
        if ([
              'enabled',
              'notes',
              'achievements',
              'titles',
              'priority',
              'required',
              'requires',
            ].contains(key) ||
            (key == 'details' && value.containsKey('description'))) {
          continue;
        }
        final text = value[key];
        if (text is! String ||
            text.length > 10000 ||
            RegExp(r'[<>`*|\r\n]').hasMatch(text) ||
            (required.contains(key) && text.trim().isEmpty)) {
          throw FormatException(
            '$key must be plain text${required.contains(key) ? ' and cannot be empty' : ''}.',
          );
        }
      }
      if (value.containsKey('id') && !ids.add(value['id'] as String)) {
        throw const FormatException(
          'Resume entry and achievement IDs must be unique.',
        );
      }
    }

    if (data.keys.toSet().difference(empty().keys.toSet()).isNotEmpty ||
        data['header'] is! Map ||
        data['headings'] is! Map) {
      throw const FormatException('Invalid fixed resume content.');
    }
    fields(
      header,
      ['name'],
      ['contact', if (header.containsKey('headline')) 'headline'],
    );
    fields(
      headings,
      (empty()['headings'] as Map).keys.cast<String>().toList(),
      [],
    );
    if (headings.values.toSet().length != headings.length) {
      throw const FormatException('Section headings must be distinct.');
    }
    for (final section in [
      'experience',
      'projects',
      'patents',
      'education',
      'skills',
      'personal_context',
    ]) {
      if (data[section] is! List || (data[section] as List).length > 100) {
        throw FormatException(
          '$section must be a list of at most 100 entries.',
        );
      }
      for (final raw in data[section] as List) {
        if (raw is! Map || raw['enabled'] is! bool) {
          throw const FormatException(
            'Each resume entry needs an enabled flag.',
          );
        }
        switch (section) {
          case 'skills':
            fields(raw, ['id', 'name'], ['enabled', 'proficiency', 'notes']);
            if (raw['proficiency'] is! String ||
                raw['notes'] is! String ||
                (raw['notes'] as String).length > 10000) {
              throw const FormatException(
                'Skill proficiency and notes must be text.',
              );
            }
          case 'experience':
            fields(
              raw,
              ['id', 'employer'],
              [
                'location',
                'titles',
                'enabled',
                if (raw.containsKey('verification_status'))
                  'verification_status',
              ],
            );
            final status = raw['verification_status'] ?? 'confirmed';
            if (!['confirmed', 'pending'].contains(status) ||
                (status == 'pending' && raw['enabled'] == true)) {
              throw const FormatException(
                'Unreviewed work history must remain disabled. Review its wording before confirming it.',
              );
            }
            if (raw['titles'] is! List ||
                (raw['titles'] as List).isEmpty ||
                (raw['titles'] as List).length > 100) {
              throw const FormatException(
                'Each employment entry needs between 1 and 100 titles.',
              );
            }
            for (final title in raw['titles'] as List) {
              if (title is! Map) {
                throw const FormatException('Invalid job title.');
              }
              fields(title, ['title'], ['dates', 'achievements']);
              if (title['achievements'] is! List ||
                  (title['achievements'] as List).length > 100) {
                throw const FormatException(
                  'Each title needs an achievements list.',
                );
              }
              for (final achievement in title['achievements'] as List) {
                if (achievement is! Map) {
                  throw const FormatException('Invalid achievement.');
                }
                fields(
                  achievement,
                  ['id', 'text'],
                  ['priority', 'required', 'requires'],
                );
                final priority = achievement['priority'] ?? 0;
                if (priority is! int ||
                    priority < 0 ||
                    priority > 100 ||
                    (achievement.containsKey('priority') &&
                        achievement['priority'] == null)) {
                  throw const FormatException(
                    'Achievement priority must be an integer from 0 to 100.',
                  );
                }
                if (achievement.containsKey('required') &&
                    achievement['required'] is! bool) {
                  throw const FormatException(
                    'Achievement required must be a boolean.',
                  );
                }
              }
            }
            final achievements = roleAchievements(raw);
            final ownIds = achievements.map((a) => a['id']).toSet();
            for (final achievement in achievements) {
              final dependencies = achievement.containsKey('requires')
                  ? achievement['requires']
                  : [];
              if (dependencies is! List ||
                  dependencies.any(
                    (id) =>
                        id is! String ||
                        id == achievement['id'] ||
                        !ownIds.contains(id),
                  ) ||
                  dependencies.toSet().length != dependencies.length) {
                throw const FormatException(
                  'Achievement requires must contain unique IDs of other achievements in the same employment entry.',
                );
              }
            }
          case 'projects':
            fields(
              raw,
              ['id', 'name', 'description'],
              [
                'stack',
                'dates',
                'url',
                'enabled',
                if (raw.containsKey('details')) 'details',
              ],
            );
            final details = raw.containsKey('details') ? raw['details'] : [];
            if (details is! List || details.length > 100) {
              throw const FormatException(
                'Project details must be a list of at most 100 sentences.',
              );
            }
            for (final detail in details) {
              if (detail is! Map) {
                throw const FormatException('Invalid project detail.');
              }
              fields(detail, ['id', 'text'], ['requires']);
            }
            final ownIds = details.map((d) => d['id']).toSet();
            for (final detail in details) {
              final dependencies = detail.containsKey('requires')
                  ? detail['requires']
                  : [];
              if (dependencies is! List ||
                  dependencies.any(
                    (id) =>
                        id is! String ||
                        id == detail['id'] ||
                        !ownIds.contains(id),
                  ) ||
                  dependencies.toSet().length != dependencies.length) {
                throw const FormatException(
                  'Project detail requires must contain unique IDs of other detail sentences in the same project.',
                );
              }
            }
          case 'patents':
            fields(raw, ['id', 'text'], ['enabled']);
          case 'education':
            fields(raw, ['id', 'heading', 'details'], ['enabled']);
          case 'personal_context':
            fields(raw, ['id', 'topic', 'text'], ['enabled']);
        }
      }
    }
  }

  /// Catch literal disclosure of matching-only content even when an unscoped
  /// caller has previously read the full profile. Writers receive filtered data.
  void validateDisclosure(String text) {
    final visible = <String>[];
    final hidden = <String>[];
    for (final section in [
      'experience',
      'projects',
      'patents',
      'education',
      'skills',
      'personal_context',
    ]) {
      for (final entry in entries(section)) {
        final target = entry['enabled'] == true ? visible : hidden;
        if (section == 'experience') {
          target.add(entry['employer'] as String);
          target.addAll(
            roleAchievements(entry).map((a) => a['text'] as String),
          );
        } else if (section == 'personal_context') {
          target.add(entry['topic'] as String);
          target.add(entry['text'] as String);
        } else if (section == 'skills') {
          target.add(entry['name'] as String);
          target.add(entry['notes'] as String);
        } else if (section == 'projects') {
          target.add(entry['name'] as String);
          target.add(entry['description'] as String);
          if (entry['enabled'] == true) target.add(entry['stack'] as String);
          target.addAll(projectDetails(entry).map((d) => d['text'] as String));
        } else {
          target.add(
            entry[section == 'patents' ? 'text' : 'heading'] as String,
          );
        }
      }
    }
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final allowed = normalize(
      [header['name'], header['contact'], ...visible].join(' '),
    );
    final candidate = normalize(text);
    for (final value in hidden.map(normalize).where((s) => s.length >= 4)) {
      if (!allowed.contains(value) &&
          RegExp(
            r'(^|[^a-z0-9])' + RegExp.escape(value) + r'(?=$|[^a-z0-9])',
          ).hasMatch(candidate)) {
        throw const FormatException(
          'Application text includes a disabled resume entry. Disabled content is for matching only.',
        );
      }
    }
  }

  String _block(String text, String revision) =>
      '$text <!-- facts: $revision -->';
  List<String> roleHeading(Map role, String revision) {
    final titles = (role['titles'] as List).cast<Map>();
    if (titles.length == 1) {
      return [
        _block('### ${role['employer']}, ${titles.single['title']}', revision),
        if ([
          role['location'],
          titles.single['dates'],
        ].any((v) => (v as String).isNotEmpty))
          _block(
            '*${[role['location'], titles.single['dates']].where((v) => (v as String).isNotEmpty).join(' · ')}*',
            revision,
          ),
      ];
    }
    return [
      _block('### ${role['employer']}', revision),
      if ((role['location'] as String).isNotEmpty)
        _block('*${role['location']}*', revision),
    ];
  }

  List<Map> roleAchievements(Map role) => (role['titles'] as List)
      .cast<Map>()
      .expand((title) => (title['achievements'] as List).cast<Map>())
      .toList();

  String titleHeading(Map title, String revision) => _block(
    '**${title['title']}**${(title['dates'] as String).isEmpty ? '' : ' · ${title['dates']}'}',
    revision,
  );

  List<Map> projectDetails(Map project) =>
      ((project['details'] ?? []) as List).cast<Map>();

  List<String> projectHeading(Map project, String revision) => [
    _block(
      '### **${project['name']}**${(project['stack'] as String).isEmpty ? '' : ' · ${project['stack']}'}',
      revision,
    ),
    if ((project['dates'] as String).isNotEmpty)
      _block('*${project['dates']}*', revision),
    if ((project['url'] as String).isNotEmpty)
      _block(project['url'] as String, revision),
  ];

  List<String> _inferProjectDetails(Map project, String text) {
    final summary = project['description'] as String;
    if (!text.startsWith(summary)) {
      throw StateError('Project summaries are fixed and always included.');
    }
    // Match whole saved sentences in order, including overlapping wording,
    // without accepting shortened sentences or moving them between projects.
    final matches = <int, List<String>>{summary.length: []};
    for (final detail in projectDetails(project)) {
      final sentence = ' ${detail['text']}';
      for (final match in matches.entries.toList()) {
        if (text.startsWith(sentence, match.key)) {
          matches.putIfAbsent(
            match.key + sentence.length,
            () => [...match.value, detail['id'] as String],
          );
        }
      }
    }
    final selected = matches[text.length];
    if (selected == null) {
      throw StateError(
        'Project details must use complete saved sentences in their saved order.',
      );
    }
    return selected;
  }

  Map<String, Map> get _enabledEvidence => {
    for (final section in [
      'experience',
      'projects',
      'patents',
      'education',
      'skills',
      'personal_context',
    ])
      for (final entry in entries(
        section,
      ).where((e) => e['enabled'] == true)) ...{
        entry['id'] as String: entry,
        if (section == 'experience')
          for (final item in roleAchievements(entry))
            item['id'] as String: item,
        if (section == 'projects')
          for (final item in projectDetails(entry)) item['id'] as String: item,
      },
  };

  Map<String, String> get _generationIds => {
    for (final (index, id) in _enabledEvidence.keys.indexed)
      'F${index + 1}': id,
  };

  /// Short IDs are local to the frozen work-order revision, never persistent IDs.
  Map<String, dynamic> get generationContent {
    final aliases = {
      for (final entry in _generationIds.entries) entry.value: entry.key,
    };
    Object? rewrite(Object? value) {
      if (value is List) return value.map(rewrite).toList();
      if (value is Map) {
        return {
          for (final entry in value.entries)
            entry.key: entry.key == 'id'
                ? aliases[entry.value]
                : entry.key == 'requires'
                ? (entry.value as List).map((id) => aliases[id]).toList()
                : rewrite(entry.value),
        };
      }
      return value;
    }

    return {
      'header': header,
      'headings': headings,
      for (final section in [
        'experience',
        'projects',
        'patents',
        'education',
        'skills',
        'personal_context',
      ])
        section: rewrite(
          entries(section).where((e) => e['enabled'] == true).toList(),
        ),
    };
  }

  Set<String> _selectionIds(
    Object? value,
    String field,
    Set<String> allowed, {
    bool required = false,
  }) {
    if (value is! List || value.any((id) => id is! String)) {
      throw FormatException('$field must be a list of saved-content IDs.');
    }
    final ids = value.cast<String>().toSet();
    if (required && ids.isEmpty) {
      throw FormatException('$field needs at least one supporting content ID.');
    }
    final invalid = ids.difference(allowed);
    if (invalid.isNotEmpty) {
      throw FormatException(
        '$field contains unknown or disabled IDs: ${invalid.join(', ')}.',
      );
    }
    return ids;
  }

  String _supportedText(
    Object? value,
    String field,
    String revision, {
    bool bullet = false,
  }) {
    if (value is! Map) {
      throw FormatException('$field needs text and support_ids.');
    }
    _selectionIds(
      value['support_ids'],
      '$field.support_ids',
      _generationIds.keys.toSet(),
      required: true,
    );
    String prose(Object? raw) {
      if (raw is! String || raw.trim().isEmpty || raw.length > 10000) {
        throw FormatException(
          '$field needs nonempty prose of at most 10000 characters.',
        );
      }
      final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (RegExp(r'[<>`*|]').hasMatch(text) ||
          RegExp(r'^(#|- |\d+\. )|!?\[[^\]]*\]\(').hasMatch(text)) {
        throw FormatException(
          '$field accepts plain prose; use label for a bold label. CareerShopper supplies Markdown and citations.',
        );
      }
      return text;
    }

    final text = prose(value['text']);
    final label = value['label'] == null ? '' : '**${prose(value['label'])}** ';
    return _block('${bullet ? '- ' : ''}$label$text', revision);
  }

  List<String> _supportedParagraphs(
    Object? value,
    String field,
    String revision, {
    bool bullets = false,
    int minimum = 1,
  }) {
    if (value is! List || value.length < minimum || value.length > 100) {
      throw FormatException(
        '$field needs $minimum to 100 text/support_ids objects.',
      );
    }
    return [
      for (final (index, item) in value.indexed)
        _supportedText(item, '$field[$index]', revision, bullet: bullets),
    ];
  }

  // Close dependencies in code, including mutually dependent groups. Saved
  // order, rather than the order in which the model lists IDs, controls output.
  void _includePrerequisites(Set<String> selected, List<Map> items) {
    final byId = {for (final item in items) item['id'] as String: item};
    final pending = selected.toList();
    while (pending.isNotEmpty) {
      final item = byId[pending.removeLast()]!;
      for (final id in (item['requires'] as List? ?? []).cast<String>()) {
        if (selected.add(id)) pending.add(id);
      }
    }
  }

  Map<String, dynamic> _assemblePlan(
    Map<String, dynamic> plan,
    String revision,
  ) {
    if ([
      'summary_markdown',
      'direct_match_markdown',
      'core_skills_markdown',
      'work_history',
      'project_details',
    ].any(plan.containsKey)) {
      throw const FormatException(
        'Use structured text and selected_ids without legacy Markdown fields.',
      );
    }
    final selected = _selectionIds(
      plan['selected_ids'],
      'selected_ids',
      _generationIds.keys.toSet(),
    ).map((id) => _generationIds[id]!).toSet();
    final work = <Map<String, Object>>[];
    for (final role in entries(
      'experience',
    ).where((e) => e['enabled'] == true)) {
      final items = roleAchievements(role);
      final ids = items
          .map((a) => a['id'] as String)
          .where(selected.contains)
          .toSet();
      if (ids.isEmpty && !selected.contains(role['id'])) continue;
      ids.addAll(
        items.where((a) => a['required'] == true).map((a) => a['id'] as String),
      );
      _includePrerequisites(ids, items);
      for (final title in (role['titles'] as List).cast<Map>()) {
        final achievements = (title['achievements'] as List).cast<Map>();
        if (achievements.isEmpty ||
            achievements.any((a) => ids.contains(a['id']))) {
          continue;
        }
        // A strict greater-than retains saved order for equal priorities.
        var best = achievements.first;
        for (final candidate in achievements.skip(1)) {
          if ((candidate['priority'] as int? ?? 0) >
              (best['priority'] as int? ?? 0)) {
            best = candidate;
          }
        }
        ids.add(best['id'] as String);
        _includePrerequisites(ids, items);
      }
      work.add({
        'entry_id': role['id'] as String,
        'achievement_ids': ids.toList(),
      });
    }
    final projects = <Map<String, Object>>[];
    for (final project in entries(
      'projects',
    ).where((e) => e['enabled'] == true)) {
      final items = projectDetails(project);
      final ids = items
          .map((d) => d['id'] as String)
          .where(selected.contains)
          .toSet();
      _includePrerequisites(ids, items);
      if (ids.isNotEmpty) {
        projects.add({
          'entry_id': project['id'] as String,
          'detail_ids': ids.toList(),
        });
      }
    }
    return {
      'content_revision_id': revision,
      'professional_headline': plan['professional_headline'],
      'summary_markdown': _supportedText(plan['summary'], 'summary', revision),
      'direct_match_markdown': _supportedParagraphs(
        plan['direct_match'],
        'direct_match',
        revision,
        bullets: true,
      ).join('\n\n'),
      'core_skills_markdown': _supportedParagraphs(
        plan['core_skills'],
        'core_skills',
        revision,
      ).join('\n\n'),
      'work_history': work,
      'project_details': projects,
    };
  }

  String composeCoverLetter(
    Map<String, dynamic> plan,
    String revision, {
    String employer = '',
    String jobTitle = '',
    String draftingDate = '',
  }) {
    validate();
    // Listing fields are display data, never Markdown or template instructions.
    String contextText(String text) => text
        .replaceAll(RegExp(r'[<>`*|#\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final recipient = contextText(employer);
    final subject = contextText(jobTitle);

    final markdown = [
      '---\ndocument_type: cover_letter\n${subject.isEmpty ? '' : 'subtitle: $subject application\n'}footer: ${header['name']}\npage_numbers: false\n--- <!-- facts: $revision -->',
      _block('# ${header['name']}', revision),
      if ((header['contact'] as String).isNotEmpty)
        _block(header['contact'] as String, revision),
      if (draftingDate.isNotEmpty) _block(contextText(draftingDate), revision),
      if (recipient.isNotEmpty) _block('Hiring Team  \n$recipient', revision),
      _block('Dear Hiring Team,', revision),
      ..._supportedParagraphs(
        plan['paragraphs'],
        'paragraphs',
        revision,
        minimum: 2,
      ),
      _block('Sincerely,', revision),
      _block(header['name'] as String, revision),
    ].join('\n\n');
    parseMaterialDocument(markdown);
    return markdown;
  }

  String compose(Map<String, dynamic> plan, String revision) {
    validate();
    if (!plan.containsKey('selected_ids') &&
        plan['content_revision_id'] != revision) {
      throw StateError(
        'Fixed resume content changed. Read resume_content_get and use its current revision.',
      );
    }
    if (plan.containsKey('selected_ids')) {
      plan = _assemblePlan(plan, revision);
    }
    String dynamicSection(String key, {required bool bullets}) {
      final text = plan[key];
      if (text is! String || text.trim().isEmpty) {
        throw FormatException('$key is required.');
      }
      final blocks = parseMaterialMarkdown(text);
      if (blocks.any(
        (b) =>
            b.level != 0 ||
            b.pageBreak ||
            b.metadataSubtitle ||
            b.bullet != bullets,
      )) {
        throw FormatException(
          '$key allows ${bullets ? 'achievement bullets' : 'paragraphs'} only; headings and fixed content are assembled by CareerShopper.',
        );
      }
      if (key == 'summary_markdown' && blocks.length != 1) {
        throw const FormatException('Use one opening summary paragraph.');
      }
      return text.trim();
    }

    final headline = plan['professional_headline'];
    if (headline is! String ||
        headline.length > 200 ||
        RegExp(r'[<>`*|\r\n]').hasMatch(headline)) {
      throw const FormatException(
        'professional_headline must be plain text on one line, at most 200 characters.',
      );
    }
    final selected = plan['work_history'];
    if (selected is! List) {
      throw const FormatException(
        'work_history must contain selected role and achievement IDs.',
      );
    }
    final choices = <String, Set<String>>{};
    final roles = {
      for (final r in entries('experience').where((r) => r['enabled'] == true))
        r['id']: r,
    };
    for (final raw in selected) {
      if (raw is! Map ||
          raw['entry_id'] is! String ||
          raw['achievement_ids'] is! List) {
        throw const FormatException(
          'Each work-history selection needs entry_id and achievement_ids.',
        );
      }
      final id = raw['entry_id'] as String;
      final role = roles[id];
      final chosen = (raw['achievement_ids'] as List)
          .whereType<String>()
          .toSet();
      if (role == null ||
          choices.containsKey(id) ||
          chosen.length != (raw['achievement_ids'] as List).length ||
          !chosen.every(
            (a) => roleAchievements(role).any((v) => v['id'] == a),
          )) {
        throw const FormatException(
          'Unknown, disabled, duplicate, or wrongly attributed role/achievement selection.',
        );
      }
      for (final title in (role['titles'] as List).cast<Map>()) {
        if ((title['achievements'] as List).isNotEmpty &&
            !(title['achievements'] as List).any(
              (a) => chosen.contains(a['id']),
            )) {
          throw FormatException(
            'Including ${role['employer']} requires at least one achievement under every title, including ${title['title']} (${title['dates']}).',
          );
        }
      }
      for (final achievement in roleAchievements(role)) {
        if (achievement['required'] == true &&
            !chosen.contains(achievement['id'])) {
          throw FormatException(
            'Including ${role['employer']} requires achievement ${achievement['id']}: ${achievement['text']}',
          );
        }
      }
      for (final achievement in roleAchievements(
        role,
      ).where((a) => chosen.contains(a['id']))) {
        final missing = ((achievement['requires'] ?? []) as List)
            .where((dependency) => !chosen.contains(dependency))
            .toList();
        if (missing.isNotEmpty) {
          throw FormatException(
            'Achievement ${achievement['id']} requires these additional achievements from ${role['employer']}: ${missing.join(', ')}. Include their prerequisites too, or omit the dependent achievement.',
          );
        }
      }
      choices[id] = chosen;
    }
    final projectChoices = <String, Set<String>>{};
    final selectedDetails = plan.containsKey('project_details')
        ? plan['project_details']
        : [];
    if (selectedDetails is! List) {
      throw const FormatException(
        'project_details must be a list of project and detail IDs.',
      );
    }
    for (final selection in selectedDetails) {
      if (selection is! Map ||
          selection['entry_id'] is! String ||
          selection['detail_ids'] is! List) {
        throw const FormatException(
          'Each project selection needs entry_id and detail_ids.',
        );
      }
      final id = selection['entry_id'] as String;
      final project = entries(
        'projects',
      ).where((p) => p['id'] == id && p['enabled'] == true).firstOrNull;
      final ids = (selection['detail_ids'] as List).whereType<String>().toSet();
      if (project == null ||
          projectChoices.containsKey(id) ||
          ids.length != (selection['detail_ids'] as List).length ||
          !ids.every(
            (id) => projectDetails(project).any((d) => d['id'] == id),
          )) {
        throw const FormatException(
          'Unknown, disabled, duplicate, or wrongly attributed project/detail selection.',
        );
      }
      for (final detail in projectDetails(project)) {
        if (!ids.contains(detail['id'])) continue;
        final missing = ((detail['requires'] ?? []) as List)
            .where((dependency) => !ids.contains(dependency))
            .toList();
        if (missing.isNotEmpty) {
          throw FormatException(
            'Project detail ${detail['id']} requires these additional sentences from ${project['name']}: ${missing.join(', ')}. Include their prerequisites too, or omit the dependent sentence.',
          );
        }
      }
      projectChoices[id] = ids;
    }
    final result = <String>[
      '---\ndocument_type: resume\n${headline.trim().isEmpty ? '' : 'subtitle: ${headline.trim()}\n'}footer: ${header['name']}\npage_numbers: true\n--- <!-- facts: $revision -->',
      _block('# ${header['name']}', revision),
      if ((header['contact'] as String).isNotEmpty)
        _block(header['contact'] as String, revision),
      dynamicSection('summary_markdown', bullets: false),
      _block('## ${headings['direct_match']}', revision),
      dynamicSection('direct_match_markdown', bullets: true),
      _block('## ${headings['skills']}', revision),
      dynamicSection('core_skills_markdown', bullets: false),
      if (choices.isNotEmpty) _block('## ${headings['experience']}', revision),
      for (final role in entries(
        'experience',
      ).where((r) => choices.containsKey(r['id']))) ...[
        ...roleHeading(role, revision),
        for (final title in (role['titles'] as List).cast<Map>()) ...[
          if ((role['titles'] as List).length > 1)
            titleHeading(title, revision),
          for (final a in (title['achievements'] as List).cast<Map>().where(
            (a) => choices[role['id']]!.contains(a['id']),
          ))
            _block('- ${a['text']}', revision),
        ],
      ],
    ];
    for (final section in ['projects', 'patents', 'education']) {
      final enabled = entries(
        section,
      ).where((r) => r['enabled'] == true).toList();
      if (enabled.isEmpty) continue;
      result.add(_block('## ${headings[section]}', revision));
      for (final entry in enabled) {
        if (section == 'projects') {
          result.addAll([
            ...projectHeading(entry, revision),
            _block(
              [
                entry['description'],
                ...projectDetails(entry)
                    .where(
                      (d) =>
                          projectChoices[entry['id']]?.contains(d['id']) ??
                          false,
                    )
                    .map((d) => d['text']),
              ].join(' '),
              revision,
            ),
          ]);
        } else if (section == 'patents') {
          result.add(_block('- ${entry['text']}', revision));
        } else {
          result.addAll([
            _block('### ${entry['heading']}', revision),
            _block(entry['details'] as String, revision),
          ]);
        }
      }
    }
    final markdown = result.join('\n\n');
    parseMaterialDocument(markdown);
    return markdown;
  }

  /// Infer only permitted selections, then compare the assembled document. This
  /// also protects later exact-text edits and raw Markdown submissions.
  void validateGenerated(String markdown, String revision) {
    final document = parseMaterialDocument(markdown);
    final blocks = document.blocks.where((b) => !b.metadataSubtitle).toList();
    final groups = <String, List<MaterialBlock>>{'opening': []};
    var section = 'opening';
    for (final block in blocks) {
      if (block.level == 2) {
        section = block.text;
        if (groups.containsKey(section)) {
          throw StateError('Repeated resume section.');
        }
        groups[section] = [];
      } else {
        groups[section]!.add(block);
      }
    }
    String asMarkdown(List<MaterialBlock> value) =>
        MaterialDocument(value, {}, []).toMarkdown();
    final opening = groups['opening']!;
    final skip = (header['contact'] as String).isEmpty ? 1 : 2;
    final selections = <Map<String, Object>>[];
    final work = groups[headings['experience']] ?? [];
    Map? role;
    List<String>? achievements;
    Map? title;
    var nextTitle = 0;
    for (final (index, block) in work.indexed) {
      if (block.level == 3) {
        role = entries('experience').where((r) {
          final fixed = parseMaterialMarkdown(
            roleHeading(r, revision).join('\n\n'),
          );
          return index + fixed.length <= work.length &&
              fixed.indexed.every(
                (item) =>
                    work[index + item.$1].text == item.$2.text &&
                    work[index + item.$1].level == item.$2.level &&
                    work[index + item.$1].bullet == item.$2.bullet,
              );
        }).firstOrNull;
        if (role == null) {
          throw StateError(
            'Work-history wording is fixed. Select an existing role.',
          );
        }
        final titles = role['titles'] as List;
        title = titles.length == 1 ? titles.single as Map : null;
        nextTitle = 0;
        achievements = [];
        selections.add({
          'entry_id': role['id'] as String,
          'achievement_ids': achievements,
        });
      } else if (block.bullet) {
        final match = title == null
            ? null
            : (title['achievements'] as List)
                  .cast<Map>()
                  .where(
                    (a) =>
                        a['text'] == block.text &&
                        !achievements!.contains(a['id']),
                  )
                  .firstOrNull;
        if (match == null) {
          throw StateError(
            'Achievement wording and employer attribution are fixed. Select an existing achievement.',
          );
        }
        achievements!.add(match['id'] as String);
      } else if (role != null && (role['titles'] as List).length > 1) {
        final titles = (role['titles'] as List).cast<Map>();
        if (nextTitle < titles.length &&
            block.text ==
                parseMaterialMarkdown(
                  titleHeading(titles[nextTitle], revision),
                ).single.text) {
          title = titles[nextTitle++];
        }
      }
    }
    final projectSelections = <Map<String, Object>>[];
    final projectBlocks = groups[headings['projects']] ?? [];
    var cursor = 0;
    for (final project in entries(
      'projects',
    ).where((p) => p['enabled'] == true)) {
      final prefix = parseMaterialMarkdown(
        projectHeading(project, revision).join('\n\n'),
      );
      if (cursor + prefix.length >= projectBlocks.length ||
          !prefix.indexed.every(
            (item) => item.$2.text == projectBlocks[cursor + item.$1].text,
          )) {
        throw StateError(
          'Every enabled project must retain its fixed heading and summary.',
        );
      }
      cursor += prefix.length;
      projectSelections.add({
        'entry_id': project['id'] as String,
        'detail_ids': _inferProjectDetails(
          project,
          projectBlocks[cursor++].text,
        ),
      });
    }
    final expected = compose({
      'content_revision_id': revision,
      'professional_headline': document.metadata['subtitle'] ?? '',
      'summary_markdown': asMarkdown(opening.skip(skip).toList()),
      'direct_match_markdown': asMarkdown(
        groups[headings['direct_match']] ?? [],
      ),
      'core_skills_markdown': asMarkdown(groups[headings['skills']] ?? []),
      'work_history': selections,
      'project_details': projectSelections,
    }, revision);
    if (document.toMarkdown() != parseMaterialDocument(expected).toMarkdown()) {
      throw StateError(
        'Fixed resume content was changed, omitted, added, or reordered. Only the professional headline, opening summary, direct match, core skills, work-history selections, and project-detail selections may vary. Submit resume_plan to assemble the fixed wording.',
      );
    }
  }
}
