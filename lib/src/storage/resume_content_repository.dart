import '../documents/resume_content.dart';
import 'profile_repository.dart';

class ResumeContentRepository {
  ResumeContentRepository(this.profile);
  final ProfileStore profile;

  Future<CareerProfileFact?> read() async =>
      (await profile.watchCareerFacts().first)
          .where(
            (f) => f.kind == resumeContentKind && f.canDiscloseInApplications,
          )
          .firstOrNull;

  /// Disabled entries remain matching context, but never application evidence.
  Future<List<CareerProfileFact>> evidence({bool forMatching = false}) async {
    final fact = await read();
    if (fact == null) return [];
    final content = ResumeContent((fact.value as Map).cast<String, dynamic>());
    if (!forMatching) {
      for (final section in [
        'skills',
        'personal_context',
        'experience',
        'projects',
        'patents',
        'education',
      ]) {
        (content.data[section] as List).removeWhere(
          (entry) => entry['enabled'] != true,
        );
      }
    }
    return [
      CareerProfileFact(
        id: fact.id,
        revisionId: fact.revisionId,
        kind: fact.kind,
        value: content.data,
        verificationStatus: fact.verificationStatus,
        visibility: fact.visibility,
        createdAt: fact.createdAt,
        sourceId: fact.sourceId,
        sourceType: fact.sourceType,
        sourceLabel: fact.sourceLabel,
        evidenceText: fact.evidenceText,
      ),
    ];
  }

  Future<Map<String, Object?>> get({bool forApplications = false}) async {
    final fact = await read();
    final value = forApplications && fact != null
        ? (await evidence()).single.value
        : fact?.value ?? await _prefill();
    final content = ResumeContent((value as Map).cast<String, dynamic>());
    if (forApplications) {
      return {
        'configured': fact != null,
        'generation_content': content.generationContent,
      };
    }
    return {
      'generation_content': content.generationContent,
      'revision_id': fact?.revisionId,
      'content': content.data,
      'configured': fact != null,
    };
  }

  /// Explicit import only: reads never resurrect removed or disabled skills.
  Future<int> importLegacySkills({required String actor}) async {
    final current = await read();
    if (current == null) {
      throw StateError('Save Resume content before importing skills.');
    }
    final content = ResumeContent(
      (current.value as Map).cast<String, dynamic>(),
    );
    final skills = content.data['skills'] as List;
    final ids = skills.map((s) => s['id']).toSet();
    final names = skills
        .map((s) => (s['name'] as String).trim().toLowerCase())
        .toSet();
    var added = 0;
    final archived = await profile.watchCareerFacts().first;
    final contextNames = {
      for (final fact in archived.where(
        (f) => f.canDiscloseInApplications && f.value is Map,
      ))
        if ((fact.value as Map)['employer'] is String ||
            (fact.value as Map)['name'] is String)
          fact.id:
              ((fact.value as Map)['employer'] ?? (fact.value as Map)['name'])
                  as String,
    };
    for (final fact in archived) {
      if (fact.kind != 'skill' ||
          !fact.canDiscloseInApplications ||
          fact.value is! Map) {
        continue;
      }
      final value = fact.value as Map;
      final name = value['name'];
      if (name is! String ||
          name.trim().isEmpty ||
          ids.contains(fact.id) ||
          names.contains(name.trim().toLowerCase())) {
        continue;
      }
      final contexts = ((value['context_fact_ids'] as List?) ?? [])
          .map((id) => contextNames[id])
          .whereType<String>()
          .toSet();
      final notes = <String>[
        if (contexts.isNotEmpty) 'Related experience: ${contexts.join(', ')}.',
        for (final field in [
          'context',
          'description',
          'preference_note',
          'current_tool_usage',
        ])
          if (value[field] is String && (value[field] as String).isNotEmpty)
            value[field] as String,
        for (final note
            in (value['experience_notes'] as List? ?? []).whereType<String>())
          note,
        if (value['aliases'] is List && (value['aliases'] as List).isNotEmpty)
          'Also known as: ${(value['aliases'] as List).join(', ')}.',
        if (value['last_used'] is Map &&
            (value['last_used'] as Map)['value'] != null)
          'Last used: ${(value['last_used'] as Map)['approximate'] == true ? 'approximately ' : ''}${(value['last_used'] as Map)['value']}.',
      ];
      skills.add({
        'id': fact.id,
        'enabled': true,
        'name': name,
        'proficiency': value['level']?.toString() ?? '',
        'notes': notes.join('\n\n'),
      });
      ids.add(fact.id);
      names.add(name.trim().toLowerCase());
      added++;
    }
    if (added > 0) {
      await save(
        content.data,
        expectedRevision: current.revisionId,
        actor: actor,
      );
    }
    return added;
  }

  Future<Map<String, dynamic>> _prefill() async {
    final facts = (await profile.watchCareerFacts().first)
        .where(
          (f) =>
              f.canDiscloseInApplications &&
              f.visibility == 'resume' &&
              f.value is Map,
        )
        .toList();
    final data = ResumeContent.empty();
    String text(Map value, String key) =>
        value[key] is String ? value[key] as String : '';
    String date(Object? raw) {
      final value = raw is Map ? raw['value'] : raw;
      if (value is! String) return '';
      final parts = value.split('-');
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
      final shown = month != null && month >= 1 && month <= 12
          ? '${months[month - 1]} ${parts.first}'
          : value;
      return raw is Map && raw['approximate'] == true
          ? 'approximately $shown'
          : shown;
    }

    String dates(Map value) => [
      date(value['start']),
      value['end_status'] == 'current' ? 'Present' : date(value['end']),
    ].where((s) => s.isNotEmpty).join(' to ');
    final identity = <String, String>{};
    for (final fact in facts.where((f) => f.kind == 'identity')) {
      final v = fact.value as Map;
      if (v['field'] is String) {
        identity[v['field'] as String] = text(v, 'text');
      }
      for (final key in ['name', 'email', 'phone', 'location', 'github']) {
        if (v[key] is String) identity[key] = v[key] as String;
      }
    }
    data['header'] = {
      'name': identity['name'] ?? '',
      'contact': ['location', 'phone', 'email', 'github']
          .map((key) => identity[key] ?? '')
          .where((v) => v.isNotEmpty)
          .join(' · '),
    };
    String start(CareerProfileFact fact) {
      final value = (fact.value as Map)['start'];
      return (value is Map ? value['value'] : value)?.toString() ?? '';
    }

    List<CareerProfileFact> chronological(String kind) =>
        facts.where((f) => f.kind == kind).toList()
          ..sort((a, b) => start(b).compareTo(start(a)));
    final employment = chronological('employment');
    for (final fact in employment) {
      final value = fact.value as Map;
      (data['experience'] as List).add({
        'id': fact.id,
        'enabled': true,
        'employer': text(value, 'employer'),
        'title': text(value, 'title'),
        'location': text(value, 'location'),
        'dates': dates(value),
        'achievements': [
          for (final a in facts.where((a) => a.kind == 'achievement'))
            if (((a.value as Map)['context_fact_ids'] as List? ?? []).contains(
                  fact.id,
                ) &&
                employment
                        .where(
                          (e) =>
                              (((a.value as Map)['context_fact_ids']
                                          as List?) ??
                                      [])
                                  .contains(e.id),
                        )
                        .length ==
                    1 &&
                text(a.value as Map, 'statement').isNotEmpty)
              {'id': a.id, 'text': text(a.value as Map, 'statement')},
        ],
      });
    }
    for (final fact in chronological('project')) {
      final value = fact.value as Map;
      (data['projects'] as List).add({
        'id': fact.id,
        'enabled': true,
        'name': text(value, 'name'),
        'description': text(value, 'description'),
        'stack': value['stack'] is List
            ? (value['stack'] as List).whereType<String>().join(', ')
            : text(value, 'stack'),
        'dates': dates(value),
        'url': text(value, 'url'),
      });
    }
    for (final fact in facts.where((f) => f.kind == 'patent')) {
      final value = fact.value as Map;
      final classification = value['classification'] is Map
          ? value['classification'] as Map
          : {};
      final number = text(value, 'number');
      final category = [
        text(classification, 'code'),
        text(classification, 'label'),
      ].where((v) => v.isNotEmpty).join(' - ');
      final granted = date(value['grant_date']);
      (data['patents'] as List).add({
        'id': fact.id,
        'enabled': true,
        'text':
            '${value['jurisdiction'] == 'US' ? 'U.S. ' : ''}Patent${number.isEmpty ? '' : ' No. $number'}${category.isEmpty ? '' : ' [Class $category]'} ${text(value, 'title')}${granted.isEmpty ? '' : ' ($granted)'}',
      });
    }
    for (final fact in facts.where((f) => f.kind == 'education')) {
      final value = fact.value as Map;
      (data['education'] as List).add({
        'id': fact.id,
        'enabled': false,
        'heading': text(value, 'institution'),
        'details': [
          text(value, 'program'),
          text(value, 'credential'),
          dates(value),
        ].where((v) => v.isNotEmpty).join(' · '),
      });
    }
    return data;
  }

  Future<void> save(
    Map<String, dynamic> value, {
    required String? expectedRevision,
    required String actor,
  }) async {
    final content = ResumeContent(value);
    content.validate();
    final current = await read();
    if (current?.revisionId != expectedRevision) {
      throw StateError('Resume content changed. Reload before saving.');
    }
    await profile.saveCareerFact(
      CareerFactDraft(
        id: current?.id,
        kind: resumeContentKind,
        value: content.data,
        visibility: 'resume',
        expectedRevisionId: expectedRevision,
        evidenceText: 'Exact resume wording explicitly saved by the user.',
      ),
      actor: actor,
    );
  }

  Future<String> compose(Map<String, dynamic> plan) async {
    final fact = await read();
    if (fact == null) {
      throw StateError(
        'Define and save Profile > Resume content before generating a resume.',
      );
    }
    return ResumeContent(
      (fact.value as Map).cast<String, dynamic>(),
    ).compose(plan, fact.revisionId);
  }

  Future<void> validateApplicationDisclosure(String text) async {
    final fact = await read();
    if (fact == null) {
      throw StateError('Save Resume content before preparing applications.');
    }
    ResumeContent(
      (fact.value as Map).cast<String, dynamic>(),
    ).validateDisclosure(text);
  }

  Future<void> validateGenerated(String markdown) async {
    final fact = await read();
    if (fact == null) {
      throw StateError(
        'Define and save Profile > Resume content before generating a resume.',
      );
    }
    ResumeContent(
      (fact.value as Map).cast<String, dynamic>(),
    ).validateGenerated(markdown, fact.revisionId);
  }
}
