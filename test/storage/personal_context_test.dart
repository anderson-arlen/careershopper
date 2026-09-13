import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/resume_content_repository.dart';
import 'package:careershopper/src/protocol/mcp_ui_tools.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'resume_content_test.dart' as fixture;

void main() {
  test(
    'personal context survives MCP save and supports cited prose, not fixed resume sections',
    () async {
      final db = CareerShopperDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final content = fixture.fixedContent()
        ..['personal_context'] = [
          {
            'id': 'gardening',
            'enabled': true,
            'topic': 'Gardening',
            'text': 'I volunteer in a community garden.',
          },
          {
            'id': 'private',
            'enabled': false,
            'topic': 'Private interest',
            'text':
                'A personal interest that I do not want disclosed in applications.',
          },
        ];
      final tools = McpUiTools(db);
      final saved = await tools.call('resume_content_save', {
        'content': content,
        'confirmed': true,
      });
      expect((saved['content'] as Map)['personal_context'], hasLength(2));
      final repository = ResumeContentRepository(ProfileRepository(db));
      expect(
        ((await repository.evidence(forMatching: true)).single.value
            as Map)['personal_context'],
        hasLength(2),
      );
      final visible = (await repository.evidence()).single;
      expect((visible.value as Map)['personal_context'], hasLength(1));
      final model = ResumeContent(
        (visible.value as Map).cast<String, dynamic>(),
      );
      final short =
          (model.generationContent['personal_context'] as List).single['id'];
      final letter = model.composeCoverLetter({
        'paragraphs': [
          {
            'text':
                'As a community gardener, I understand seasonal planting schedules.',
            'support_ids': [short],
          },
          {
            'text':
                'My gardening interest helps me understand the people using these tools.',
            'support_ids': [short],
          },
        ],
      }, visible.revisionId);
      expect(letter, contains('As a community gardener'));
      expect(letter, contains(visible.revisionId));
      final resume = model.compose(
        fixture.structuredPlan(),
        visible.revisionId,
      );
      expect(resume, isNot(contains('community gardener')));
      expect(resume, isNot(contains('Personal context')));
      final all = ResumeContent(content);
      expect(
        () => all.validateDisclosure(
          'A personal interest that I do not want disclosed in applications.',
        ),
        throwsFormatException,
      );
      expect(
        () => all.composeCoverLetter({
          'paragraphs': [
            {
              'text': 'I led a team.',
              'support_ids': ['F2'],
            },
            {
              'text': 'Unsupported license.',
              'support_ids': ['private'],
            },
          ],
        }, visible.revisionId),
        throwsFormatException,
      );
    },
  );

  test('legacy content gains no invented personal facts', () {
    final old = fixture.fixedContent()..remove('personal_context');
    final content = ResumeContent(old);
    content.validate();
    expect(content.data['personal_context'], isEmpty);
  });
}
