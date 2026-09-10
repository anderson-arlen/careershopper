import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase database;
  late ProfileRepository repository;

  setUp(() {
    database = CareerShopperDatabase(NativeDatabase.memory());
    repository = ProfileRepository(database);
  });

  tearDown(() => database.close());

  test('shows current facts with their provenance', () async {
    await _insertPendingFact(database);

    final facts = await repository.watchCareerFacts().first;
    expect(facts, hasLength(1));
    expect(facts.single.kind, 'employment');
    expect(facts.single.value, {'employer': 'Example', 'role': 'Engineer'});
    expect(facts.single.sourceLabel, 'resume.md');
    expect(facts.single.verificationStatus, 'pending');
  });

  test('confirming a fact preserves the extracted revision', () async {
    await _insertPendingFact(database);

    await repository.setFactVerificationStatus(
      'fact-1',
      'confirmed',
      actor: 'desktop_user',
    );

    final revisions = await (database.select(
      database.careerFactRevisions,
    )..where((row) => row.factId.equals('fact-1'))).get();
    expect(revisions, hasLength(2));
    expect(revisions.map((item) => item.verificationStatus), [
      'pending',
      'confirmed',
    ]);
    expect(
      (await repository.watchCareerFacts().first).single.verificationStatus,
      'confirmed',
    );
    expect(await database.select(database.auditEvents).get(), hasLength(1));
  });

  test('editing a fact creates a confirmed user revision', () async {
    await _insertPendingFact(database);

    await repository.saveCareerFact(
      const CareerFactDraft(
        id: 'fact-1',
        kind: 'employment',
        value: {'employer': 'Example', 'role': 'Senior Engineer'},
        visibility: 'resume',
        evidenceText: 'Corrected directly by the user.',
      ),
      actor: 'desktop_user',
    );

    final revisions = await (database.select(
      database.careerFactRevisions,
    )..where((row) => row.factId.equals('fact-1'))).get();
    expect(revisions, hasLength(2));
    final current = (await repository.watchCareerFacts().first).single;
    expect(current.value, {'employer': 'Example', 'role': 'Senior Engineer'});
    expect(current.verificationStatus, 'confirmed');
    expect(current.sourceType, 'user_statement');
    expect(current.sourceLabel, 'CareerShopper profile editor');
  });

  test('retiring a fact preserves it as an immutable revision', () async {
    await _insertPendingFact(database);

    await repository.retireCareerFact('fact-1', actor: 'desktop_user');

    final current = (await repository.watchCareerFacts().first).single;
    expect(current.verificationStatus, 'retired');
    expect(
      await (database.select(
        database.careerFactRevisions,
      )..where((row) => row.factId.equals('fact-1'))).get(),
      hasLength(2),
    );
  });

  test('shows AI-managed career preferences', () async {
    await database
        .into(database.careerPreferences)
        .insert(
          CareerPreferencesCompanion.insert(
            id: 'preference-1',
            key: 'preferred_workplace',
            valueJson: '["remote","hybrid"]',
            updatedAt: DateTime.utc(2026, 9, 4),
          ),
        );

    final preferences = await repository.watchCareerPreferences().first;
    expect(preferences.single.key, 'preferred_workplace');
    expect(preferences.single.value, ['remote', 'hybrid']);
  });

  test('creates, edits, and removes career preferences', () async {
    final id = await repository.saveCareerPreference(
      const CareerPreferenceDraft(
        key: 'preferred_workplace',
        value: ['remote'],
      ),
    );
    await repository.saveCareerPreference(
      CareerPreferenceDraft(
        id: id,
        key: 'workplace_preferences',
        value: const ['remote', 'hybrid'],
      ),
    );

    final preference = (await repository.watchCareerPreferences().first).single;
    expect(preference.key, 'workplace_preferences');
    expect(preference.value, ['remote', 'hybrid']);

    await repository.deleteCareerPreference(id);
    expect(await repository.watchCareerPreferences().first, isEmpty);
  });
}

Future<void> _insertPendingFact(CareerShopperDatabase database) async {
  final createdAt = DateTime.utc(2026, 9, 4);
  await database
      .into(database.careerSources)
      .insert(
        CareerSourcesCompanion.insert(
          id: 'source-1',
          sourceType: 'document_extraction',
          label: 'resume.md',
          createdAt: createdAt,
        ),
      );
  await database
      .into(database.careerFacts)
      .insert(
        CareerFactsCompanion.insert(
          id: 'fact-1',
          kind: 'employment',
          currentRevisionId: const Value('revision-1'),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
  await database
      .into(database.careerFactRevisions)
      .insert(
        CareerFactRevisionsCompanion.insert(
          id: 'revision-1',
          factId: 'fact-1',
          revision: 1,
          valueJson: '{"employer":"Example","role":"Engineer"}',
          verificationStatus: 'pending',
          visibility: 'resume',
          sourceId: const Value('source-1'),
          createdBy: 'mcp_harness',
          createdAt: createdAt,
        ),
      );
}
