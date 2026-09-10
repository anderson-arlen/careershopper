import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/documents/document_prompt.dart';
import 'package:careershopper/src/storage/application_material_repository.dart';
import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/domain/job_statistics.dart';
import 'package:careershopper/src/domain/job.dart';
import 'package:careershopper/src/storage/job_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CareerShopperDatabase db;
  setUp(() => db = CareerShopperDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'availability actions and expired outcomes are discoverable and guarded',
    () async {
      final definitions =
          ((await exchange(db, 'tools/list', {}))['result'] as Map)['tools']
              as List;
      for (final name in [
        'job_availability_check',
        'job_availability_block_clear',
      ]) {
        expect(definitions.any((d) => d['name'] == name), true);
        expect(await call(db, name, {'job_id': 'missing'}), contains('error'));
      }
      final submit =
          definitions.singleWhere(
                (d) => d['name'] == 'application_materials_submit',
              )
              as Map;
      expect(
        ((submit['inputSchema'] as Map)['properties'] as Map).containsKey(
          'request_second_review',
        ),
        true,
      );
      final jobs = JobRepository(db);
      final id = await jobs.queueManualUrl(
        Uri.parse('https://example.test/expired'),
      );
      await jobs.setApplicationStatus(
        id,
        ApplicationStatus.readyToApply,
        actor: 'user',
        origin: 'test',
      );
      expect(
        await call(db, 'application_outcome_set', {
          'job_id': id,
          'application_outcome': 'expired',
          'confirmed': true,
        }),
        isNot(contains('error')),
      );
      final job = (await jobs.getJob(id))!;
      expect(job.applicationOutcome, ApplicationOutcome.expired);
      expect(job.applicationStatus, ApplicationStatus.readyToApply);
      expect(
        (await call(db, 'job_availability_block_clear', {
          'job_id': id,
          'confirmed': true,
        })),
        isNot(contains('error')),
      );
      expect(
        (await jobs.watchStatistics().first).sankeyNodes
            .singleWhere((n) => n.id == 'expired')
            .count,
        1,
      );
    },
  );

  test(
    'blocked employer MCP read and unblock use the shared repository',
    () async {
      final jobs = JobRepository(db);
      final now = DateTime.now();
      await db
          .into(db.employers)
          .insert(
            EmployersCompanion.insert(
              id: 'employer',
              displayName: 'Blocked company',
              normalizedName: 'blocked company',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await jobs.setEmployerBlocked(
        'employer',
        blocked: true,
        actor: 'user',
        origin: 'test',
        reason: 'User preference',
      );
      final result = data(await call(db, 'blocked_employers_list', {}));
      final row = (await jobs.watchBlockedEmployers().first).single;
      expect((result['employers'] as List).single, {
        'id': row.id,
        'display_name': row.displayName,
        'blocked_at': row.blockedAt!.toIso8601String(),
        'reason': row.blockReason,
      });
      expect(
        await call(db, 'employer_block_set', {
          'employer_id': row.id,
          'blocked': false,
          'confirmed': false,
        }),
        contains('error'),
      );
      expect(await jobs.watchBlockedEmployers().first, hasLength(1));
      await call(db, 'employer_block_set', {
        'employer_id': row.id,
        'blocked': false,
        'confirmed': true,
      });
      expect(await jobs.watchBlockedEmployers().first, isEmpty);
      expect(
        data(await call(db, 'blocked_employers_list', {}))['employers'],
        isEmpty,
      );
      expect(await db.select(db.employers).get(), hasLength(1));
    },
  );

  test(
    'statistics is discoverable and matches UI aggregates for every period',
    () async {
      final discovered = await exchange(db, 'tools/list', {});
      final definition = ((discovered['result'] as Map)['tools'] as List)
          .cast<Map>()
          .singleWhere((tool) => tool['name'] == 'statistics_get');
      expect((definition['annotations'] as Map)['readOnlyHint'], true);
      final jobs = JobRepository(db);
      await jobs.queueManualUrl(Uri.parse('https://example.test/new-job'));
      final defaultStats = data(await call(db, 'statistics_get', {}));
      expect(defaultStats['period'], 'all_time');
      final sankey = defaultStats['sankey'] as Map;
      expect(sankey['source_attribution'], 'first_observed_source');
      for (final node in (sankey['nodes'] as List).where(
        (n) => n['remainder'] == true,
      )) {
        final pending =
            node['id'] == 'inbox' ||
            node['id'] == 'pending_processing' ||
            (node['id'] as String).endsWith('_waiting');
        expect(node['terminal'], !pending);
      }
      expect(
        (sankey['nodes'] as List).singleWhere(
          (n) => n['id'] == 'ai_rejected',
        )['label'],
        'AI rejected',
      );
      expect(
        (sankey['nodes'] as List).first,
        containsPair('label', 'Manual entry'),
      );
      expect((sankey['links'] as List).first, {
        'source': 'source:manual',
        'target': 'found',
        'count': 1,
      });
      for (final period in StatisticsPeriod.values) {
        final response = data(
          await call(db, 'statistics_get', {'period': period.value}),
        );
        final ui = await jobs
            .watchStatistics(changedSince: period.start(DateTime.now()))
            .first;
        expect(response['counts'], ui.toJson());
        expect(response['sankey'], ui.sankeyToJson());
        expect(response['date_basis'], 'job_last_state_change');
      }
      expect(
        await call(db, 'statistics_get', {'period': 'nonsense'}),
        contains('error'),
      );
      expect(
        await call(db, 'statistics_get', {'extra': true}),
        contains('error'),
      );
    },
  );

  test('statistics MCP exposes stage-specific terminal outcomes', () async {
    final jobs = JobRepository(db);
    final id = await jobs.queueManualUrl(
      Uri.parse('https://example.test/offer'),
    );
    await jobs.setApplicationStatus(
      id,
      ApplicationStatus.offer,
      actor: 'user',
      origin: 'test',
    );
    for (final entry in {
      ApplicationOutcome.active: 'offer_waiting',
      ApplicationOutcome.rejected: 'offer_withdrawn',
      ApplicationOutcome.withdrawn: 'offer_rejected',
    }.entries) {
      await jobs.setApplicationOutcome(
        id,
        entry.key,
        actor: 'user',
        origin: 'test',
      );
      final response = data(await call(db, 'statistics_get', {}));
      final sankey = response['sankey'] as Map;
      expect(
        (sankey['links'] as List).where(
          (l) => l['source'] == 'offers' && l['count'] == 1,
        ),
        [
          {'source': 'offers', 'target': entry.value, 'count': 1},
        ],
      );
      expect(
        (sankey['nodes'] as List)
            .where((n) => n['remainder'] == true && n['count'] == 1)
            .length,
        1,
      );
      expect(
        (sankey['nodes'] as List).any(
          (n) => n['id'] == 'no_offer' || n['id'] == 'not_interviewed',
        ),
        false,
      );
    }
  });

  test(
    'MCP neither advertises nor accepts general ACP control operations',
    () async {
      const forbidden = [
        'application_materials_generate',
        'job_import_start',
        'job_refresh',
        'ai_profile_save',
        'ai_profile_delete',
        'ai_profile_default_set',
        'ai_registry_list',
        'ai_registry_agent_add',
        'ai_configuration_edit',
        'ai_conversation_start',
        'ai_conversation_send',
      ];
      final discovered = await exchange(db, 'tools/list', {});
      final names = ((discovered['result'] as Map)['tools'] as List).map(
        (tool) => (tool as Map)['name'],
      );
      expect(names, contains('application_documents_export'));
      expect(names, contains('saved_search_runs_list'));
      expect(names, contains('source_block_clear'));
      expect(
        names,
        containsAll(['job_notes_get', 'job_notes_set', 'job_context_get']),
      );
      expect(names, contains('application_answer_generate'));
      for (final name in forbidden) {
        expect(names, isNot(contains(name)), reason: name);
        final response = await call(db, name, {'confirmed': true});
        expect((response['error'] as Map)['code'], -32602, reason: name);
      }
      expect(await db.select(db.aiWorkOrders).get(), isEmpty);
      expect(await db.select(db.aiHarnessProfiles).get(), isEmpty);
    },
  );

  test(
    'template partial edits and prompt-only reset preserve layout',
    () async {
      final initial = data(await call(db, 'document_template_get', {}));
      expect((initial['cover_letter_settings'] as Map)['body_font_size'], 10.0);
      expect((initial['cover_letter_settings'] as Map)['line_spacing'], 1.12);
      expect(
        (initial['cover_letter_settings'] as Map)['paragraph_spacing'],
        8.0,
      );
      expect((initial['cover_letter_settings'] as Map)['page_numbers'], false);
      expect(
        initial['default_generation_prompt'],
        defaultDocumentGenerationPrompt,
      );
      expect(await db.select(db.documentTemplates).get(), isEmpty);
      expect(
        await call(db, 'document_template_update', {
          'settings': {'generation_prompt': 'No authorization'},
        }),
        contains('error'),
      );
      final edited = data(
        await call(db, 'document_template_update', {
          'confirmed': true,
          'name': 'Custom',
          'settings': {
            'generation_prompt': 'Lead with technical ownership.',
            'body_font_size': 10.0,
            'section_order': [
              'summary',
              'direct_match',
              'experience',
              'projects',
            ],
          },
        }),
      );
      expect((edited['settings'] as Map)['body_font_size'], 10.0);
      expect((edited['cover_letter_settings'] as Map)['body_font_size'], 10.0);
      expect((edited['settings'] as Map)['section_order'], [
        'summary',
        'direct_match',
        'experience',
        'projects',
      ]);
      final reset = data(
        await call(db, 'document_template_reset', {
          'confirmed': true,
          'target': 'prompt',
        }),
      );
      expect(reset['name'], 'Custom');
      expect(
        (reset['settings'] as Map)['generation_prompt'],
        defaultDocumentGenerationPrompt,
      );
      expect((reset['settings'] as Map)['body_font_size'], 10.0);
      expect(
        await call(db, 'document_template_update', {
          'confirmed': true,
          'settings': {'typo': true},
        }),
        contains('error'),
      );
      expect(
        await call(db, 'document_template_reset', {
          'confirmed': true,
          'target': 'prompt',
        }, scope: 'scoped-order'),
        contains('error'),
      );
    },
  );

  test(
    'MCP reads complete documents, saves edits, and rejects stale IDs and scoped bypass',
    () async {
      final imported = data(
        await call(db, 'job_import_submit', {
          'source_url': 'https://example.test/job',
          'title': 'Engineer',
          'employer_name': 'Example',
          'description': 'Build systems.',
          'employer_logo_url': 'file:///not-a-logo',
        }),
      );
      final jobId = imported['job_id'] as String;
      expect(imported['logo_warning'], isNotNull);
      final facts = data(
        await call(db, 'profile_facts_upsert_batch', {
          'provenance': 'user_statement',
          'source_label': 'User statement',
          'facts': [
            {
              'kind': 'identity',
              'value': {'name': 'Alex'},
              'verification_status': 'confirmed',
            },
          ],
        }),
      );
      final revision = ((facts['facts'] as List).single as Map)['revision_id'];
      final markdown = '# Alex <!-- facts: $revision -->';
      expect(
        await call(db, 'job_review_set', {
          'job_id': jobId,
          'review_state': 'approved',
          'confirmed': true,
        }),
        isNot(contains('error')),
      );
      final saved = await ApplicationMaterialRepository(
        db,
      ).save(jobId: jobId, resume: markdown, coverLetter: markdown);
      final read = data(
        await call(db, 'application_materials_get', {'job_id': jobId}),
      );
      expect((read['materials'] as Map)['resume_markdown'], markdown);
      expect((read['materials'] as Map)['cover_letter_markdown'], markdown);
      final formatted =
          '---\npage_numbers: false\n---\n\n$markdown\n\n<!-- pagebreak -->\n\n**A bold label** and *italic text* ${markdown.substring(markdown.indexOf('<!-- facts:'))}';
      final args = {
        'job_id': jobId,
        'expected_material_set_id': saved,
        'resume_markdown': formatted,
        'cover_letter_markdown': markdown,
        'reviewed': true,
        'confirmed': true,
      };
      expect(
        await call(
          db,
          'application_materials_update',
          args,
          scope: 'scoped-order',
        ),
        contains('error'),
      );
      final edited = data(await call(db, 'application_materials_update', args));
      expect(edited['reviewed'], true);
      expect(edited['material_set_id'], isNot(saved));
      final reread = data(
        await call(db, 'application_materials_get', {'job_id': jobId}),
      );
      expect((reread['materials'] as Map)['resume_markdown'], formatted);
      expect(
        await call(db, 'application_materials_update', args),
        contains('error'),
      );
      expect(
        await call(db, 'application_materials_create', {
          'confirmed': true,
          'job_id': jobId,
          'resume_markdown': markdown,
          'cover_letter_markdown': markdown,
        }),
        contains('error'),
      );
      expect(await db.select(db.aiWorkOrders).get(), isEmpty);
      expect(
        (data(
          await call(db, 'employer_logo_get', {'job_id': jobId}),
        ))['png_base64'],
        isNull,
      );
    },
  );

  test(
    'preference IDs support rename/delete and unknown arguments are rejected',
    () async {
      final created = data(
        await call(db, 'profile_preference_save', {
          'confirmed': true,
          'key': 'work_style',
          'value': 'remote',
        }),
      );
      final id = created['preference_id'];
      expect(
        await call(db, 'profile_preference_save', {
          'confirmed': true,
          'preference_id': id,
          'key': 'location_style',
          'value': 'hybrid',
        }),
        isNot(contains('error')),
      );
      final profile = data(await call(db, 'profile_get', {}));
      expect(
        (profile['preference_entries'] as List).single,
        containsPair('id', id),
      );
      expect(
        await call(db, 'profile_preference_delete', {
          'preference_id': id,
          'confirmed': false,
        }),
        contains('error'),
      );
      expect(
        await call(db, 'profile_preference_delete', {
          'preference_id': id,
          'confirmed': true,
        }),
        isNot(contains('error')),
      );
      expect(await db.select(db.careerPreferences).get(), isEmpty);
      expect(
        await call(db, 'ai_conversation_get', {
          'conversation_id': 'x',
          'limit': 0,
        }),
        contains('error'),
      );
      expect(
        await call(db, 'application_apply', {
          'job_id': 'x',
          'material_set_id': 'x',
          'format': 'docx',
          'confirmed': true,
          'replace_output': false,
        }),
        contains('error'),
      );
    },
  );
}

Map<String, Object?> data(Map<String, Object?> response) {
  expect(response, isNot(contains('error')), reason: '$response');
  return ((response['result'] as Map)['structuredContent'] as Map)
      .cast<String, Object?>();
}

Future<Map<String, Object?>> call(
  CareerShopperDatabase db,
  String tool,
  Map<String, Object?> arguments, {
  String? scope,
}) => exchange(db, 'tools/call', {
  'name': tool,
  'arguments': arguments,
}, scope: scope);
Future<Map<String, Object?>> exchange(
  CareerShopperDatabase db,
  String method,
  Map<String, Object?> params, {
  String? scope,
}) async {
  final controller = StreamController<List<int>>();
  final sink = IOSink(controller.sink);
  final result = controller.stream.transform(utf8.decoder).join();
  await McpServer(db, workOrderId: scope).serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params})}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return (jsonDecode(await result) as Map).cast<String, Object?>();
}
