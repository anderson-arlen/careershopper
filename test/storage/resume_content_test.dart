import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/resume_content_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixedContent() => {
  ...ResumeContent.empty(),
  'header': {
    'name': 'Alex Example',
    'headline': 'Software Engineer',
    'contact': 'alex@example.test',
  },
  'experience': [
    {
      'id': 'current',
      'enabled': true,
      'employer': 'Current Company',
      'title': 'Engineer',
      'location': 'Remote',
      'dates': '2019 to Present',
      'achievements': [
        {'id': 'search-achievement', 'text': 'Implemented a search feature.'},
        {'id': 'ci', 'text': 'Added automated checks.'},
      ],
    },
    {
      'id': 'previous',
      'enabled': true,
      'employer': 'Previous Company',
      'title': 'Developer',
      'location': 'Montana',
      'dates': '2016 to 2019',
      'achievements': [
        {'id': 'report-achievement', 'text': 'Updated a reporting tool.'},
      ],
    },
  ],
  'projects': [
    {
      'id': 'project',
      'enabled': true,
      'name': 'Public Project',
      'stack': 'Dart, Go',
      'dates': '2026 to Present',
      'url': 'https://example.test',
      'description': 'Built a public product with a local database.',
    },
    {
      'id': 'disabled',
      'enabled': false,
      'name': 'Omitted Project',
      'stack': '',
      'dates': '',
      'url': '',
      'description': 'Do not include this entry.',
    },
  ],
  'patents': [
    {
      'id': 'patent',
      'enabled': true,
      'text': 'U.S. Patent No. 123, Exact patent title (2025).',
    },
  ],
  'education': [
    {
      'id': 'school',
      'enabled': true,
      'heading': 'Example School',
      'details': 'Exact qualification and dates.',
    },
  ],
};
Map<String, dynamic> plan(String revision) => {
  'content_revision_id': revision,
  'professional_headline': 'Software Engineer',
  'summary_markdown':
      'Engineer with production ownership. <!-- facts: $revision -->',
  'direct_match_markdown':
      '- **Leadership:** Led delivery teams. <!-- facts: $revision -->',
  'core_skills_markdown': '**Languages:** Dart, Go. <!-- facts: $revision -->',
  // Input order does not change the user-owned order.
  'work_history': [
    {
      'entry_id': 'previous',
      'achievement_ids': ['report-achievement'],
    },
    {
      'entry_id': 'current',
      'achievement_ids': ['ci', 'search-achievement'],
    },
  ],
};

Map<String, dynamic> structuredPlan() => {
  'professional_headline': 'Software Engineer',
  'summary': {
    'text': 'Engineer with production ownership.',
    'support_ids': ['F2'],
  },
  'direct_match': [
    {
      'label': 'Leadership:',
      'text': 'Led delivery teams.',
      'support_ids': ['F2', 'F5'],
    },
  ],
  'core_skills': [
    {
      'label': 'Languages:',
      'text': 'Dart, Go.',
      'support_ids': ['F6'],
    },
  ],
  'selected_ids': ['F2', 'F3', 'F5'],
};

void main() {
  test(
    'project dependencies enforce directional chains and cycles in plans and raw documents',
    () {
      final content = ResumeContent(fixedContent());
      final details = <Map<String, dynamic>>[
        {'id': 'base', 'text': 'Built an API.'},
        {
          'id': 'rollout',
          'text': 'Rolled it out incrementally.',
          'requires': ['base'],
        },
        {
          'id': 'scale',
          'text': 'Expanded its capacity.',
          'requires': ['rollout'],
        },
      ];
      content.entries('projects').first['details'] = details;
      Map<String, dynamic> selection(List<String> ids) => {
        ...plan('revision'),
        'project_details': [
          {'entry_id': 'project', 'detail_ids': ids},
        ],
      };
      for (final ids in <List<String>>[
        [],
        ['base'],
        ['base', 'rollout'],
        ['base', 'rollout', 'scale'],
      ]) {
        final markdown = content.compose(selection(ids), 'revision');
        content.validateGenerated(markdown, 'revision');
      }
      for (final ids in [
        ['rollout'],
        ['scale'],
        ['base', 'scale'],
        ['rollout', 'scale'],
      ]) {
        expect(
          () => content.compose(selection(ids), 'revision'),
          throwsFormatException,
        );
      }
      final markdown = content.compose(
        selection(['base', 'rollout', 'scale']),
        'revision',
      );
      expect(
        () => content.validateGenerated(
          markdown.replaceFirst(' Built an API.', ''),
          'revision',
        ),
        throwsA(isA<Exception>()),
      );
      details.first['requires'] = ['scale'];
      content.validate();
      expect(
        () => content.compose(selection(['base']), 'revision'),
        throwsFormatException,
      );
      content.validateGenerated(
        content.compose(selection(['base', 'rollout', 'scale']), 'revision'),
        'revision',
      );
      content.compose(selection([]), 'revision');
    },
  );

  test(
    'project dependency references cannot be malformed, dangling or cross project',
    () {
      final content = ResumeContent(fixedContent());
      final details = <Map<String, dynamic>>[
        {'id': 'base', 'text': 'Built an API.'},
        {'id': 'detail', 'text': 'Rolled it out.'},
      ];
      content.entries('projects').first['details'] = details;
      content.entries('projects').last['details'] = [
        {'id': 'other', 'text': 'Another project detail.'},
      ];
      for (final invalid in <Object?>[
        null,
        'base',
        [3],
        ['detail'],
        ['other'],
        ['search-achievement'],
        ['missing'],
        ['base', 'base'],
      ]) {
        details.last['requires'] = invalid;
        expect(content.validate, throwsFormatException, reason: '$invalid');
      }
      details.last['requires'] = ['base'];
      content.validate();
      details.removeAt(0);
      expect(content.validate, throwsFormatException);
    },
  );

  test(
    'achievement dependencies enforce directional and transitive inclusion without rewriting',
    () {
      final content = ResumeContent(fixedContent());
      final role = content.entries('experience').first;
      final achievements = role['titles'][0]['achievements'] as List;
      achievements.add({
        'id': 'rollout',
        'text': 'Rolled the rebuilt platform out incrementally.',
        'requires': ['ci'],
      });
      (achievements[1] as Map)['requires'] = ['search-achievement'];
      Map<String, dynamic> selected(List<String> ids) => {
        ...plan('revision'),
        'work_history': [
          {'entry_id': 'current', 'achievement_ids': ids},
        ],
      };
      for (final ids in [
        ['search-achievement'],
        ['search-achievement', 'ci'],
        ['rollout', 'ci', 'search-achievement'],
      ]) {
        final markdown = content.compose(selected(ids), 'revision');
        content.validateGenerated(markdown, 'revision');
        if (ids.contains('rollout')) {
          expect(
            markdown.indexOf('Implemented a search'),
            lessThan(markdown.indexOf('Added automated')),
          );
          expect(
            markdown.indexOf('Added automated'),
            lessThan(markdown.indexOf('Rolled the rebuilt')),
          );
          expect(
            () => content.validateGenerated(
              markdown.replaceFirst(
                '- Added automated checks. <!-- facts: revision -->',
                '',
              ),
              'revision',
            ),
            throwsFormatException,
          );
        }
      }
      for (final ids in [
        ['ci'],
        ['rollout'],
        ['ci', 'rollout'],
      ]) {
        expect(
          () => content.compose(selected(ids), 'revision'),
          throwsFormatException,
        );
      }
      // A required bullet also brings its prerequisite obligations.
      (achievements[2] as Map)['required'] = true;
      expect(
        () => content.compose(selected(['search-achievement', 'rollout']), 'revision'),
        throwsFormatException,
      );
      expect(
        content.compose({...plan('revision'), 'work_history': []}, 'revision'),
        isNot(contains('Current Company')),
      );
      // Links survive moving achievements to another title in the same job.
      final moved = achievements.removeLast();
      (role['titles'] as List).add({
        'title': 'Lead',
        'dates': '2015 to 2019',
        'achievements': [moved],
      });
      content.validateGenerated(
        content.compose(selected(['search-achievement', 'ci', 'rollout']), 'revision'),
        'revision',
      );
    },
  );

  test(
    'dependency validation rejects dangling cross-job self and duplicate links',
    () {
      final content = ResumeContent(fixedContent());
      final achievement = content
          .roleAchievements(content.entries('experience').first)
          .last;
      for (final invalid in <dynamic>[
        null,
        'search-achievement',
        [1],
        ['ci'],
        ['report-achievement'],
        ['missing'],
        ['search-achievement', 'search-achievement'],
      ]) {
        achievement['requires'] = invalid;
        expect(content.validate, throwsFormatException);
      }
      achievement['requires'] = ['search-achievement'];
      content.validate();
      (content.entries('experience').first['titles'][0]['achievements'] as List)
          .removeAt(0);
      expect(content.validate, throwsFormatException);
    },
  );

  test('mutual dependencies require the whole group and do not recurse', () {
    final content = ResumeContent(fixedContent());
    final achievements = content.roleAchievements(
      content.entries('experience').first,
    );
    achievements.first['requires'] = ['ci'];
    achievements.last['requires'] = ['search-achievement'];
    final markdown = content.compose(plan('revision'), 'revision');
    content.validateGenerated(markdown, 'revision');
    expect(
      () => content.compose({
        ...plan('revision'),
        'work_history': [
          {
            'entry_id': 'current',
            'achievement_ids': ['search-achievement'],
          },
        ],
      }, 'revision'),
      throwsFormatException,
    );
  });

  test(
    'required achievements are enforced only when their job is included',
    () {
      final content = ResumeContent(fixedContent());
      final achievements = content.roleAchievements(
        content.entries('experience').first,
      );
      achievements.first.addAll(<String, dynamic>{
        'priority': 90,
        'required': true,
      });
      achievements.last['priority'] = 10;
      final complete = content.compose(plan('revision'), 'revision');
      content.validateGenerated(complete, 'revision');
      final missing = plan('revision');
      (missing['work_history'] as List).last['achievement_ids'] = ['ci'];
      expect(() => content.compose(missing, 'revision'), throwsFormatException);
      expect(
        () => content.validateGenerated(
          complete.replaceFirst(
            '- Implemented a search feature. <!-- facts: revision -->',
            '',
          ),
          'revision',
        ),
        throwsFormatException,
      );
      (missing['work_history'] as List).removeLast();
      expect(
        content.compose(missing, 'revision'),
        isNot(contains('Current Company')),
      );
      achievements.first['required'] = false;
      expect(
        content.compose({
          ...plan('revision'),
          'work_history': [
            {
              'entry_id': 'current',
              'achievement_ids': ['ci'],
            },
          ],
        }, 'revision'),
        isNot(contains('Implemented a search')),
      );
      expect(
        complete.indexOf('Implemented a search feature.'),
        lessThan(complete.indexOf('Added automated checks.')),
      );
      for (final invalid in [-1, 101, 1.5, '90', null]) {
        achievements.first['priority'] = invalid;
        expect(content.validate, throwsFormatException);
      }
      achievements.first['priority'] = 0;
      achievements.first['required'] = 'yes';
      expect(content.validate, throwsFormatException);
    },
  );

  test(
    'project summary is mandatory and optional sentences are selected verbatim in saved order',
    () {
      final content = ResumeContent(fixedContent());
      final project = content.entries('projects').first;
      project['details'] = [
        {'id': 'p-api', 'text': 'Built the API in Go.'},
        {'id': 'p-storage', 'text': 'Stored offline data in SQLite.'},
        {'id': 'p-ui', 'text': 'Built the interface in Dart.'},
      ];
      for (final ids in <List<String>>[
        [],
        ['p-storage'],
        ['p-ui', 'p-api'],
        ['p-api', 'p-storage', 'p-ui'],
      ]) {
        final markdown = content.compose({
          ...plan('revision'),
          'project_details': [
            {'entry_id': 'project', 'detail_ids': ids},
          ],
        }, 'revision');
        expect(markdown, contains(project['description']));
        for (final detail in project['details'] as List) {
          expect(
            markdown.contains(detail['text'] as String),
            ids.contains(detail['id']),
          );
        }
        if (ids.contains('p-api') && ids.contains('p-ui')) {
          expect(
            markdown.indexOf('Built the API'),
            lessThan(markdown.indexOf('Built the interface')),
          );
        }
        content.validateGenerated(markdown, 'revision');
      }
      final all = content.compose({
        ...plan('revision'),
        'project_details': [
          {
            'entry_id': 'project',
            'detail_ids': ['p-api', 'p-storage', 'p-ui'],
          },
        ],
      }, 'revision');
      for (final changed in [
        all.replaceFirst(project['description'] as String, ''),
        all.replaceFirst('Built the API in Go.', 'Built the API.'),
        all.replaceFirst(
          'Built the API in Go. Stored offline data in SQLite.',
          'Stored offline data in SQLite. Built the API in Go.',
        ),
        all.replaceFirst('Built the API in Go.', 'Invented a new database.'),
      ]) {
        expect(
          () => content.validateGenerated(changed, 'revision'),
          throwsA(anything),
        );
      }
      expect(
        content.compose(plan('revision'), 'revision'),
        isNot(contains('Built the API in Go.')),
      );
      for (final selection in [
        [
          {
            'entry_id': 'project',
            'detail_ids': ['unknown'],
          },
        ],
        [
          {'entry_id': 'disabled', 'detail_ids': []},
        ],
        [
          {'entry_id': 'unknown', 'detail_ids': []},
        ],
        [
          {
            'entry_id': 'project',
            'detail_ids': ['p-api', 'p-api'],
          },
        ],
        [
          {'entry_id': 'project', 'detail_ids': []},
          {'entry_id': 'project', 'detail_ids': []},
        ],
      ]) {
        expect(
          () => content.compose({
            ...plan('revision'),
            'project_details': selection,
          }, 'revision'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'project detail IDs remain unique and cannot be borrowed across projects',
    () {
      final content = ResumeContent(fixedContent());
      final projects = content.entries('projects');
      projects.first['details'] = [
        {'id': 'detail', 'text': 'Built in Go.'},
      ];
      projects.last['enabled'] = true;
      projects.last['details'] = [
        {'id': 'other-detail', 'text': 'Used SQLite.'},
      ];
      expect(
        () => content.compose({
          ...plan('revision'),
          'project_details': [
            {
              'entry_id': 'project',
              'detail_ids': ['other-detail'],
            },
          ],
        }, 'revision'),
        throwsFormatException,
      );
      projects.last['details'] = [
        {'id': 'detail', 'text': 'Used SQLite.'},
      ];
      expect(content.validate, throwsFormatException);
      projects.last['details'] = [
        {'id': 'other-detail', 'text': ''},
      ];
      expect(content.validate, throwsFormatException);
    },
  );

  test(
    'overlapping optional sentences validate without splitting their wording',
    () {
      final content = ResumeContent(fixedContent());
      content.entries('projects').first['details'] = [
        {'id': 'short', 'text': 'Built the API.'},
        {'id': 'long', 'text': 'Built the API. Used Go.'},
      ];
      for (final ids in [
        ['short'],
        ['long'],
        ['short', 'long'],
      ]) {
        final markdown = content.compose({
          ...plan('revision'),
          'project_details': [
            {'entry_id': 'project', 'detail_ids': ids},
          ],
        }, 'revision');
        content.validateGenerated(markdown, 'revision');
      }
    },
  );

  test(
    'title histories remain grouped, ordered and immutable when selecting an employment entry',
    () {
      final content = ResumeContent(fixedContent());
      final role = content.entries('experience').first;
      final achievements =
          (role['titles'] as List).single['achievements'] as List;
      role['titles'] = [
        {
          'title': 'Senior Engineer',
          'dates': '2020 to Present',
          'achievements': [achievements.first],
        },
        {
          'title': 'Senior Developer',
          'dates': '2019 to 2020',
          'achievements': [achievements.last],
        },
      ];
      final markdown = content.compose(plan('revision'), 'revision');
      expect(
        markdown,
        contains('### Current Company <!-- facts: revision -->'),
      );
      expect(markdown, contains('**Senior Engineer** · 2020 to Present'));
      expect(markdown, contains('**Senior Developer** · 2019 to 2020'));
      expect(
        markdown.indexOf('Senior Engineer'),
        lessThan(markdown.indexOf('Senior Developer')),
      );
      expect(
        markdown.indexOf('Implemented a search feature.'),
        lessThan(markdown.indexOf('Senior Developer')),
      );
      content.validateGenerated(markdown, 'revision');
      for (final changed in [
        markdown.replaceFirst('2020 to Present', '2019 to Present'),
        markdown.replaceFirst('**Senior Developer**', '**Junior Developer**'),
        markdown.replaceFirst(
          '**Senior Developer** · 2019 to 2020 <!-- facts: revision -->\n\n',
          '',
        ),
        markdown.replaceFirst(
          '**Senior Engineer** · 2020 to Present',
          '**Senior Developer** · 2019 to 2020',
        ),
      ]) {
        expect(
          () => content.validateGenerated(changed, 'revision'),
          throwsA(anything),
        );
      }
      final incomplete = plan('revision');
      (incomplete['work_history'] as List).last['achievement_ids'] = ['search-achievement'];
      expect(
        () => content.compose(incomplete, 'revision'),
        throwsFormatException,
      );
      expect(
        () => content.validateGenerated(
          markdown.replaceFirst(
            '- Added automated checks. <!-- facts: revision -->',
            '',
          ),
          'revision',
        ),
        throwsA(anything),
      );
      (role['titles'] as List).last['achievements'] = [];
      content.validate();
      expect(
        () => content.compose(plan('revision'), 'revision'),
        throwsFormatException,
      );
      (incomplete['work_history'] as List).removeLast();
      expect(
        content.compose(incomplete, 'revision'),
        isNot(contains('Current Company')),
      );
      role['titles'] = [];
      expect(content.validate, throwsFormatException);
      role['titles'] = [
        {'title': '', 'dates': '2019 to Present'},
      ];
      expect(content.validate, throwsFormatException);
    },
  );

  test('identical achievement wording stays attributed to each title', () {
    final content = ResumeContent(fixedContent());
    final role = content.entries('experience').first;
    role['titles'] = [
      {
        'title': 'Engineer',
        'dates': '2020 to Present',
        'achievements': [
          {'id': 'search-achievement', 'text': 'Delivered production services.'},
        ],
      },
      {
        'title': 'Developer',
        'dates': '2019 to 2020',
        'achievements': [
          {'id': 'ci', 'text': 'Delivered production services.'},
        ],
      },
    ];
    final markdown = content.compose(plan('revision'), 'revision');
    content.validateGenerated(markdown, 'revision');
    final withoutFirstBullet = markdown.replaceFirst(
      '- Delivered production services. <!-- facts: revision -->',
      '',
    );
    expect(
      () => content.validateGenerated(withoutFirstBullet, 'revision'),
      throwsA(anything),
    );
  });

  test(
    'legacy single-title entries retain their wording and render unchanged',
    () {
      final legacy = fixedContent();
      final content = ResumeContent(legacy);
      expect(content.entries('experience').first['titles'], [
        {
          'title': 'Engineer',
          'dates': '2019 to Present',
          'achievements': (legacy['experience'] as List).first['achievements'],
        },
      ]);
      expect(content.entries('experience').first.containsKey('title'), false);
      expect((legacy['experience'] as List).first['title'], 'Engineer');
      final markdown = content.compose(plan('revision'), 'revision');
      expect(
        markdown,
        contains(
          '### Current Company, Engineer <!-- facts: revision -->\n\n*Remote · 2019 to Present*',
        ),
      );
      content.validateGenerated(markdown, 'revision');
    },
  );

  test(
    'generated headlines override legacy wording and can change during revisions',
    () {
      final data = fixedContent();
      (data['header'] as Map)['headline'] = 'Legacy Role Headline';
      final content = ResumeContent(data);
      final generated = content.compose(
        plan('revision')
          ..['professional_headline'] = 'Senior Software Engineer',
        'revision',
      );
      expect(generated, contains('subtitle: Senior Software Engineer'));
      expect(generated, isNot(contains('Legacy Role Headline')));
      content.validateGenerated(
        generated.replaceFirst(
          'subtitle: Senior Software Engineer',
          'subtitle: Staff Software Engineer',
        ),
        'revision',
      );
      for (final headline in [
        'Engineer\nfooter: someone else',
        '**Engineer**',
        '<!-- facts: other -->',
        'x' * 201,
      ]) {
        expect(
          () => content.compose(
            plan('revision')..['professional_headline'] = headline,
            'revision',
          ),
          throwsFormatException,
        );
      }
      final omitted = content.compose(
        plan('revision')..['professional_headline'] = '',
        'revision',
      );
      expect(omitted, isNot(contains('subtitle:')));
      content.validateGenerated(omitted, 'revision');
      (data['header'] as Map).remove('headline');
      ResumeContent(data).validate();
    },
  );

  test(
    'assembly preserves wording, attribution, ordering and project heading weight',
    () {
      final content = ResumeContent(fixedContent());
      final markdown = content.compose(plan('revision'), 'revision');
      content.validateGenerated(markdown, 'revision');
      expect(
        markdown.indexOf('Current Company'),
        lessThan(markdown.indexOf('Previous Company')),
      );
      expect(
        markdown.indexOf('Implemented a search feature.'),
        lessThan(markdown.indexOf('Added automated checks.')),
      );
      expect(markdown, contains('### **Public Project** · Dart, Go'));
      expect(
        markdown,
        contains(
          'Built a public product with a local database. <!-- facts: revision -->',
        ),
      );
      expect(
        markdown,
        contains('U.S. Patent No. 123, Exact patent title (2025).'),
      );
      expect(markdown, isNot(contains('Omitted Project')));
      expect(markdown, contains('Exact qualification and dates.'));
    },
  );

  test(
    'AI can vary its headline, three sections and valid work-history selections',
    () {
      final content = ResumeContent(fixedContent());
      final selected = plan('revision')
        ..['work_history'] = [
          {
            'entry_id': 'current',
            'achievement_ids': ['ci'],
          },
        ];
      final markdown = content.compose(selected, 'revision');
      expect(markdown, isNot(contains('Previous Company')));
      expect(markdown, isNot(contains('Implemented a search')));
      content.validateGenerated(
        markdown.replaceFirst(
          'Engineer with production ownership.',
          'Engineer with delivery experience.',
        ),
        'revision',
      );
      for (final change in [
        markdown.replaceFirst('Engineer <!--', 'Principal Engineer <!--'),
        markdown.replaceFirst(
          'Added automated checks.',
          'Built CI and a React app.',
        ),
        markdown.replaceFirst(
          'Built a public product with a local database.',
          'New project description.',
        ),
        markdown.replaceFirst('Exact patent title', 'Improved patent title'),
        markdown.replaceFirst(
          'Exact qualification and dates.',
          'Different qualification.',
        ),
        markdown.replaceFirst('CORE SKILLS', 'OTHER SKILLS'),
        markdown.replaceFirst('alex@example.test', 'other@example.test'),
        markdown.replaceFirst(
          '## PATENTS <!-- facts: revision -->\n\n- U.S. Patent No. 123, Exact patent title (2025). <!-- facts: revision -->\n\n',
          '',
        ),
        '$markdown\n\n## NEW SECTION <!-- facts: revision -->',
      ]) {
        expect(
          () => content.validateGenerated(change, 'revision'),
          throwsA(anything),
        );
      }
    },
  );

  test('rejects wrong-employer, duplicate, disabled and stale selections', () {
    final data = fixedContent();
    (data['experience'] as List)[1]['enabled'] = false;
    final content = ResumeContent(data);
    for (final selection in [
      [
        {
          'entry_id': 'current',
          'achievement_ids': ['report-achievement'],
        },
      ],
      [
        {
          'entry_id': 'current',
          'achievement_ids': ['ci', 'ci'],
        },
      ],
      [
        {'entry_id': 'previous', 'achievement_ids': []},
      ],
      [
        {'entry_id': 'unknown', 'achievement_ids': []},
      ],
    ]) {
      expect(
        () => content.compose(
          plan('revision')..['work_history'] = selection,
          'revision',
        ),
        throwsFormatException,
      );
    }
    expect(() => content.compose(plan('old'), 'revision'), throwsStateError);
    expect(
      () => content.compose(
        plan('revision')
          ..['summary_markdown'] =
              '## Injected heading <!-- facts: revision -->',
        'revision',
      ),
      throwsFormatException,
    );
  });

  test(
    'prefill remains unsaved, excludes private facts and binds achievements to their employer',
    () async {
      final db = CareerShopperDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final profile = ProfileRepository(db);
      Future<String> fact(
        String kind,
        Map<String, dynamic> value, {
        String visibility = 'resume',
      }) => profile.saveCareerFact(
        CareerFactDraft(kind: kind, value: value, visibility: visibility),
        actor: 'user',
      );
      await fact('identity', {'field': 'name', 'text': 'Alex Example'});
      final current = await fact('employment', {
        'employer': 'Current Company',
        'title': 'Engineer',
        'start': {'value': '2019-04'},
        'end_status': 'current',
      });
      final previous = await fact('employment', {
        'employer': 'Previous Company',
        'title': 'Developer',
        'start': {'value': '2016-04'},
        'end': {'value': '2019-04'},
      });
      await fact('achievement', {
        'statement': 'Implemented a search feature.',
        'context_fact_ids': [current],
      });
      await fact('achievement', {
        'statement': 'Updated a reporting tool.',
        'context_fact_ids': [previous],
      });
      await fact('achievement', {
        'statement': 'Ambiguous employer.',
        'context_fact_ids': [previous, current],
      });
      await fact('project', {
        'name': 'Stealth',
        'description': 'Private product',
      }, visibility: 'private');
      final repository = ResumeContentRepository(profile);
      final draft = await repository.get();
      expect(draft['configured'], false);
      expect(await repository.read(), isNull);
      final content = draft['content'] as Map<String, dynamic>;
      ResumeContent(content).validate();
      final roles = content['experience'] as List;
      expect(roles.first['employer'], 'Current Company');
      expect(roles.first['titles'], hasLength(1));
      expect(roles.first['titles'][0]['title'], 'Engineer');
      expect(roles.first['titles'][0]['dates'], 'April 2019 to Present');
      expect(roles.first['titles'][0]['achievements'], hasLength(1));
      expect(
        roles.first['titles'][0]['achievements'][0]['text'],
        'Implemented a search feature.',
      );
      expect(
        roles.last['titles'][0]['achievements'][0]['text'],
        'Updated a reporting tool.',
      );
      expect(content['projects'], isEmpty);
      await repository.save(content, expectedRevision: null, actor: 'user');
      final saved = await repository.read();
      expect(saved, isNotNull);
      expect(saved!.canDiscloseInApplications, true);
      await expectLater(
        repository.save(content, expectedRevision: null, actor: 'user'),
        throwsStateError,
      );
      await repository.save(
        content,
        expectedRevision: saved.revisionId,
        actor: 'user',
      );
      expect((await repository.read())!.revisionId, isNot(saved.revisionId));
      expect(
        (await profile.watchCareerFacts().first).where(
          (f) => f.kind == 'employment',
        ),
        hasLength(2),
      );
    },
  );
}
