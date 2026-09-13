import 'dart:convert';
import 'package:careershopper/src/documents/resume_content.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/resume_content_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'resume_content_test.dart' as fixture;

void main() {
  test(
    'matching uses disabled work; applications use only enabled resume evidence and ignore archived facts',
    () async {
      final db = CareerShopperDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final profile = ProfileRepository(db);
      final repository = ResumeContentRepository(profile);
      await profile.saveCareerFact(
        const CareerFactDraft(
          kind: 'employment',
          value: {'employer': 'Stale employer'},
          visibility: 'resume',
        ),
        actor: 'test',
      );
      final content = ResumeContent(fixture.fixedContent()).data;
      (content['experience'] as List).add({
        'id': 'older',
        'enabled': false,
        'verification_status': 'pending',
        'employer': 'Older Factory',
        'location': 'Montana',
        'titles': [
          {
            'title': 'Production worker',
            'dates': '',
            'achievements': [
              {'id': 'older-work', 'text': 'Repaired production machinery.'},
            ],
          },
        ],
      });
      await repository.save(content, expectedRevision: null, actor: 'test');
      final matching = await repository.evidence(forMatching: true);
      final applications = await repository.evidence();
      expect(matching, hasLength(1));
      expect(jsonEncode(matching.single.value), contains('Older Factory'));
      expect(jsonEncode(matching.single.value), contains('pending'));
      expect(
        jsonEncode(matching.single.value),
        isNot(contains('Stale employer')),
      );
      expect(
        jsonEncode(applications.single.value),
        isNot(contains('Older Factory')),
      );
      expect(
        jsonEncode(applications.single.value),
        isNot(contains('Omitted Project')),
      );
      expect(
        jsonEncode(
          (await repository.get(forApplications: true))['generation_content'],
        ),
        jsonEncode(
          ResumeContent(
            (applications.single.value as Map).cast<String, dynamic>(),
          ).generationContent,
        ),
      );
      expect((await profile.watchCareerFacts().first), hasLength(2));
      expect(matching.single.revisionId, applications.single.revisionId);
      final rendered = await repository.compose(
        fixture.plan(matching.single.revisionId),
      );
      expect(rendered, isNot(contains('Older Factory')));
      await expectLater(
        repository.validateApplicationDisclosure('I worked at Older Factory.'),
        throwsFormatException,
      );
      await repository.validateApplicationDisclosure(
        'I worked at Current Company.',
      );
      final oldRevision = matching.single.revisionId;
      final updated =
          (await repository.get())['content'] as Map<String, dynamic>;
      ((updated['experience'] as List).first as Map)['employer'] =
          'Renamed Company';
      await repository.save(
        updated,
        expectedRevision: oldRevision,
        actor: 'test',
      );
      expect(
        jsonEncode((await repository.evidence(forMatching: true)).single.value),
        contains('Renamed Company'),
      );
      expect(
        jsonEncode((await repository.evidence(forMatching: true)).single.value),
        isNot(contains('Current Company')),
      );
      expect(
        await (db.select(
          db.careerFactRevisions,
        )..where((r) => r.id.equals(oldRevision))).get(),
        hasLength(1),
      );
    },
  );

  test(
    'pending imported work cannot be enabled without review and date precision is retained',
    () {
      final content = ResumeContent(fixture.fixedContent());
      final role = content.entries('experience').first;
      role['verification_status'] = 'pending';
      expect(content.validate, throwsFormatException);
      role['enabled'] = false;
      content.validate();
      role['verification_status'] = 'confirmed';
      role['enabled'] = true;
      content.validate();
      expect(role['titles'][0]['dates'], '2019 to Present');
    },
  );
}
