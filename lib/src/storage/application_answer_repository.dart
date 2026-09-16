import 'package:drift/drift.dart';

import 'database.dart';

/// User-kept application text is a record, not confirmed career evidence.
class ApplicationAnswerRepository {
  ApplicationAnswerRepository(this.database);
  final CareerShopperDatabase database;

  SimpleSelectStatement<ApplicationAnswers, ApplicationAnswerRow> _query(
    String jobId,
  ) => (database.select(database.applicationAnswers)
    ..where((r) => r.jobId.equals(jobId))
    ..orderBy([
      (r) => OrderingTerm.desc(r.createdAt),
      (r) => OrderingTerm.asc(r.id),
    ]));

  Stream<List<ApplicationAnswerRow>> watch(String jobId) =>
      _query(jobId).watch();

  Future<List<ApplicationAnswerRow>> list(String jobId) async {
    await _requireJob(jobId);
    return _query(jobId).get();
  }

  Future<void> _requireJob(String jobId) async {
    if (await (database.select(
          database.jobs,
        )..where((r) => r.id.equals(jobId))).getSingleOrNull() ==
        null) {
      throw StateError('Unknown job_id.');
    }
  }

  Future<ApplicationAnswerRow> save({
    required String jobId,
    required String answerId,
    required int expectedRevision,
    required String question,
    required String answer,
    required String status,
  }) => database.transaction(() async {
    if (answerId.trim().isEmpty ||
        answerId.length > 200 ||
        question.trim().isEmpty ||
        question.length > 12000 ||
        answer.trim().isEmpty ||
        answer.length > 30000 ||
        expectedRevision < 0 ||
        !{'draft', 'submitted'}.contains(status)) {
      throw const FormatException(
        'Provide a question, answer, valid ID, revision, and draft/submitted status.',
      );
    }
    await _requireJob(jobId);
    final existing = await (database.select(
      database.applicationAnswers,
    )..where((r) => r.id.equals(answerId))).getSingleOrNull();
    if (existing != null && existing.jobId != jobId) {
      throw StateError('Answer belongs to another job.');
    }
    if ((existing?.revision ?? 0) != expectedRevision) {
      throw StateError(
        'Answer changed. Read the saved answer before editing it.',
      );
    }
    final now = DateTime.now().toUtc();
    await database
        .into(database.applicationAnswers)
        .insertOnConflictUpdate(
          ApplicationAnswersCompanion.insert(
            id: answerId,
            jobId: jobId,
            question: question,
            answer: answer,
            status: status,
            revision: expectedRevision + 1,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return (database.select(
      database.applicationAnswers,
    )..where((r) => r.id.equals(answerId))).getSingle();
  });

  static Map<String, Object?> toJson(ApplicationAnswerRow row) => {
    'answer_id': row.id,
    'job_id': row.jobId,
    'question': row.question,
    'answer': row.answer,
    'status': row.status,
    'revision': row.revision,
    'created_at': row.createdAt.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}
