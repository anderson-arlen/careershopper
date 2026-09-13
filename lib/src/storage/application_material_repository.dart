import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../documents/material_markdown.dart';
import 'database.dart';
import 'profile_repository.dart';
import 'document_template_repository.dart';
import 'resume_content_repository.dart';

class ApplicationMaterials {
  const ApplicationMaterials({
    required this.id,
    required this.resume,
    required this.coverLetter,
    required this.reviewed,
    required this.createdAt,
  });
  final String id;
  final String resume;
  final String coverLetter;
  final bool reviewed;
  final DateTime createdAt;
}

class ApplicationMaterialRepository {
  ApplicationMaterialRepository(this.database);
  final CareerShopperDatabase database;
  final _uuid = const Uuid();

  Stream<ApplicationMaterials?> watch(String jobId) {
    final query =
        database.select(database.materialSets).join([
            innerJoin(
              database.applications,
              database.applications.id.equalsExp(
                database.materialSets.applicationId,
              ),
            ),
          ])
          ..where(
            database.applications.jobId.equals(jobId) &
                database.materialSets.staged.equals(false),
          )
          ..orderBy([
            OrderingTerm.desc(database.materialSets.createdAt),
            OrderingTerm.desc(database.materialSets.id),
          ])
          ..limit(1);
    return query.watch().map(
      (rows) => rows.isEmpty
          ? null
          : _view(rows.first.readTable(database.materialSets)),
    );
  }

  ApplicationMaterials _view(MaterialSetRow row) => ApplicationMaterials(
    id: row.id,
    resume: row.resumeMarkdown,
    coverLetter: row.coverLetterMarkdown ?? '',
    reviewed: row.reviewedAt != null,
    createdAt: row.createdAt,
  );

  Future<MaterialSetRow> get(String id) => (database.select(
    database.materialSets,
  )..where((row) => row.id.equals(id))).getSingle();

  Future<void> validate(String resume, String coverLetter) async {
    final documents = <String, List<MaterialBlock>>{};
    final errors = <String>[];
    for (final (kind, markdown) in [
      ('Resume', resume),
      ('Cover letter', coverLetter),
    ]) {
      try {
        documents[kind] = parseMaterialMarkdown(markdown);
      } on FormatException catch (error) {
        errors.add('$kind: ${error.message}');
      }
    }
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
    final ids = documents.values
        .expand((blocks) => blocks)
        .expand((block) => block.factIds)
        .toSet();
    if (ids.isEmpty) throw StateError('Documents need confirmed career facts.');
    final revisions = await (database.select(
      database.careerFactRevisions,
    )..where((row) => row.id.isIn(ids))).get();
    final current = await (database.select(
      database.careerFacts,
    )..where((row) => row.currentRevisionId.isIn(ids))).get();
    final currentIds = current.map((fact) => fact.currentRevisionId).toSet();
    final profile = await ResumeContentRepository(
      ProfileRepository(database),
    ).evidence();
    final disclosableIds = profile.map((fact) => fact.revisionId).toSet();
    final invalid = <String, String>{};
    for (final id in ids) {
      final revision = revisions.where((r) => r.id == id).firstOrNull;
      if (revision == null) {
        invalid[id] =
            'revision not found; copy the exact revision_id from the supplied profile';
      } else if (revision.verificationStatus != 'confirmed' ||
          revision.visibility == 'private') {
        invalid[id] = 'not a confirmed, non-private career-fact revision';
      } else if (!currentIds.contains(id)) {
        invalid[id] = 'fact has changed; use its current confirmed revision';
      } else if (!disclosableIds.contains(id)) {
        invalid[id] =
            'archived or confidential evidence is not available; cite the current saved resume content';
      }
    }
    for (final document in documents.entries) {
      for (final (index, block) in document.value.indexed) {
        for (final id in block.factIds.where(invalid.containsKey)) {
          errors.add(
            '${document.key}, block ${index + 1}: $id: ${invalid[id]}',
          );
        }
      }
    }
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    await ResumeContentRepository(
      ProfileRepository(database),
    ).validateApplicationDisclosure(
      documents.values
          .expand((blocks) => blocks)
          .map((b) => b.plainText)
          .join('\n'),
    );
  }

  Future<void> validateGenerated(String resume, String coverLetter) async {
    await validate(resume, coverLetter);
    await ResumeContentRepository(
      ProfileRepository(database),
    ).validateGenerated(resume);
    for (final (kind, markdown) in [
      ('resume', resume),
      ('cover letter', coverLetter),
    ]) {
      final blocks = parseMaterialMarkdown(markdown);
      final body = blocks
          .where((block) => block.level == 0 && !block.pageBreak)
          .toList();
      final words = body
          .map((block) => block.plainText)
          .join(' ')
          .split(RegExp(r'\s+'))
          .length;
      if (blocks.first.level != 1 ||
          body.length < 2 ||
          words < 50 ||
          (kind == 'resume' && !blocks.any((block) => block.level == 2))) {
        throw StateError(
          'The $kind is incomplete: submit a complete document with a name heading and substantive body (at least two body blocks and 50 words; resume also needs a section heading). Do not submit diagnostic drafts or pad unsupported content. Use application_materials_validate to check formatting; if evidence is insufficient, report the blocker.',
        );
      }
    }
  }

  /// Publish only the latest successfully submitted pair after the ACP turn.
  /// Failed turns leave all provisional rows hidden and prior drafts intact.
  Future<void> publishGeneration(
    String workOrderId, {
    bool required = true,
  }) async {
    await database.transaction(() async {
      final order = await (database.select(
        database.aiWorkOrders,
      )..where((row) => row.id.equals(workOrderId))).getSingle();
      if (order.kind != 'application_materials' || order.status != 'running') {
        throw StateError('The materials work order is no longer active.');
      }
      final staged =
          await (database.select(database.materialSets)
                ..where(
                  (row) =>
                      row.workOrderId.equals(workOrderId) &
                      row.staged.equals(true),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.createdAt),
                  (row) => OrderingTerm.desc(row.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      final items = await (database.select(
        database.aiWorkItems,
      )..where((row) => row.workOrderId.equals(workOrderId))).get();
      if (!required && items.every((item) => item.status == 'running')) return;
      if (staged == null ||
          items.isEmpty ||
          items.any((item) => item.status != 'submitted')) {
        throw StateError(
          'Generation did not finish with a valid resume and cover-letter submission. Previous documents were kept. See the conversation for details.',
        );
      }
      await validateGenerated(
        staged.resumeMarkdown,
        staged.coverLetterMarkdown ?? '',
      );
      final application = await (database.select(
        database.applications,
      )..where((row) => row.id.equals(staged.applicationId))).getSingle();
      final job = await (database.select(
        database.jobs,
      )..where((row) => row.id.equals(application.jobId))).getSingle();
      if (application.outcome != 'active' ||
          job.availability == 'closed' ||
          job.reviewState != 'approved' ||
          job.currentSnapshotId != staged.jobSnapshotId) {
        throw StateError(
          'The job changed during generation. Previous documents were kept.',
        );
      }
      if (job.employerId != null) {
        final employer = await (database.select(
          database.employers,
        )..where((row) => row.id.equals(job.employerId!))).getSingle();
        if (employer.blockedAt != null) {
          throw StateError(
            'The employer was blocked during generation. Previous documents were kept.',
          );
        }
      }
      await (database.update(database.materialSets)
            ..where((row) => row.id.equals(staged.id)))
          .write(const MaterialSetsCompanion(staged: Value(false)));
      await (database.update(
        database.aiWorkItems,
      )..where((row) => row.workOrderId.equals(workOrderId))).write(
        AiWorkItemsCompanion(
          status: const Value('completed'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<String> save({
    required String jobId,
    required String resume,
    required String coverLetter,
    bool reviewed = false,
    String? workOrderId,
    String? expectedMaterialId,
    bool staged = false,
    bool requestSecondReview = false,
  }) async {
    return database.transaction(() async {
      await validate(resume, coverLetter);
      final job = await (database.select(
        database.jobs,
      )..where((row) => row.id.equals(jobId))).getSingle();
      if (job.reviewState != 'approved') {
        throw StateError('Approve this job first.');
      }
      final application = await (database.select(
        database.applications,
      )..where((row) => row.jobId.equals(jobId))).getSingle();
      if (expectedMaterialId != null) {
        final latest =
            await (database.select(database.materialSets)
                  ..where(
                    (row) =>
                        row.applicationId.equals(application.id) &
                        row.staged.equals(false),
                  )
                  ..orderBy([
                    (row) => OrderingTerm.desc(row.createdAt),
                    (row) => OrderingTerm.desc(row.id),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (latest?.id != expectedMaterialId) {
          throw StateError(
            'A newer draft is available. Reopen it before saving your edits.',
          );
        }
        if (latest?.jobSnapshotId != job.currentSnapshotId) {
          throw StateError(
            'The listing changed. Regenerate the documents before reviewing.',
          );
        }
      }
      final ids = [
        ...parseMaterialMarkdown(resume),
        ...parseMaterialMarkdown(coverLetter),
      ].expand((b) => b.factIds).toSet().toList()..sort();
      final now = DateTime.now().toUtc();
      final manifest = jsonEncode({'confirmed_fact_revision_ids': ids});
      final hash = sha256.convert(utf8.encode(manifest)).toString();
      var profile =
          await (database.select(database.profileSnapshots)
                ..where((row) => row.manifestHash.equals(hash))
                ..limit(1))
              .getSingleOrNull();
      if (profile == null) {
        final id = _uuid.v7();
        await database
            .into(database.profileSnapshots)
            .insert(
              ProfileSnapshotsCompanion.insert(
                id: id,
                manifestJson: manifest,
                manifestHash: hash,
                createdAt: now,
              ),
            );
        profile = await (database.select(
          database.profileSnapshots,
        )..where((row) => row.id.equals(id))).getSingle();
      }
      final id = _uuid.v7();
      await database
          .into(database.materialSets)
          .insert(
            MaterialSetsCompanion.insert(
              id: id,
              staged: Value(staged),
              applicationId: application.id,
              jobSnapshotId: job.currentSnapshotId!,
              profileSnapshotId: profile.id,
              resumeMarkdown: resume,
              coverLetterMarkdown: Value(coverLetter),
              rendererVersion: 'restricted-markdown-v2',
              templateId: defaultResumeTemplateId,
              createdAt: now,
              workOrderId: Value(workOrderId),
              reviewedAt: Value(reviewed ? now : null),
            ),
          );
      if (requestSecondReview && staged) {
        await database
            .into(database.auditEvents)
            .insert(
              AuditEventsCompanion.insert(
                id: _uuid.v7(),
                eventType: 'materials.second_review_requested',
                subjectType: 'material_set',
                subjectId: id,
                actor: 'ai',
                occurredAt: now,
              ),
            );
      }
      for (final (kind, markdown) in [
        ('resume', resume),
        ('cover_letter', coverLetter),
      ]) {
        for (final block in parseMaterialMarkdown(markdown)) {
          if (block.pageBreak) continue;
          await database
              .into(database.materialClaims)
              .insert(
                MaterialClaimsCompanion.insert(
                  id: _uuid.v7(),
                  materialSetId: id,
                  documentKind: kind,
                  blockText: block.text,
                  factRevisionIdsJson: jsonEncode(block.factIds),
                ),
              );
        }
      }
      return id;
    });
  }
}
