import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../documents/resume_content.dart';

class CareerProfileFact {
  const CareerProfileFact({
    required this.id,
    required this.revisionId,
    required this.kind,
    required this.value,
    required this.verificationStatus,
    required this.visibility,
    required this.createdAt,
    this.sourceId,
    this.sourceType,
    this.sourceLabel,
    this.evidenceText,
  });

  final String id;
  final String revisionId;
  final String kind;
  final Object? value;
  final String verificationStatus;
  final String visibility;
  final String? sourceId;
  final String? sourceType;
  final String? sourceLabel;
  final String? evidenceText;
  final DateTime createdAt;

  bool get canDiscloseInApplications {
    final data = value;
    final disclosure = data is Map
        ? data['disclosure_status']?.toString().toLowerCase()
        : null;
    return verificationStatus == 'confirmed' &&
        ['resume', 'application_only'].contains(visibility) &&
        !{
          'private',
          'confidential',
          'stealth',
          'internal_only',
        }.contains(disclosure);
  }
}

class CareerPreferenceValue {
  const CareerPreferenceValue({
    required this.id,
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String id;
  final String key;
  final Object? value;
  final DateTime updatedAt;
}

class CareerFactDraft {
  const CareerFactDraft({
    this.id,
    required this.kind,
    required this.value,
    required this.visibility,
    this.evidenceText,
    this.expectedRevisionId,
  });

  final String? id;
  final String kind;
  final Object value;
  final String visibility;
  final String? evidenceText;
  final String? expectedRevisionId;
}

class CareerPreferenceDraft {
  const CareerPreferenceDraft({
    this.id,
    required this.key,
    required this.value,
  });

  final String? id;
  final String key;
  final Object value;
}

abstract interface class ProfileStore {
  Stream<List<CareerProfileFact>> watchCareerFacts();

  Stream<List<CareerPreferenceValue>> watchCareerPreferences();

  Future<String> saveCareerFact(CareerFactDraft draft, {required String actor});

  Future<void> retireCareerFact(String factId, {required String actor});

  Future<String> saveCareerPreference(CareerPreferenceDraft draft);

  Future<void> deleteCareerPreference(String id);

  Future<void> setFactVerificationStatus(
    String factId,
    String status, {
    required String actor,
  });
}

class ProfileRepository implements ProfileStore {
  ProfileRepository(this.database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final CareerShopperDatabase database;
  final Uuid _uuid;

  @override
  Stream<List<CareerProfileFact>> watchCareerFacts() {
    final query =
        database.select(database.careerFacts).join([
          innerJoin(
            database.careerFactRevisions,
            database.careerFactRevisions.id.equalsExp(
              database.careerFacts.currentRevisionId,
            ),
          ),
          leftOuterJoin(
            database.careerSources,
            database.careerSources.id.equalsExp(
              database.careerFactRevisions.sourceId,
            ),
          ),
        ])..orderBy([
          OrderingTerm.asc(database.careerFacts.kind),
          OrderingTerm.desc(database.careerFactRevisions.createdAt),
        ]);
    return query.watch().map(
      (rows) => rows
          .map((row) {
            final fact = row.readTable(database.careerFacts);
            final revision = row.readTable(database.careerFactRevisions);
            final source = row.readTableOrNull(database.careerSources);
            return CareerProfileFact(
              id: fact.id,
              revisionId: revision.id,
              kind: fact.kind,
              value: _decodeJson(revision.valueJson),
              verificationStatus: revision.verificationStatus,
              visibility: revision.visibility,
              sourceId: source?.id,
              sourceType: source?.sourceType,
              sourceLabel: source?.label,
              evidenceText: revision.evidenceText,
              createdAt: revision.createdAt,
            );
          })
          .toList(growable: false),
    );
  }

  @override
  Stream<List<CareerPreferenceValue>> watchCareerPreferences() {
    final query = database.select(database.careerPreferences)
      ..orderBy([(row) => OrderingTerm.asc(row.key)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => CareerPreferenceValue(
              id: row.id,
              key: row.key,
              value: _decodeJson(row.valueJson),
              updatedAt: row.updatedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<String> saveCareerFact(
    CareerFactDraft draft, {
    required String actor,
  }) async {
    final kind = draft.kind.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(kind)) {
      throw ArgumentError(
        'Fact type must use lower_snake_case, such as employment or project.',
      );
    }
    if (!{'resume', 'application_only', 'private'}.contains(draft.visibility)) {
      throw ArgumentError('Invalid career fact visibility.');
    }
    final factId = draft.id ?? _uuid.v7();
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      if (kind == resumeContentKind) {
        if (draft.value is! Map) {
          throw const FormatException(
            'Fixed resume content must be structured.',
          );
        }
        ResumeContent((draft.value as Map).cast<String, dynamic>()).validate();
        final saved = await (database.select(
          database.careerFacts,
        )..where((r) => r.kind.equals(resumeContentKind))).getSingleOrNull();
        if (saved != null &&
            (saved.id != draft.id ||
                saved.currentRevisionId != draft.expectedRevisionId)) {
          throw StateError('Resume content changed. Reload before saving.');
        }
      }
      final existing = await (database.select(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).getSingleOrNull();
      final latest = existing == null
          ? null
          : await (database.select(database.careerFactRevisions)
                  ..where((row) => row.factId.equals(factId))
                  ..orderBy([(row) => OrderingTerm.desc(row.revision)])
                  ..limit(1))
                .getSingleOrNull();
      final sourceId = _uuid.v7();
      await database
          .into(database.careerSources)
          .insert(
            CareerSourcesCompanion.insert(
              id: sourceId,
              sourceType: 'user_statement',
              label: 'CareerShopper profile editor',
              createdAt: now,
            ),
          );
      if (existing == null) {
        await database
            .into(database.careerFacts)
            .insert(
              CareerFactsCompanion.insert(
                id: factId,
                kind: kind,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.careerFacts,
        )..where((row) => row.id.equals(factId))).write(
          CareerFactsCompanion(kind: Value(kind), updatedAt: Value(now)),
        );
      }
      final revisionId = _uuid.v7();
      await database
          .into(database.careerFactRevisions)
          .insert(
            CareerFactRevisionsCompanion.insert(
              id: revisionId,
              factId: factId,
              revision: (latest?.revision ?? 0) + 1,
              valueJson: jsonEncode(draft.value),
              verificationStatus: 'confirmed',
              visibility: draft.visibility,
              sourceId: Value(sourceId),
              evidenceText: Value(
                draft.evidenceText?.trim().isEmpty == true
                    ? null
                    : draft.evidenceText?.trim(),
              ),
              createdBy: actor,
              createdAt: now,
            ),
          );
      await (database.update(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).write(
        CareerFactsCompanion(
          currentRevisionId: Value(revisionId),
          updatedAt: Value(now),
        ),
      );
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: existing == null
                  ? 'career_fact.created'
                  : 'career_fact.edited',
              subjectType: 'career_fact',
              subjectId: factId,
              actor: actor,
              payloadJson: Value(
                jsonEncode({
                  'kind': kind,
                  'visibility': draft.visibility,
                  'revision_id': revisionId,
                }),
              ),
              occurredAt: now,
            ),
          );
    });
    return factId;
  }

  @override
  Future<void> retireCareerFact(String factId, {required String actor}) async {
    await database.transaction(() async {
      final fact = await (database.select(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).getSingleOrNull();
      if (fact == null || fact.currentRevisionId == null) {
        throw ArgumentError('Career fact no longer exists.');
      }
      final current = await (database.select(
        database.careerFactRevisions,
      )..where((row) => row.id.equals(fact.currentRevisionId!))).getSingle();
      if (current.verificationStatus == 'retired') return;
      final latest =
          await (database.select(database.careerFactRevisions)
                ..where((row) => row.factId.equals(factId))
                ..orderBy([(row) => OrderingTerm.desc(row.revision)])
                ..limit(1))
              .getSingle();
      final now = DateTime.now().toUtc();
      final revisionId = _uuid.v7();
      await database
          .into(database.careerFactRevisions)
          .insert(
            CareerFactRevisionsCompanion.insert(
              id: revisionId,
              factId: factId,
              revision: latest.revision + 1,
              valueJson: current.valueJson,
              verificationStatus: 'retired',
              visibility: current.visibility,
              sourceId: Value(current.sourceId),
              evidenceText: Value(current.evidenceText),
              createdBy: actor,
              createdAt: now,
            ),
          );
      await (database.update(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).write(
        CareerFactsCompanion(
          currentRevisionId: Value(revisionId),
          updatedAt: Value(now),
        ),
      );
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: 'career_fact.retired',
              subjectType: 'career_fact',
              subjectId: factId,
              actor: actor,
              occurredAt: now,
            ),
          );
    });
  }

  @override
  Future<String> saveCareerPreference(CareerPreferenceDraft draft) async {
    final key = draft.key.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(key)) {
      throw ArgumentError(
        'Preference name must use lower_snake_case, such as preferred_workplace.',
      );
    }
    final id = draft.id ?? _uuid.v7();
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final existing = await (database.select(
        database.careerPreferences,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      final duplicate = await (database.select(
        database.careerPreferences,
      )..where((row) => row.key.equals(key))).getSingleOrNull();
      if (duplicate != null && duplicate.id != id) {
        throw ArgumentError('A preference named $key already exists.');
      }
      if (existing == null) {
        await database
            .into(database.careerPreferences)
            .insert(
              CareerPreferencesCompanion.insert(
                id: id,
                key: key,
                valueJson: jsonEncode(draft.value),
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.careerPreferences,
        )..where((row) => row.id.equals(id))).write(
          CareerPreferencesCompanion(
            key: Value(key),
            valueJson: Value(jsonEncode(draft.value)),
            updatedAt: Value(now),
          ),
        );
      }
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: existing == null
                  ? 'career_preference.created'
                  : 'career_preference.edited',
              subjectType: 'career_preference',
              subjectId: id,
              actor: 'desktop_user',
              payloadJson: Value(jsonEncode({'key': key})),
              occurredAt: now,
            ),
          );
    });
    return id;
  }

  @override
  Future<void> deleteCareerPreference(String id) async {
    await database.transaction(() async {
      final preference = await (database.select(
        database.careerPreferences,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (preference == null) return;
      await (database.delete(
        database.careerPreferences,
      )..where((row) => row.id.equals(id))).go();
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: 'career_preference.deleted',
              subjectType: 'career_preference',
              subjectId: id,
              actor: 'desktop_user',
              payloadJson: Value(jsonEncode({'key': preference.key})),
              occurredAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  @override
  Future<void> setFactVerificationStatus(
    String factId,
    String status, {
    required String actor,
  }) async {
    if (!{'confirmed', 'disputed'}.contains(status)) {
      throw ArgumentError('Fact status must be confirmed or disputed.');
    }
    await database.transaction(() async {
      final fact = await (database.select(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).getSingleOrNull();
      if (fact == null || fact.currentRevisionId == null) {
        throw ArgumentError('Career fact no longer exists.');
      }
      final current = await (database.select(
        database.careerFactRevisions,
      )..where((row) => row.id.equals(fact.currentRevisionId!))).getSingle();
      if (current.verificationStatus == status) return;
      final latest =
          await (database.select(database.careerFactRevisions)
                ..where((row) => row.factId.equals(factId))
                ..orderBy([(row) => OrderingTerm.desc(row.revision)])
                ..limit(1))
              .getSingle();
      final now = DateTime.now().toUtc();
      final revisionId = _uuid.v7();
      await database
          .into(database.careerFactRevisions)
          .insert(
            CareerFactRevisionsCompanion.insert(
              id: revisionId,
              factId: factId,
              revision: latest.revision + 1,
              valueJson: current.valueJson,
              verificationStatus: status,
              visibility: current.visibility,
              sourceId: Value(current.sourceId),
              evidenceText: Value(current.evidenceText),
              createdBy: actor,
              createdAt: now,
            ),
          );
      await (database.update(
        database.careerFacts,
      )..where((row) => row.id.equals(factId))).write(
        CareerFactsCompanion(
          currentRevisionId: Value(revisionId),
          updatedAt: Value(now),
        ),
      );
      await database
          .into(database.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              id: _uuid.v7(),
              eventType: 'career_fact.verification_changed',
              subjectType: 'career_fact',
              subjectId: factId,
              actor: actor,
              payloadJson: Value(jsonEncode({'status': status})),
              occurredAt: now,
            ),
          );
    });
  }
}

Object? _decodeJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}
