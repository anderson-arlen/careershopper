import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/interview.dart';
import 'database.dart';
import 'application_answer_repository.dart';
import 'employer_logo_repository.dart';
import 'profile_repository.dart';
import 'resume_content_repository.dart';

class InterviewRepository {
  InterviewRepository(this.database, {EmployerLogoRepository? logos})
    : logos = logos ?? EmployerLogoRepository(database);
  final EmployerLogoRepository logos;
  final CareerShopperDatabase database;
  static const _uuid = Uuid();

  /// Scheduled completion reflects elapsed time, not an attendance or hiring outcome.
  Future<int> completeScheduledStages({String? jobId, DateTime? now}) =>
      database.transaction(() async {
        final time = (now ?? DateTime.now()).toUtc();
        final candidates = await database
            .customSelect(
              r'''SELECT w.job_id FROM interview_workspaces w
      WHERE (? IS NULL OR w.job_id = ?) AND EXISTS (
        SELECT 1 FROM json_each(w.ladder_json) s
        WHERE json_extract(s.value, '$.status') = 'scheduled'
          AND COALESCE(json_extract(s.value, '$.archived'), 0) = 0
      )''',
              variables: [Variable<String>(jobId), Variable<String>(jobId)],
              readsFrom: {database.interviewWorkspaces},
            )
            .get();
        var count = 0;
        for (final candidate in candidates) {
          final id = candidate.read<String>('job_id');
          final row = (await _row(id))!;
          final stages = interviewMaps(jsonDecode(row.ladderJson));
          final completed = <String>[];
          for (final stage in stages) {
            final end = interviewStageEnd(stage);
            if (stage['archived'] != true &&
                stage['status'] == 'scheduled' &&
                end != null &&
                !end.isAfter(time)) {
              stage['status'] = 'completed';
              completed.add(stage['id']! as String);
            }
          }
          if (completed.isEmpty) continue;
          await _update(
            id,
            InterviewWorkspacesCompanion(
              ladderJson: Value(interviewCanonical(stages)),
              revision: Value(row.revision + 1),
              updatedAt: Value(time),
            ),
          );
          await database
              .into(database.auditEvents)
              .insert(
                AuditEventsCompanion.insert(
                  id: _uuid.v7(),
                  eventType: 'interview.scheduled_stages_completed',
                  subjectType: 'job',
                  subjectId: id,
                  actor: 'system',
                  payloadJson: Value(
                    jsonEncode({
                      'stage_ids': completed,
                      'reason': 'scheduled_end_elapsed',
                    }),
                  ),
                  occurredAt: time,
                ),
              );
          count += completed.length;
        }
        return count;
      });

  Future<InterviewWorkspace?> _row(String jobId) => (database.select(
    database.interviewWorkspaces,
  )..where((r) => r.jobId.equals(jobId))).getSingleOrNull();

  Future<void> ensure(String jobId) async {
    if (await (database.select(
          database.jobs,
        )..where((r) => r.id.equals(jobId))).getSingleOrNull() ==
        null) {
      throw StateError('Unknown job.');
    }
    await database
        .into(database.interviewWorkspaces)
        .insert(
          InterviewWorkspacesCompanion.insert(
            jobId: jobId,
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<InterviewWorkspace> _edit(String jobId, int revision) async {
    await ensure(jobId);
    final row = (await _row(jobId))!;
    if (row.revision != revision) {
      throw StateError('Interview workspace changed. Reload before saving.');
    }
    return row;
  }

  Future<void> _update(String jobId, InterviewWorkspacesCompanion value) async {
    await (database.update(
      database.interviewWorkspaces,
    )..where((r) => r.jobId.equals(jobId))).write(value);
  }

  Future<Map<String, Object?>?> revision(String jobId, String? id) async {
    if (id == null) {
      return null;
    }
    final row = await (database.select(
      database.interviewRevisions,
    )..where((r) => r.id.equals(id) & r.jobId.equals(jobId))).getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Interview revision belongs to another job or does not exist.',
      );
    }
    return {
      'id': row.id,
      'kind': row.kind,
      'created_at': row.createdAt.toIso8601String(),
      'payload': jsonDecode(row.payloadJson),
    };
  }

  Future<String> _saveRevision(
    String jobId,
    String kind,
    Map<String, Object?> payload,
  ) async {
    final id = _uuid.v7();
    await database
        .into(database.interviewRevisions)
        .insert(
          InterviewRevisionsCompanion.insert(
            id: id,
            jobId: jobId,
            kind: kind,
            payloadJson: interviewCanonical(payload),
            createdAt: DateTime.now().toUtc(),
          ),
        );
    return id;
  }

  Stream<void> watchPreparationChanges(String jobId) {
    final query = database.customSelect(
      """
    SELECT w.revision, w.preparation_state, w.preparation_error, e.logo_source_url, e.updated_at AS employer_updated_at,
           o.id AS work_order_id, o.status AS work_order_status,
           (SELECT COUNT(*) || ':' || COALESCE(SUM(p.revision),0) FROM interview_practices p WHERE p.job_id = j.id) AS practice_version,
           (SELECT COUNT(*) || ':' || COALESCE(SUM(x.revision),0) FROM interview_exchanges x JOIN interview_practices p ON p.id = x.practice_id WHERE p.job_id = j.id) AS exchange_version,
           (SELECT COUNT(*) FROM material_sets m JOIN applications a ON a.id = m.application_id WHERE a.job_id = j.id) AS materials_version,
           (SELECT auto_prepare || ':' || COALESCE(agent_id,'') FROM interview_settings WHERE id = 1) AS settings_version
    FROM jobs j
    LEFT JOIN employers e ON e.id = j.employer_id
    LEFT JOIN interview_workspaces w ON w.job_id = j.id
    LEFT JOIN ai_work_orders o ON o.job_id = j.id AND o.kind = 'interview_preparation'
    WHERE j.id = ?
    ORDER BY o.created_at DESC, o.id DESC LIMIT 1
    """,
      variables: [Variable<String>(jobId)],
      readsFrom: {
        database.jobs,
        database.employers,
        database.interviewWorkspaces,
        database.aiWorkOrders,
        database.interviewPractices,
        database.interviewExchanges,
        database.materialSets,
        database.applications,
        database.interviewSettings,
      },
    );
    String fingerprint(List<QueryRow> rows) =>
        jsonEncode(rows.map((r) => r.data).toList());
    late StreamController<String> changes;
    StreamSubscription<List<QueryRow>>? subscription;
    Timer? timer;
    Future<void>? checking;
    int? version;
    var stopped = false;
    Future<void> checkExternal() async {
      try {
        final next =
            (await database.customSelect('PRAGMA data_version').getSingle())
                .read<int>('data_version');
        if (version != next) {
          version = next;
          final rows = await query.get();
          if (!stopped) changes.add(fingerprint(rows));
        }
      } on Object catch (error, stack) {
        if (!stopped) changes.addError(error, stack);
      }
    }

    void poll() {
      if (checking != null || stopped) return;
      checking = checkExternal().whenComplete(() => checking = null);
    }

    changes = StreamController<String>(
      onListen: () {
        subscription = query.watch().listen(
          (rows) => changes.add(fingerprint(rows)),
          onError: changes.addError,
        );
        // MCP can commit through another process, outside Drift's notifications.
        // Read a tiny version marker; compare only compact metadata when it changes.
        poll();
        timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      },
      onCancel: () async {
        stopped = true;
        timer?.cancel();
        await subscription?.cancel();
        await checking;
      },
    );
    return changes.stream.distinct().map((_) {});
  }

  Future<EmployerRow?> company(String jobId) async {
    final query = database.select(database.employers).join([
      innerJoin(
        database.jobs,
        database.jobs.employerId.equalsExp(database.employers.id),
      ),
    ])..where(database.jobs.id.equals(jobId));
    return (await query.getSingleOrNull())?.readTable(database.employers);
  }

  Future<Map<String, Object?>> summary(String jobId) async {
    await completeScheduledStages(jobId: jobId);
    final rows = await database
        .customSelect(
          """
      SELECT w.ladder_json, w.preparation_state, o.status
      FROM jobs j LEFT JOIN interview_workspaces w ON w.job_id = j.id
      LEFT JOIN ai_work_orders o ON o.job_id = j.id AND o.kind = 'interview_preparation'
      WHERE j.id = ? ORDER BY o.created_at DESC, o.id DESC LIMIT 1
    """,
          variables: [Variable(jobId)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Unknown job.');
    final row = rows.single;
    final status = row.readNullable<String>('status');
    return {
      'ladder': jsonDecode(row.readNullable<String>('ladder_json') ?? '[]'),
      'preparation_state': ['queued', 'running'].contains(status)
          ? status
          : row.readNullable<String>('preparation_state') ?? 'not_started',
    };
  }

  Future<Map<String, Object?>> get(String jobId) async {
    await completeScheduledStages(jobId: jobId);
    final job = await (database.select(
      database.jobs,
    )..where((r) => r.id.equals(jobId))).getSingleOrNull();
    if (job == null) {
      throw StateError('Unknown job.');
    }
    final employer = await company(jobId);
    final row = await _row(jobId);
    final work =
        await (database.select(database.aiWorkOrders)
              ..where(
                (r) =>
                    r.jobId.equals(jobId) &
                    r.kind.equals('interview_preparation'),
              )
              ..orderBy([
                (r) => OrderingTerm.desc(r.createdAt),
                (r) => OrderingTerm.desc(r.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    // Saving a packet does not mean the ACP turn has stopped running.
    final preparationState = switch (work?.status) {
      'queued' || 'running' => work!.status,
      _ => row?.preparationState ?? 'not_started',
    };
    final table = database.interviewRevisions;
    final revisions =
        await (database.selectOnly(table)
              ..addColumns([table.id, table.kind, table.createdAt])
              ..where(table.jobId.equals(jobId))
              ..orderBy([
                OrderingTerm.desc(table.createdAt),
                OrderingTerm.desc(table.id),
              ]))
            .get();
    return {
      'job_id': jobId,
      'revision': row?.revision ?? 0,
      'ladder': jsonDecode(row?.ladderJson ?? '[]'),
      'next_scheduled_stage': nextScheduledInterviewStage(
        interviewMaps(jsonDecode(row?.ladderJson ?? '[]')),
      ),
      'current_stage': currentInterviewStage(
        interviewMaps(jsonDecode(row?.ladderJson ?? '[]')),
      ),
      'preparation_state': preparationState,
      'company': {
        'name': employer?.displayName,
        'has_logo': employer?.logoPng != null,
        'logo_source_url': employer?.logoSourceUrl,
      },
      'research_activity': work == null
          ? null
          : {'work_order_id': work.id, 'status': work.status},
      'preparation_error': row?.preparationError,
      'intel': await revision(jobId, row?.intelId),
      'application_context': await _applicationContext(jobId, row?.contextId),
      'questions': await questions(jobId),
      'revisions': [
        for (final r in revisions)
          {
            'id': r.read(table.id),
            'kind': r.read(table.kind),
            'created_at': r.read(table.createdAt)!.toIso8601String(),
          },
      ],
      'settings': await settings(),
    };
  }

  Future<Map<String, Object?>?> _applicationContext(
    String jobId,
    String? selectedId,
  ) async {
    final submittedAnswers =
        (await ApplicationAnswerRepository(database).list(jobId))
            .where((r) => r.status == 'submitted')
            .map(ApplicationAnswerRepository.toJson)
            .toList();
    if (selectedId != null) {
      final selected = await revision(jobId, selectedId);
      if (selected != null) {
        return {
          ...selected,
          'payload': {
            ...interviewMap(selected['payload']),
            'application_answers': submittedAnswers,
          },
        };
      }
    }
    final latest = (await materials(jobId)).firstOrNull;
    if (latest == null && submittedAnswers.isEmpty) return null;
    return {
      'id': null,
      'kind': 'context',
      'created_at': latest?['created_at'],
      'payload': {
        ...?latest,
        'material_set_id': latest?['id'],
        'attribution': latest == null
            ? 'submitted_application_answers'
            : 'latest_application_documents',
        'application_answers': submittedAnswers,
      },
    };
  }

  Future<Map<String, Object?>> settings() async {
    final row = await (database.select(
      database.interviewSettings,
    )..where((r) => r.id.equals(1))).getSingleOrNull();
    return {'auto_prepare': row?.autoPrepare ?? true, 'agent_id': row?.agentId};
  }

  // Harness configuration is a desktop control. MCP exposes settings read-only.
  Future<void> configureAutomaticPreparation({
    required bool enabled,
    String? agentId,
  }) async {
    // No override follows the current default harness, including later setup.
    if (agentId != null) {
      final agent = await (database.select(
        database.aiHarnessProfiles,
      )..where((r) => r.id.equals(agentId))).getSingleOrNull();
      if (agent == null || agent.protocol != 'acp_stdio') {
        throw StateError('Choose an ACP agent first.');
      }
    }
    await database
        .into(database.interviewSettings)
        .insertOnConflictUpdate(
          InterviewSettingsCompanion.insert(
            id: const Value(1),
            autoPrepare: Value(enabled),
            agentId: Value(agentId),
          ),
        );
  }

  Future<Map<String, Object?>> saveStages(
    String jobId,
    int expected,
    List<Map<String, Object?>> stages,
  ) => database.transaction(() async {
    validateInterviewLadder(stages);
    final row = await _edit(jobId, expected);
    final retained = [
      for (final stage in stages)
        {
          ...stage,
          'scheduled_at':
              interviewStageStart(stage)?.toUtc().toIso8601String() ?? '',
        },
    ];
    final ids = stages.map((s) => s['id']).toSet();
    // Removal archives an identity; historical questions and sessions still resolve it.
    for (final old in interviewMaps(jsonDecode(row.ladderJson))) {
      if (!ids.contains(old['id'])) retained.add({...old, 'archived': true});
    }
    validateInterviewLadder(retained);
    await _update(
      jobId,
      InterviewWorkspacesCompanion(
        ladderJson: Value(interviewCanonical(retained)),
        ladderEdited: const Value(true),
        revision: Value(expected + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return get(jobId);
  });

  Future<List<Map<String, Object?>>> materials(String jobId) async {
    final app = await (database.select(
      database.applications,
    )..where((r) => r.jobId.equals(jobId))).getSingleOrNull();
    if (app == null) {
      return [];
    }
    final rows =
        await (database.select(database.materialSets)
              ..where(
                (r) => r.applicationId.equals(app.id) & r.staged.equals(false),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
            .get();
    return [
      for (final r in rows)
        {
          'id': r.id,
          'created_at': r.createdAt.toIso8601String(),
          'resume_markdown': r.resumeMarkdown,
          'cover_letter_markdown': r.coverLetterMarkdown ?? '',
        },
    ];
  }

  Future<Map<String, Object?>> saveContext(
    String jobId,
    int expected, {
    String? materialSetId,
    String? submittedText,
    required String attribution,
  }) => database.transaction(() async {
    if (![
      'user_confirmed_submitted',
      'selected_for_practice',
    ].contains(attribution)) {
      throw const FormatException('Invalid attribution.');
    }
    if ((materialSetId == null) == (submittedText == null)) {
      throw const FormatException(
        'Select saved materials or supply submitted text, not both.',
      );
    }
    await _edit(jobId, expected);
    final Map<String, Object?> context;
    if (materialSetId != null) {
      final material = (await materials(
        jobId,
      )).where((r) => r['id'] == materialSetId).firstOrNull;
      if (material == null) {
        throw StateError('Material set is not a saved draft for this job.');
      }
      context = {...material, 'material_set_id': materialSetId};
    } else {
      validateInterview(submittedText, interviewText(150000, 1));
      context = {'submitted_text': submittedText};
    }
    final id = await _saveRevision(jobId, 'context', {
      ...context,
      'attribution': attribution,
    });
    await _update(
      jobId,
      InterviewWorkspacesCompanion(
        contextId: Value(id),
        revision: Value(expected + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return get(jobId);
  });

  Future<Map<String, Object?>> questions(
    String jobId, {
    String? stageId,
    int offset = 0,
    int limit = 1000,
  }) async {
    if (offset < 0 || limit < 1 || limit > 1000) {
      throw const FormatException('Invalid page.');
    }
    final row = await _row(jobId);
    final bank = await revision(jobId, row?.questionsId);
    final payload = bank == null
        ? <String, Object?>{}
        : interviewMap(bank['payload']);
    final merged = <String, Map<String, Object?>>{
      for (final q in interviewMaps(payload['questions'] ?? []))
        q['id']! as String: q,
      for (final e in interviewMap(
        jsonDecode(row?.overridesJson ?? '{}'),
      ).entries)
        e.key: interviewMap(e.value),
    };
    final all = merged.values
        .where((q) => stageId == null || q['stage_id'] == stageId)
        .toList();
    return {
      'revision_id': bank?['id'],
      'coverage_gaps': payload['coverage_gaps'] ?? [],
      'stage_targets': [
        for (final stage
            in interviewMaps(jsonDecode(row?.ladderJson ?? '[]')).where(
              (s) =>
                  s['archived'] != true &&
                  (stageId == null || s['id'] == stageId),
            ))
          {
            'stage_id': stage['id'],
            'target': interviewQuestionTarget(stage),
            'available': all
                .where(
                  (q) => q['stage_id'] == stage['id'] && q['archived'] != true,
                )
                .map(
                  (q) => interviewQuestionFingerprint(q['prompt']! as String),
                )
                .toSet()
                .length,
          },
      ],
      'questions': all.skip(offset).take(limit).toList(),
      'total': all.length,
      'next_offset': offset + limit < all.length ? offset + limit : null,
    };
  }

  Future<Map<String, Object?>> saveQuestion(
    String jobId,
    int expected,
    Map<String, Object?> question,
  ) => database.transaction(() async {
    validateInterview(question, interviewQuestionSchema);
    final row = await _edit(jobId, expected);
    _checkQuestionStages([question], interviewMaps(jsonDecode(row.ladderJson)));
    final intel = await revision(jobId, row.intelId);
    final sourceIds = intel == null
        ? <Object?>{}
        : interviewMaps(
            interviewMap(intel['payload'])['sources'],
          ).map((s) => s['id']).toSet();
    if ((question['source_ids'] as List).any((id) => !sourceIds.contains(id))) {
      throw const FormatException(
        'Question references an unknown research source.',
      );
    }
    final overrides = interviewMap(jsonDecode(row.overridesJson));
    overrides[question['id']! as String] = question;
    final currentQuestions = interviewMaps(
      (await questions(jobId))['questions'],
    );
    validateInterviewQuestionDependencies([
      for (final q in currentQuestions)
        if (q['id'] != question['id']) q,
      question,
    ]);
    await _update(
      jobId,
      InterviewWorkspacesCompanion(
        overridesJson: Value(interviewCanonical(overrides)),
        revision: Value(expected + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return questions(jobId);
  });

  void _checkQuestionStages(
    List<Map<String, Object?>> questions,
    List<Map<String, Object?>> stages,
  ) {
    final ids = stages.map((s) => s['id']).toSet();
    uniqueInterviewIds(questions);
    for (final q in questions) {
      if (!ids.contains(q['stage_id'])) {
        throw const FormatException('Question references an unknown stage.');
      }
    }
  }

  Future<Map<String, Object?>> submitPreparation(
    String jobId,
    int expected,
    Map<String, Object?> intel,
    Map<String, Object?> bank, {
    String? workOrderId,
    String? employerLogoUrl,
  }) async {
    // Omitted proposals mean no new stages, including on an existing ladder.
    intel = {'stage_proposals': <Object?>[], ...intel};
    var saved = false;
    final result = await database.transaction(() async {
      if (workOrderId != null) {
        await checkScope(jobId, workOrderId, write: false);
      }
      validateInterview(intel, interviewIntelSchema);
      validateInterview(bank, interviewQuestionsSchema);
      final current = await _row(jobId);
      if (current != null &&
          current.revision == expected + 1 &&
          current.intelId != null &&
          current.questionsId != null) {
        final savedIntel = await revision(jobId, current.intelId);
        final savedBank = interviewMap(
          (await revision(jobId, current.questionsId))!['payload'],
        );
        if (interviewCanonical(savedIntel!['payload']) ==
                interviewCanonical(intel) &&
            interviewCanonical({
                  'questions': savedBank['questions'],
                  'coverage_gaps': savedBank['coverage_gaps'],
                }) ==
                interviewCanonical(bank)) {
          return {
            'job_id': jobId,
            'revision': current.revision,
            'intel_id': current.intelId,
            'questions_id': current.questionsId,
          };
        }
      }
      if (workOrderId != null) {
        await checkScope(jobId, workOrderId, write: true);
      }
      final row = await _edit(jobId, expected);
      final sources = interviewMaps(intel['sources']);
      uniqueInterviewIds(sources);
      final sourceIds = sources.map((s) => s['id']).toSet();
      for (final source in sources) {
        final url = Uri.tryParse(source['url']! as String);
        if (url == null ||
            !['https', 'http'].contains(url.scheme) ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty) {
          throw const FormatException('Sources require public HTTP(S) URLs.');
        }
        if (DateTime.tryParse(source['retrieved_at']! as String) == null) {
          throw const FormatException(
            'Source retrieval time must be an ISO timestamp.',
          );
        }
      }
      final proposals = interviewMaps(intel['stage_proposals']);
      validateInterviewLadder(proposals);
      final stages = !row.ladderEdited && jsonDecode(row.ladderJson).isEmpty
          ? proposals
          : interviewMaps(jsonDecode(row.ladderJson));
      final questions = interviewMaps(bank['questions']);
      _checkQuestionStages(questions, stages);
      validateInterviewQuestionDependencies(questions);
      final mergedQuestions = {for (final q in questions) q['id']: q};
      for (final override in interviewMap(
        jsonDecode(row.overridesJson),
      ).values) {
        final q = interviewMap(override);
        mergedQuestions[q['id']] = q;
      }
      validateInterviewQuestionDependencies(mergedQuestions.values.toList());
      final records = [
        ...interviewMaps(intel['assertions']),
        ...interviewMaps(intel['roster']),
        ...questions,
        for (final s in proposals) ...interviewMaps(s['interviewers']),
      ];
      for (final record in records) {
        final refs = record['source_ids']! as List;
        if (refs.any((id) => !sourceIds.contains(id))) {
          throw const FormatException('Unknown research source reference.');
        }
        if ((record['evidence'] == 'reported' ||
                record['kind'] == 'reported') &&
            refs.isEmpty) {
          throw const FormatException(
            'Reported information requires a source.',
          );
        }
        if (workOrderId != null && record['evidence'] == 'user_confirmed') {
          throw const FormatException(
            'Research cannot confirm user arrangements. Use reported, inferred, or unknown.',
          );
        }
      }
      final evidence = await ResumeContentRepository(
        ProfileRepository(database),
      ).get(forApplications: true);
      final intelId = await _saveRevision(jobId, 'intel', intel);
      saved = true;
      final questionsId = await _saveRevision(jobId, 'questions', {
        ...bank,
        'intel_id': intelId,
        'context_id': row.contextId,
        'application_context': await _applicationContext(jobId, row.contextId),
        'resume_evidence': evidence,
        'resume_revision_id': (await ResumeContentRepository(
          ProfileRepository(database),
        ).read())?.revisionId,
      });
      await _update(
        jobId,
        InterviewWorkspacesCompanion(
          intelId: Value(intelId),
          questionsId: Value(questionsId),
          ladderJson: Value(interviewCanonical(stages)),
          revision: Value(expected + 1),
          preparationState: const Value('ready'),
          preparationError: const Value(null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      if (workOrderId != null) {
        await (database.update(database.aiWorkItems)..where(
              (r) =>
                  r.workOrderId.equals(workOrderId) & r.subjectId.equals(jobId),
            ))
            .write(
              AiWorkItemsCompanion(
                status: const Value('completed'),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
      }
      return {
        'job_id': jobId,
        'revision': expected + 1,
        'intel_id': intelId,
        'questions_id': questionsId,
      };
    });
    // Optional network work happens after the packet commits. A failed image
    // cannot roll back useful research, and identical packet retries skip it.
    if (saved && employerLogoUrl != null) {
      try {
        final employer = await company(jobId);
        if (employer == null) {
          throw StateError('No employer is linked to this job.');
        }
        await logos.setFromUrl(employer.id, Uri.parse(employerLogoUrl));
      } on Object catch (error) {
        result['logo_warning'] =
            'Research saved, but the company logo was not cached: $error';
      }
    }
    return result;
  }

  Future<void> checkScope(
    String jobId,
    String orderId, {
    required bool write,
  }) async {
    final order = await (database.select(
      database.aiWorkOrders,
    )..where((r) => r.id.equals(orderId))).getSingleOrNull();
    final item =
        await (database.select(database.aiWorkItems)..where(
              (r) => r.workOrderId.equals(orderId) & r.subjectId.equals(jobId),
            ))
            .getSingleOrNull();
    if (order == null ||
        order.kind != 'interview_preparation' ||
        order.jobId != jobId ||
        order.status != 'running' ||
        order.leasedUntil == null ||
        !order.leasedUntil!.isAfter(DateTime.now().toUtc()) ||
        item == null ||
        (write && item.status != 'running')) {
      throw StateError(
        'Interview operation is outside the active work-order scope.',
      );
    }
  }

  Future<Map<String, int>> _questionExposure(String jobId) async {
    final query = database.select(database.interviewExchanges).join([
      innerJoin(
        database.interviewPractices,
        database.interviewPractices.id.equalsExp(
          database.interviewExchanges.practiceId,
        ),
      ),
    ])..where(database.interviewPractices.jobId.equals(jobId));
    final counts = <String, int>{};
    final seen = <String>{};
    for (final result in await query.get()) {
      final practice = result.readTable(database.interviewPractices);
      final exchange = result.readTable(database.interviewExchanges);
      final payload = interviewMap(jsonDecode(exchange.payloadJson));
      if (!interviewMaps(payload['turns']).any(
        (t) =>
            t['speaker'] == 'interviewer' &&
            (t['text']! as String).trim().isNotEmpty,
      )) {
        continue;
      }
      final bank = interviewMap(
        interviewMap(jsonDecode(practice.snapshotJson))['questions'],
      );
      final question = interviewMaps(
        bank['questions'],
      ).where((q) => q['id'] == payload['question_id']).firstOrNull;
      if (question == null) continue;
      final fingerprint = interviewQuestionFingerprint(
        question['prompt']! as String,
      );
      // Corrections and repeated checkpoints count as one exposure per session.
      if (seen.add('${practice.id}:$fingerprint')) {
        counts.update(fingerprint, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  Future<Map<String, Object?>> startPractice(
    String jobId,
    String? stageId,
    String requestId,
    Map<String, Object?> settings,
  ) => database.transaction(() async {
    validateInterview(settings, interviewPracticeSettingsSchema);
    validateInterview(requestId, interviewId);
    final request = interviewCanonical({
      'job_id': jobId,
      'stage_id': stageId,
      'settings': settings,
    });
    final existing = await (database.select(
      database.interviewPractices,
    )..where((r) => r.requestId.equals(requestId))).getSingleOrNull();
    if (existing != null) {
      if (existing.requestJson != request) {
        throw StateError(
          'This client request ID was already used for different settings.',
        );
      }
      return practice(existing.id);
    }
    await ensure(jobId);
    await completeScheduledStages(jobId: jobId);
    final row = (await _row(jobId))!;
    final ladder = interviewMaps(jsonDecode(row.ladderJson));
    final stage = stageId == null
        ? currentInterviewStage(ladder)
        : ladder
              .where((s) => s['id'] == stageId && s['archived'] != true)
              .firstOrNull;
    if (stage == null) {
      throw StateError(
        stageId == null
            ? 'No current interview stage is recorded. Add an unfinished stage or explicitly select a stage to revisit.'
            : 'Select an active interview stage.',
      );
    }
    final resolvedStageId = stage['id']! as String;
    final table = database.interviewPractices;
    final count = table.id.count();
    final completed =
        (await (database.selectOnly(table)
                  ..addColumns([count])
                  ..where(
                    table.jobId.equals(jobId) &
                        table.stageId.equals(resolvedStageId) &
                        table.status.equals('completed'),
                  ))
                .getSingle())
            .read(count) ??
        0;
    final automatic = !settings.containsKey('difficulty');
    final difficulty = automatic
        ? min(5, 2 + completed ~/ 2)
        : settings['difficulty']! as int;
    final resolvedSettings = {...settings, 'difficulty': difficulty};
    final resume = ResumeContentRepository(ProfileRepository(database));
    final fact = await resume.read();
    final context = await _applicationContext(jobId, row.contextId);
    final activeQuestions = await questions(jobId, stageId: resolvedStageId);
    final exposure = await _questionExposure(jobId);
    activeQuestions['questions'] = randomizedInterviewQuestions(
      interviewMaps(activeQuestions['questions']),
      exposure,
      random: Random.secure(),
      difficulty: difficulty,
    );
    activeQuestions['selection_history'] = [
      for (final q in interviewMaps(activeQuestions['questions']))
        {
          'question_id': q['id'],
          'prior_practice_count':
              exposure[interviewQuestionFingerprint(q['prompt']! as String)] ??
              0,
        },
    ];
    activeQuestions['selection_policy'] =
        'Prefer questions at the saved difficulty, then easier ones, with random choices among equally suitable least-practiced questions; prerequisites first. Use a time-appropriate subset, preserve dependency order and vary topics. Follow-ups remain attached. Explicit requests to revisit override novelty.';
    activeQuestions['total'] = (activeQuestions['questions'] as List).length;
    final snapshot = {
      'stage': stage,
      'settings': resolvedSettings,
      'difficulty_progression': {
        'mode': automatic ? 'automatic' : 'fixed',
        'completed_practices': completed,
        'level': difficulty,
        'practices_per_level': 2,
        'available_at_or_below_level': interviewMaps(
          activeQuestions['questions'],
        ).where((q) => (q['difficulty']! as int) <= difficulty).length,
        'guidance':
            'Open with a brief, easy, stage-relevant warm-up, then build toward the saved difficulty as the applicant settles in. Increase depth, ambiguity and follow-up pressure within that level. If the applicant struggles, clarify or ease the next probe; do not force escalation. Keep coaching off unless enabled. When the bank lacks suitable easy questions, use concrete stage-relevant fundamentals and record spontaneous questions without a bank question ID. Never ask an unsuitable hard question just to follow the saved order.',
      },
      'rubric_version': 'interview-v1',
      'rubric_anchors': {
        '0': 'No usable answer',
        '1': 'Substantial gaps',
        '2': 'Partial evidence',
        '3': 'Meets expectations',
        '4': 'Strong evidence with depth',
      },
      'intel': await revision(jobId, row.intelId),
      'application_context': context,
      'context_warning': context == null
          ? 'No saved application documents are available for this job.'
          : null,
      'resume_revision_id': fact?.revisionId,
      'resume_evidence': await resume.get(forApplications: true),
      'questions': activeQuestions,
    };
    final id = _uuid.v7(), now = DateTime.now().toUtc();
    await database
        .into(database.interviewPractices)
        .insert(
          InterviewPracticesCompanion.insert(
            id: id,
            jobId: jobId,
            stageId: resolvedStageId,
            requestId: requestId,
            requestJson: request,
            snapshotJson: interviewCanonical(snapshot),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return practice(id);
  });

  Future<InterviewPractice> _practice(String id) async {
    final row = await (database.select(
      database.interviewPractices,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('Unknown practice.');
    }
    return row;
  }

  Future<List<InterviewExchange>> _exchanges(String id) =>
      (database.select(database.interviewExchanges)
            ..where((r) => r.practiceId.equals(id))
            ..orderBy([(r) => OrderingTerm.asc(r.sequence)]))
          .get();

  Future<Map<String, Object?>> practice(String id) async {
    final row = await _practice(id);
    final snapshot = interviewMap(jsonDecode(row.snapshotJson));
    final exchanges = await _exchanges(id);
    final score = scoreInterview([
      for (final e in exchanges) interviewMap(jsonDecode(e.payloadJson)),
    ], interviewMap(interviewMap(snapshot['stage'])['weights']));
    return {
      'practice_id': id,
      'job_id': row.jobId,
      'stage_id': row.stageId,
      'revision': row.revision,
      'status': row.status,
      'created_at': row.createdAt.toIso8601String(),
      'updated_at': row.updatedAt.toIso8601String(),
      'debrief': row.debrief,
      'snapshot': snapshot,
      'assessment': score,
      'exchanges': [
        for (final e in exchanges)
          {
            'exchange_id': e.exchangeId,
            'revision': e.revision,
            'sequence': e.sequence,
            'payload': jsonDecode(e.payloadJson),
            'previous_revisions': jsonDecode(e.historyJson),
          },
      ],
      'start_prompt':
          'Use the CareerShopper skill to conduct interview practice $id. Read interview_practice_context_get, then follow difficulty_progression and the saved difficulty, randomized question order and selection policy. Open with an easy warm-up and build toward the session level. Ask a time-appropriate subset, one question or follow-up per turn, then wait for the answer. Keep that question pending through tool results, incidental sounds or presence checks. Cover prerequisites before dependent questions; read interview-question-patterns.md for varied pressure scenarios. Silently save each completed question and its follow-ups with interview_practice_exchange_save before asking the next question. Never split a spoken question around a tool call or announce exchange completion. Defer spoken evaluation until the debrief unless coaching is enabled. Record only transcript text actually available to you; label summaries honestly. Finish with interview_practice_state_set. I will use voice in this harness if available.',
    };
  }

  Future<Map<String, Object?>> saveExchange(
    String id,
    String exchangeId,
    int expected,
    Map<String, Object?> payload,
  ) => database.transaction(() async {
    validateInterview(exchangeId, interviewId);
    validateInterview(payload, interviewExchangeSchema);
    final row = await _practice(id);
    final old =
        await (database.select(database.interviewExchanges)..where(
              (r) => r.practiceId.equals(id) & r.exchangeId.equals(exchangeId),
            ))
            .getSingleOrNull();
    final canonical = interviewCanonical(payload);
    if (old?.payloadJson == canonical) {
      return {'exchange_id': exchangeId, 'revision': old!.revision};
    }
    if (row.status != 'active') {
      throw StateError(
        'Resume this practice before recording. Completed practices are immutable.',
      );
    }
    if ((old?.revision ?? -1) != expected) {
      throw StateError(
        'Exchange changed. Reload before saving. New exchanges use expected_revision -1.',
      );
    }
    final turns = interviewMaps(payload['turns']);
    uniqueInterviewIds(turns);
    final turnIds = turns.map((t) => t['id']).toSet();
    final answerIds = turns
        .where((t) => t['speaker'] == 'applicant')
        .map((t) => t['id'])
        .toSet();
    final assessments = interviewMaps(payload['assessments']);
    uniqueInterviewIds(assessments, 'dimension');
    if (assessments.isNotEmpty &&
        (payload['complete'] != true ||
            !turns.any((t) => t['speaker'] == 'applicant'))) {
      throw const FormatException(
        'Only completed lines with applicant evidence can be graded.',
      );
    }
    for (final a in assessments) {
      final refs = a['turn_ids']! as List;
      if (refs.isEmpty ||
          refs.any((t) => !turnIds.contains(t)) ||
          !refs.any(answerIds.contains)) {
        throw const FormatException('Assessments must cite recorded turns.');
      }
    }
    if (turns.any((t) => t['speaker'] == 'coach') &&
        payload['coached'] != true) {
      throw const FormatException('Mark coaching assistance.');
    }
    final snapshot = interviewMap(jsonDecode(row.snapshotJson));
    final qid = payload['question_id']! as String;
    if (qid.isNotEmpty &&
        !interviewMaps(
          interviewMap(snapshot['questions'])['questions'],
        ).any((q) => q['id'] == qid)) {
      throw const FormatException(
        'Question is not part of this practice snapshot. Leave question_id empty for spontaneous questions.',
      );
    }
    final history = old == null
        ? <Object?>[]
        : [
            ...jsonDecode(old.historyJson) as List,
            {'revision': old.revision, 'payload': jsonDecode(old.payloadJson)},
          ];
    final sequence = old?.sequence ?? (await _exchanges(id)).length;
    await database
        .into(database.interviewExchanges)
        .insertOnConflictUpdate(
          InterviewExchangesCompanion.insert(
            practiceId: id,
            exchangeId: exchangeId,
            sequence: sequence,
            revision: Value(expected + 1),
            payloadJson: canonical,
            historyJson: Value(jsonEncode(history)),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    await (database.update(
      database.interviewPractices,
    )..where((r) => r.id.equals(id))).write(
      InterviewPracticesCompanion(
        revision: Value(row.revision + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return {'exchange_id': exchangeId, 'revision': expected + 1};
  });

  Future<Map<String, Object?>> setPracticeState(
    String id,
    int expected,
    String status,
    String debrief,
  ) => database.transaction(() async {
    if (!['active', 'paused', 'abandoned', 'completed'].contains(status)) {
      throw const FormatException('Unknown practice state.');
    }
    validateInterview(debrief, interviewText(16000));
    final row = await _practice(id);
    if (row.status == status && row.debrief == debrief) {
      return practice(id);
    }
    if (row.status == 'completed' || row.status == 'abandoned') {
      throw StateError(
        'Finished practices are immutable. Start a new practice.',
      );
    }
    if (row.revision != expected) {
      throw StateError('Practice changed. Reload before changing state.');
    }
    if (status == 'completed') {
      final exchanges = await _exchanges(id);
      if (exchanges.isEmpty ||
          exchanges.any(
            (e) => interviewMap(jsonDecode(e.payloadJson))['complete'] != true,
          ) ||
          debrief.trim().isEmpty) {
        throw StateError(
          'Complete all recorded lines and supply a debrief before finishing.',
        );
      }
    }
    await (database.update(
      database.interviewPractices,
    )..where((r) => r.id.equals(id))).write(
      InterviewPracticesCompanion(
        status: Value(status),
        debrief: Value(debrief),
        revision: Value(expected + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return practice(id);
  });

  Future<Map<String, Object?>> practices({
    String? jobId,
    String? stageId,
    String? status,
    int offset = 0,
    int limit = 100,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw const FormatException('Invalid page.');
    }
    final rows = await database
        .customSelect(
          """
      SELECT id, job_id, stage_id, revision, status, created_at, updated_at, debrief,
        json_extract(snapshot_json, '\$.stage') AS stage_json,
        json_extract(snapshot_json, '\$.settings') AS settings_json,
        json_extract(snapshot_json, '\$.rubric_version') AS rubric_version
      FROM interview_practices
      WHERE ${[if (jobId != null) 'job_id = ?', if (stageId != null) 'stage_id = ?', if (status != null) 'status = ?', '1 = 1'].join(' AND ')}
      ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?
    """,
          variables: [
            if (jobId != null) Variable<String>(jobId),
            if (stageId != null) Variable<String>(stageId),
            if (status != null) Variable<String>(status),
            Variable(limit + 1),
            Variable(offset),
          ],
        )
        .get();
    final ids = rows.take(limit).map((r) => r.read<String>('id')).toList();
    final exchanges = ids.isEmpty
        ? <TypedResult>[]
        : await (database.selectOnly(database.interviewExchanges)
                ..addColumns([
                  database.interviewExchanges.practiceId,
                  database.interviewExchanges.payloadJson,
                ])
                ..where(database.interviewExchanges.practiceId.isIn(ids)))
              .get();
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final e in exchanges) {
      (grouped[e.read<String>(database.interviewExchanges.practiceId)!] ??= [])
          .add(
            interviewMap(
              jsonDecode(e.read(database.interviewExchanges.payloadJson)!),
            ),
          );
    }
    final items = <Map<String, Object?>>[];
    for (final row in rows.take(limit)) {
      final stage = interviewMap(jsonDecode(row.read<String>('stage_json')));
      final id = row.read<String>('id');
      items.add({
        'practice_id': id,
        'job_id': row.read<String>('job_id'),
        'stage_id': row.read<String>('stage_id'),
        'revision': row.read<int>('revision'),
        'status': row.read<String>('status'),
        'created_at': row.read<DateTime>('created_at').toIso8601String(),
        'updated_at': row.read<DateTime>('updated_at').toIso8601String(),
        'debrief': row.read<String>('debrief'),
        'stage': stage,
        'settings': jsonDecode(row.read<String>('settings_json')),
        'rubric_version': row.data['rubric_version'],
        'assessment': scoreInterview(
          grouped[id] ?? [],
          interviewMap(stage['weights']),
        ),
      });
    }
    return {
      'practices': items,
      'next_offset': rows.length > limit ? offset + limit : null,
    };
  }

  Future<Map<String, Object?>> statistics({
    String? jobId,
    String? stageId,
  }) async {
    final groups = <String, Map<String, Object?>>{};
    var offset = 0;
    do {
      final page = await practices(
        jobId: jobId,
        stageId: stageId,
        status: 'completed',
        offset: offset,
        limit: 200,
      );
      for (final p in interviewMaps(page['practices'])) {
        final settings = interviewMap(p['settings']),
            stage = interviewMap(p['stage']),
            score = interviewMap(p['assessment']);
        final keyData = {
          'job_id': p['job_id'],
          'stage_id': p['stage_id'],
          'category': stage['category'],
          'weights': stage['weights'],
          'difficulty': settings['difficulty'],
          'personality': settings['personality'],
          'personality_instructions': settings['personality_instructions'],
          'coaching': settings['coaching'] == true || score['coached'] == true,
          'rubric_version': p['rubric_version'],
          'harness': settings['harness'],
          'model': settings['model'],
        };
        final key = interviewCanonical(keyData);
        final group = groups.putIfAbsent(
          key,
          () => {'group': keyData, 'points': <Object?>[]},
        );
        (group['points'] as List).add({
          'practice_id': p['practice_id'],
          'date': p['created_at'],
          ...score,
        });
      }
      if (page['next_offset'] == null) break;
      offset = page['next_offset']! as int;
    } while (true);
    for (final group in groups.values) {
      final points = group['points'] as List;
      points.sort(
        (a, b) => (interviewMap(a)['date'] as String).compareTo(
          interviewMap(b)['date'] as String,
        ),
      );
      group['sample_count'] = points.length;
    }
    return {'groups': groups.values.toList(), 'completed_only': true};
  }
}
