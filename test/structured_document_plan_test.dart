import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/documents/material_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'storage/resume_content_test.dart' as fixture;

void main() {
  test('short catalog replaces persistent IDs and omits hidden content', () {
    final content = ResumeContent(fixture.fixedContent());
    final catalog = content.generationContent;
    expect(catalog['experience'][0]['id'], 'F1');
    expect(
      catalog['experience'][0]['titles'][0]['achievements'][0]['id'],
      'F2',
    );
    expect(catalog['projects'].toString(), isNot(contains('Omitted Project')));
    expect(catalog.toString(), isNot(contains('search-achievement')));
    final markdown = content.compose(fixture.structuredPlan(), 'revision');
    content.validateGenerated(markdown, 'revision');
    expect(markdown, contains('Implemented a search feature.'));
    expect(markdown, isNot(contains('facts: F')));
    expect(
      parseMaterialMarkdown(
        markdown,
      ).every((b) => b.factIds.single == 'revision'),
      isTrue,
    );
  });

  test(
    'selection closes required chains and cycles, fills titles by priority and retains order',
    () {
      final content = ResumeContent(fixture.fixedContent());
      final role = content.entries('experience').first;
      role['titles'] = [
        {
          'title': 'Lead',
          'dates': '2020 to Present',
          'achievements': [
            {
              'id': 'lead',
              'text': 'Led delivery.',
              'requires': ['design'],
            },
            {
              'id': 'required',
              'text': 'Maintained service quality.',
              'required': true,
              'requires': ['lead'],
            },
          ],
        },
        {
          'title': 'Developer',
          'dates': '2019 to 2020',
          'achievements': [
            {
              'id': 'design',
              'text': 'Designed the service.',
              'requires': ['lead'],
            },
          ],
        },
        {
          'title': 'Junior',
          'dates': '2015 to 2019',
          'achievements': [
            {'id': 'low', 'text': 'Completed training.', 'priority': 1},
            {
              'id': 'high',
              'text': 'Built the first implementation.',
              'priority': 90,
            },
            {
              'id': 'tie',
              'text': 'Wrote implementation notes.',
              'priority': 90,
            },
          ],
        },
        {'title': 'Intern', 'dates': '2014', 'achievements': []},
      ];
      content.validate();
      final plan = {
        'professional_headline': 'Software Engineer',
        'summary': {
          'text': 'Led delivery.',
          'support_ids': ['F2'],
        },
        'direct_match': [
          {
            'text': 'Designed services.',
            'support_ids': ['F4'],
          },
        ],
        'core_skills': [
          {
            'text': 'Service delivery.',
            'support_ids': ['F2'],
          },
        ],
        'selected_ids': ['F2'],
      };
      final markdown = content.compose(plan, 'revision');
      expect(markdown, contains('Maintained service quality.'));
      expect(markdown, contains('Designed the service.'));
      expect(markdown, contains('Built the first implementation.'));
      expect(markdown, isNot(contains('Completed training.')));
      expect(markdown, isNot(contains('Wrote implementation notes.')));
      expect(markdown, contains('**Intern** · 2014'));
      expect(
        markdown.indexOf('Led delivery. <!--'),
        lessThan(markdown.indexOf('Maintained service quality. <!--')),
      );
      content.validateGenerated(markdown, 'revision');
      // A later raw edit cannot remove a prerequisite that assembly added.
      expect(
        () => content.validateGenerated(
          markdown.replaceFirst(
            '- Designed the service. <!-- facts: revision -->',
            '',
          ),
          'revision',
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'project prerequisites close automatically and every prose object receives a citation',
    () {
      final content = ResumeContent(fixture.fixedContent());
      content.entries('projects').first['details'] = [
        {
          'id': 'base',
          'text': 'Built an API.',
          'requires': ['deploy'],
        },
        {
          'id': 'deploy',
          'text': 'Deployed the API.',
          'requires': ['base'],
        },
      ];
      final plan = fixture.structuredPlan()
        ..['selected_ids'] = ['F8']
        ..['core_skills'] = [
          {
            'label': 'Languages:',
            'text': 'Dart,\n\nGo.',
            'support_ids': ['F6'],
          },
          {
            'label': 'Delivery:',
            'text': 'API deployment.',
            'support_ids': ['F8'],
          },
        ];
      final markdown = content.compose(plan, 'revision');
      expect(
        markdown,
        contains(
          'Built a public product with a local database. Built an API. Deployed the API.',
        ),
      );
      expect(
        markdown,
        contains('**Languages:** Dart, Go. <!-- facts: revision -->'),
      );
      expect(
        markdown,
        contains('**Delivery:** API deployment. <!-- facts: revision -->'),
      );
      content.validateGenerated(markdown, 'revision');
    },
  );

  test(
    'cover letter assembly supplies framing and validates short evidence IDs',
    () {
      final content = ResumeContent(fixture.fixedContent());
      final plan = {
        'paragraphs': [
          {
            'text': 'I led teams that delivered software.',
            'support_ids': ['F2'],
          },
          {
            'text': 'I built a public product using Dart and Go.',
            'support_ids': ['F6'],
          },
        ],
      };
      final markdown = content.composeCoverLetter(plan, 'revision');
      expect(markdown, contains('# Alex Example <!-- facts: revision -->'));
      expect(markdown, contains('alex@example.test <!-- facts: revision -->'));
      expect(markdown, contains('Dear Hiring Team, <!-- facts: revision -->'));
      expect(markdown, contains('Sincerely, <!-- facts: revision -->'));
      expect(
        parseMaterialMarkdown(
          markdown,
        ).every((b) => b.factIds.single == 'revision'),
        isTrue,
      );
      for (final id in ['F999', 'disabled', 'search-achievement', '']) {
        final bad = fixture.structuredPlan()..['selected_ids'] = [id];
        expect(() => content.compose(bad, 'revision'), throwsFormatException);
        expect(
          () => content.composeCoverLetter({
            'paragraphs': [
              {
                'text': 'A claim.',
                'support_ids': [id],
              },
              {
                'text': 'Another claim.',
                'support_ids': ['F2'],
              },
            ],
          }, 'revision'),
          throwsFormatException,
        );
      }
      expect(
        () => content.compose(
          fixture.structuredPlan()
            ..['summary'] = {'text': 'Unsupported.', 'support_ids': []},
          'revision',
        ),
        throwsFormatException,
      );
    },
  );
}
