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
    'explicit import preserves proficiency and limits, excludes private/pending and never overwrites edits',
    () async {
      final db = CareerShopperDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final profile = ProfileRepository(db);
      final repository = ResumeContentRepository(profile);
      await repository.save(
        fixture.fixedContent(),
        expectedRevision: null,
        actor: 'user',
      );
      for (final name in ['Ruby', 'Private skill', 'Pending skill']) {
        final id = await profile.saveCareerFact(
          CareerFactDraft(
            kind: 'skill',
            value: {
              'name': name,
              'level': 'low',
              'aliases': ['Rb'],
              'description': 'Used in a training project.',
              'preference_note': 'Prefer small exercises.',
              'experience_notes': ['Used for a sample command-line tool.'],
              'last_used': {'value': '2026', 'approximate': false},
            },
            visibility: name == 'Private skill' ? 'private' : 'resume',
          ),
          actor: 'user',
        );
        if (name == 'Pending skill') {
          await db.customStatement(
            "UPDATE career_fact_revisions SET verification_status = 'pending' WHERE fact_id = ?",
            [id],
          );
        }
      }
      final tools = McpUiTools(db);
      await expectLater(
        tools.call('resume_content_import_skills', {}),
        throwsFormatException,
      );
      await expectLater(
        tools.call('resume_content_import_skills', {
          'confirmed': true,
        }, workOrderId: 'writer'),
        throwsStateError,
      );
      expect((await repository.get())['content'], isA<Map>());
      expect(((await repository.read())!.value as Map)['skills'], isEmpty);
      expect(
        await tools.call('resume_content_import_skills', {'confirmed': true}),
        {'imported': 1},
      );
      final current = await repository.read();
      final content = ResumeContent(
        (current!.value as Map).cast<String, dynamic>(),
      );
      final skill = content.entries('skills').single;
      expect(skill['name'], 'Ruby');
      expect(skill['proficiency'], 'low');
      for (final note in [
        'Used for a sample command-line tool.',
        'Used in a training project.',
        'Prefer small exercises.',
        'Also known as: Rb.',
        'Last used: 2026.',
      ]) {
        expect(skill['notes'], contains(note));
      }
      final short = (content.generationContent['skills'] as List).single['id'];
      final plan = fixture.structuredPlan()
        ..['core_skills'] = [
          {
            'text': 'Ruby: training project experience.',
            'support_ids': [short],
          },
        ];
      final markdown = content.compose(plan, current.revisionId);
      content.validateGenerated(markdown, current.revisionId);
      expect(markdown, contains('Ruby: training project experience.'));
      expect(markdown, isNot(contains('Used for a sample command-line tool.')));
      skill['proficiency'] = 'Updated assessment';
      skill['enabled'] = false;
      await repository.save(
        content.data,
        expectedRevision: current.revisionId,
        actor: 'user',
      );
      final editedRevision = (await repository.read())!.revisionId;
      expect(await repository.importLegacySkills(actor: 'user'), 0);
      expect((await repository.read())!.revisionId, editedRevision);
      expect(
        ((await repository.evidence(forMatching: true)).single.value
            as Map)['skills'],
        hasLength(1),
      );
      expect(
        ((await repository.evidence()).single.value as Map)['skills'],
        isEmpty,
      );
      expect((await profile.watchCareerFacts().first), hasLength(4));
    },
  );
}
