import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../domain/interview.dart';
import '../../platform/external_url_launcher.dart';
import '../../storage/ai_harness_repository.dart';
import '../../storage/database.dart' show EmployerRow;
import '../../storage/interview_repository.dart';

class InterviewsPanel extends StatefulWidget {
  const InterviewsPanel({
    super.key,
    required this.jobId,
    this.jobTitle,
    required this.repository,
    required this.harnesses,
    this.onPrepare,
  });
  final String jobId;
  final String? jobTitle;
  final InterviewRepository repository;
  final AiHarnessStore harnesses;
  final Future<void> Function()? onPrepare;
  @override
  State<InterviewsPanel> createState() => _InterviewsPanelState();
}

class _InterviewsPanelState extends State<InterviewsPanel> {
  Map<String, Object?>? data, history, statistics;
  String? error, stageFilter;
  EmployerRow? company;
  bool busy = false, loading = false, showMoreIntel = false;
  bool startingResearch = false, reloadPending = false;
  StreamSubscription<void>? preparationChanges;
  int questionLimit = 50;
  String section = 'Overview';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    preparationChanges = widget.repository
        .watchPreparationChanges(widget.jobId)
        .listen(
          (_) => unawaited(_load()),
          onError: (Object e) {
            if (mounted) setState(() => error = '$e');
          },
        );
  }

  @override
  void dispose() {
    unawaited(preparationChanges?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (loading) {
      reloadPending = true;
      return;
    }
    loading = true;
    try {
      final values = await Future.wait([
        widget.repository.get(widget.jobId),
        widget.repository.practices(jobId: widget.jobId),
        widget.repository.statistics(jobId: widget.jobId),
      ]);
      final employer = await widget.repository.company(widget.jobId);
      if (mounted) {
        setState(() {
          company = employer;
          data = values[0];
          history = values[1];
          statistics = values[2];
          error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      loading = false;
      if (reloadPending && mounted) {
        reloadPending = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
    if (error == null) {
      await _load();
    }
  }

  Future<void> _prepareResearch() async {
    setState(() => startingResearch = true);
    try {
      await _action(widget.onPrepare!);
    } finally {
      if (mounted) setState(() => startingResearch = false);
    }
  }

  int get revision => data!['revision']! as int;
  List<Map<String, Object?>> get stages => interviewMaps(data!['ladder']);
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Future<void> _stage([Map<String, Object?>? stage]) async {
    final expected = revision;
    final value = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _StageDialog(
        stage:
            stage ??
            newInterviewStage(const Uuid().v7(), 'New interview stage'),
      ),
    );
    if (value == null) {
      return;
    }
    await _action(() async {
      await widget.repository.saveStages(
        widget.jobId,
        expected,
        stage == null
            ? [...stages, value]
            : [for (final s in stages) s['id'] == value['id'] ? value : s],
      );
    });
  }

  Widget _stageFlow() {
    final visible = stages.where((s) => s['archived'] != true).toList();
    final current = currentInterviewStage(stages)?['id'];
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Interview stages'),
        const Text(
          'Select a stage to schedule it or change its status. Scheduled stages complete automatically after their start time plus duration.',
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Text('Add your first stage to schedule an interview.'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, stage) in visible.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, color: colors.outline),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 225,
                      maxWidth: 225,
                      minHeight: 190,
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: stage['id'] == current
                          ? colors.primaryContainer
                          : colors.surfaceContainer,
                      child: InkWell(
                        key: ValueKey('interview-stage-${stage['id']}'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: busy ? null : () => _stage(stage),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(switch (stage['status']) {
                                    'completed' => Icons.check_circle,
                                    'scheduled' => Icons.event,
                                    'cancelled' => Icons.cancel_outlined,
                                    'skipped' => Icons.skip_next,
                                    _ => Icons.radio_button_unchecked,
                                  }),
                                  const SizedBox(width: 8),
                                  Text(_label(stage['status']! as String)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${index + 1}. ${stage['name']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                interviewStageStart(stage) == null
                                    ? (stage['status'] == 'completed'
                                          ? 'Date not recorded'
                                          : 'Not scheduled')
                                    : _appointment(
                                        context,
                                        interviewStageStart(stage)!,
                                      ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('${stage['duration_minutes']} minutes'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : _stage,
          icon: const Icon(Icons.add),
          label: const Text('Add stage'),
        ),
      ],
    );
  }

  Future<void> _context() async {
    final expected = revision;
    final materials = await widget.repository.materials(widget.jobId);
    if (!mounted) {
      return;
    }
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ContextDialog(materials: materials),
    );
    if (result == null) {
      return;
    }
    await _action(() async {
      await widget.repository.saveContext(
        widget.jobId,
        expected,
        materialSetId: result['material_set_id'] as String?,
        submittedText: result['submitted_text'] as String?,
        attribution: result['attribution']! as String,
      );
    });
  }

  Future<void> _start() async {
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _PracticeDialog(stages: stages),
    );
    if (selected == null) {
      return;
    }
    await _action(() async {
      final practice = await widget.repository.startPractice(
        widget.jobId,
        selected['stage_id'] as String?,
        const Uuid().v7(),
        interviewMap(selected['settings']),
      );
      if (mounted) {
        await _showPractice(practice['practice_id']! as String);
      }
    });
  }

  Future<void> _showPractice(String id) async {
    final practice = await widget.repository.practice(id);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _PracticeDetail(practice: practice, repository: widget.repository),
    );
    await _load();
  }

  Future<void> _question([Map<String, Object?>? question]) async {
    final expected = revision;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _QuestionDialog(
        stages: stages,
        questions: interviewMaps(interviewMap(data!['questions'])['questions']),
        question: question,
      ),
    );
    if (selected != null) {
      await _action(() async {
        await widget.repository.saveQuestion(widget.jobId, expected, selected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: error == null ? const CircularProgressIndicator() : Text(error!),
      );
    }
    final researchState = data!['preparation_state'];
    final researching =
        startingResearch || ['queued', 'running'].contains(researchState);
    final researchLabel = startingResearch
        ? 'Starting research…'
        : switch (researchState) {
            'queued' => 'Research queued…',
            'running' => 'Research in progress…',
            _ => null,
          };
    final settings = interviewMap(data!['settings']);
    final intelRevision = data!['intel'] == null
        ? null
        : interviewMap(data!['intel']);
    final intel = intelRevision == null
        ? null
        : interviewMap(intelRevision['payload']);
    final bank = interviewMap(data!['questions']);
    final questions = interviewMaps(bank['questions'])
        .where((q) => stageFilter == null || q['stage_id'] == stageFilter)
        .toList();
    final target = [
      if (widget.jobTitle != null) widget.jobTitle!,
      if (company != null) company!.displayName,
    ].join(' at ');
    final practiceRequest =
        "Let's practice my interview for ${target.isEmpty ? 'this job' : target}.";
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in [
                'Overview',
                'Question bank',
                'Progress',
                'Settings',
              ])
                ChoiceChip(
                  label: Text(name),
                  selected: section == name,
                  onSelected: (_) => setState(() => section = name),
                ),
            ],
          ),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (section == 'Overview') ...[
            _stageFlow(),
            _heading('Practice in your voice harness'),
            Card(
              margin: const EdgeInsets.only(top: 4, bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentInterviewStage(stages) == null
                          ? (stages.isEmpty
                                ? 'No current stage yet'
                                : 'No unfinished stages')
                          : 'Current stage: ${currentInterviewStage(stages)!['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Open your preferred AI harness with the CareerShopper skill and MCP connected.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '2. Enable voice in that harness and say, or paste, this request:',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: SelectableText(
                        practiceRequest,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                '$practiceRequest\nCareerShopper job ID: ${widget.jobId}',
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Request copied. Paste it into your voice harness.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy practice request'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '3. Answer the questions aloud. Ask for clarification, pause, or say “End practice” when you are done. Come back to Progress for your saved feedback and scores.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      currentInterviewStage(stages) == null
                          ? 'Prepare the research or add your interview stages first so the agent knows which stage to practice.'
                          : 'The agent uses your current stage, interview intel and latest application documents. Difficulty starts easy and increases as you complete practices.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => section = 'Settings'),
                          child: const Text('Edit interview stages'),
                        ),
                        TextButton(
                          onPressed:
                              busy || !stages.any((s) => s['archived'] != true)
                              ? null
                              : _start,
                          child: const Text('Customize practice'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Connect your harness'),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Install the CareerShopper agent skill and register its MCP helper in your harness. From the CareerShopper source folder, run make mcp-info to see the installed helper command. Use it in your harness’s MCP settings, then restart or reload the harness. Voice must be supported and enabled in that harness. Feedback can only use conversation text the harness can access.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (company?.logoPng case final logo?)
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.memory(
                    logo,
                    width: 128,
                    height: 64,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    semanticLabel: '${company!.displayName} logo',
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            _heading('Company and interview intel'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy || widget.onPrepare == null || researching
                      ? null
                      : _prepareResearch,
                  icon: researching
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    researchLabel ??
                        (intel == null
                            ? 'Prepare with AI'
                            : 'Refresh research'),
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(switch (researchState) {
                    _ when startingResearch => 'Starting your AI agent.',
                    'queued' => 'Waiting for the AI agent to start.',
                    'running' =>
                      'The AI agent is researching this job. You can keep using CareerShopper.',
                    'ready' => 'Research ready',
                    'failed' => 'Research failed. Retry to continue.',
                    'paused' => 'Research paused',
                    _ => 'Research has not started',
                  }),
                ),
              ],
            ),
            if (data!['preparation_error'] != null)
              Text(
                '${data!['preparation_error']}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (intel == null)
              const Text(
                'Choose Prepare with AI to research the company and its interview process, and build practice questions for this job.',
              ),
            if (intel != null) ...[
              for (final section in [
                'company',
                if (showMoreIntel) 'team',
                if (showMoreIntel) 'process',
                if (showMoreIntel) 'questions',
                if (showMoreIntel) 'exercises',
                if (showMoreIntel) 'listening',
              ])
                _IntelSection(
                  title: Text(_label(section)),
                  children: [
                    for (final assertion in interviewMaps(
                      intel['assertions'],
                    ).where((a) => a['section'] == section))
                      ListTile(
                        title: SelectableText(assertion['text']! as String),
                        subtitle: Text(
                          '${assertion['evidence']} · sources: ${(assertion['source_ids'] as List).join(', ')}',
                        ),
                      ),
                  ],
                ),
              if (showMoreIntel) ...[
                _IntelSection(
                  title: const Text('Public professional roster'),
                  children: [
                    for (final person in interviewMaps(intel['roster']))
                      ListTile(
                        title: Text('${person['name']} · ${person['role']}'),
                        subtitle: Text(
                          '${person['relevance']}\n${person['evidence']} · ${(person['source_ids'] as List).join(', ')}',
                        ),
                      ),
                  ],
                ),
                _IntelSection(
                  title: const Text('Proposed stages'),
                  children: [
                    for (final stage in interviewMaps(intel['stage_proposals']))
                      ListTile(
                        title: Text(stage['name']! as String),
                        subtitle: Text(stage['purpose']! as String),
                        trailing: TextButton(
                          onPressed:
                              busy || stages.any((s) => s['id'] == stage['id'])
                              ? null
                              : () => _action(() async {
                                  if (stages.any(
                                    (s) => s['id'] == stage['id'],
                                  )) {
                                    throw StateError(
                                      'This stage is already in the ladder. Edit it above.',
                                    );
                                  }
                                  await widget.repository.saveStages(
                                    widget.jobId,
                                    revision,
                                    [...stages, stage],
                                  );
                                }),
                          child: Text(
                            stages.any((s) => s['id'] == stage['id'])
                                ? 'In ladder'
                                : 'Add to ladder',
                          ),
                        ),
                      ),
                  ],
                ),
                _IntelSection(
                  title: const Text('Sources and gaps'),
                  children: [
                    for (final source in interviewMaps(intel['sources']))
                      ListTile(
                        title: Text('${source['id']}: ${source['title']}'),
                        subtitle: SelectableText(
                          '${source['url']}\nRetrieved ${_when(context, source['retrieved_at'])} · ${source['context']}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Open source',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _action(
                            () => openExternalUrl(
                              Uri.parse(source['url']! as String),
                            ),
                          ),
                        ),
                      ),
                    for (final gap in intel['gaps'] as List)
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text('$gap'),
                      ),
                  ],
                ),
              ],
              TextButton(
                onPressed: () => setState(() => showMoreIntel = !showMoreIntel),
                child: Text(showMoreIntel ? 'Less' : 'More…'),
              ),
            ],
          ],
          if (section == 'Question bank') ...[
            _heading('Question bank'),
            DropdownButtonFormField<String>(
              initialValue: stageFilter ?? '',
              decoration: const InputDecoration(labelText: 'Stage filter'),
              items: [
                const DropdownMenuItem(value: '', child: Text('All stages')),
                for (final s in stages)
                  DropdownMenuItem(
                    value: s['id']! as String,
                    child: Text(s['name']! as String),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  questionLimit = 50;
                  stageFilter = value == '' ? null : value;
                });
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Your agent chooses a varied selection for each practice. Browse or edit these only when you want to.',
            ),
            TextButton.icon(
              onPressed: busy || stages.isEmpty ? null : _question,
              icon: const Icon(Icons.add),
              label: const Text('Add question'),
            ),
            Text(
              '${questions.length} questions in this view. Each practice uses a randomized selection with prerequisites kept in order.',
            ),
            for (final target in interviewMaps(bank['stage_targets'] ?? []))
              if ((target['available']! as int) < (target['target']! as int))
                Text(
                  'Bank still needs expansion: ${stages.where((s) => s['id'] == target['stage_id']).firstOrNull?['name'] ?? target['stage_id']} has ${target['available']} of ${target['target']} target questions.',
                ),
            if (questions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No questions for this stage yet.'),
              ),
            for (final q in questions.take(questionLimit))
              ExpansionTile(
                title: Text(
                  '${q['prompt']}${q['archived'] == true ? ' (archived)' : ''}',
                ),
                subtitle: Text(
                  '${q['kind']} · ${q['topic']} · difficulty ${q['difficulty']}',
                ),
                children: [
                  _readable({
                    'Why': q['rationale'],
                    'Criteria': q['criteria'],
                    'Follow-ups': q['follow_ups'],
                    'Application reference': q['application_reference'],
                    'Prerequisites': [
                      for (final id in q['depends_on'] as List? ?? [])
                        interviewMaps(bank['questions'])
                                .where((p) => p['id'] == id)
                                .firstOrNull?['prompt'] ??
                            id,
                    ],
                  }),
                  TextButton(
                    onPressed: busy ? null : () => _question(q),
                    child: const Text('Edit question'),
                  ),
                ],
              ),
            if (questions.length > questionLimit)
              TextButton(
                onPressed: () => setState(() => questionLimit += 50),
                child: const Text('Load more questions'),
              ),
            for (final gap in bank['coverage_gaps'] as List)
              Text('Coverage gap: $gap'),
          ],
          if (section == 'Progress') ...[
            _heading('Practice history'),
            if ((history?['practices'] as List? ?? []).isEmpty)
              const Text(
                'Your saved mock interviews and feedback will appear here.',
              ),
            for (final p in interviewMaps(history?['practices'] ?? []))
              ListTile(
                title: Text(
                  '${interviewMap(p['stage'])['name']} · ${p['status']}',
                ),
                subtitle: Text(
                  '${_when(context, p['created_at'])} · ${_score(interviewMap(p['assessment'])['score'])} · ${interviewMap(p['settings'])['personality']}',
                ),
                onTap: () =>
                    _action(() => _showPractice(p['practice_id']! as String)),
              ),
            _heading('Performance over time'),
            const Text(
              'Completed sessions are grouped by stage, difficulty, personality, coaching, rubric, and known model. Missing criteria stay unassessed.',
            ),
            _TrendChart(groups: interviewMaps(statistics?['groups'] ?? [])),
          ],
          if (section == 'Settings') ...[
            ExpansionTile(
              title: const Text('Automatic preparation'),
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Moving a job to Interviewing automatically starts research and question preparation using your default agent. You can choose another agent or turn this off. Pending jobs are prepared while the desktop app is running.',
                  ),
                ),
                StreamBuilder<List<AiHarnessProfile>>(
                  stream: widget.harnesses.watchProfiles(),
                  builder: (context, snapshot) {
                    final profiles = (snapshot.data ?? [])
                        .where((p) => p.protocol == 'acp_stdio')
                        .toList();
                    final selected =
                        profiles.any((p) => p.id == settings['agent_id'])
                        ? settings['agent_id'] as String
                        : '';
                    return Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selected,
                          decoration: const InputDecoration(
                            labelText: 'Research agent',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Use default agent'),
                            ),
                            for (final p in profiles)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (value) => _action(
                                  () => widget.repository
                                      .configureAutomaticPreparation(
                                        enabled:
                                            settings['auto_prepare'] == true,
                                        agentId: value == '' ? null : value,
                                      ),
                                ),
                        ),
                        SwitchListTile(
                          title: const Text('Prepare interviews automatically'),
                          value: settings['auto_prepare'] == true,
                          onChanged: busy
                              ? null
                              : (value) => _action(
                                  () => widget.repository
                                      .configureAutomaticPreparation(
                                        enabled: value,
                                        agentId: selected == ''
                                            ? null
                                            : selected,
                                      ),
                                ),
                        ),
                        if (profiles.isEmpty)
                          const Text(
                            'Configure a default agent in AI → Agents. Automatic preparation will wait until one is available.',
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
            _heading('Interview ladder'),
            if (stages.isEmpty)
              const Text(
                'Add your actual stages, or let AI propose a ladder during preparation.',
              ),
            for (final (index, stage) in stages.indexed)
              Card(
                child: ListTile(
                  title: Text(
                    '${index + 1}. ${stage['name']}${stage['archived'] == true ? ' (archived)' : ''}',
                  ),
                  subtitle: Text(
                    '${stage['category']} · ${stage['format']} · ${stage['duration_minutes']} min · ${stage['status']}\n${stage['purpose']}',
                  ),
                  onTap: busy ? null : () => _stage(stage),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move stage up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: busy || index == 0
                            ? null
                            : () => _action(() async {
                                final reordered = [...stages];
                                final previous = reordered[index - 1];
                                reordered[index - 1] = stage;
                                reordered[index] = previous;
                                await widget.repository.saveStages(
                                  widget.jobId,
                                  revision,
                                  reordered,
                                );
                              }),
                      ),
                      IconButton(
                        tooltip: 'Duplicate stage',
                        icon: const Icon(Icons.copy),
                        onPressed: busy
                            ? null
                            : () => _action(() async {
                                await widget.repository.saveStages(
                                  widget.jobId,
                                  revision,
                                  [
                                    ...stages,
                                    {
                                      ...stage,
                                      'id': const Uuid().v7(),
                                      'name': '${stage['name']} (copy)',
                                    },
                                  ],
                                );
                              }),
                      ),
                    ],
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: busy ? null : _stage,
              icon: const Icon(Icons.add),
              label: const Text('Add stage'),
            ),
            _heading('Application context'),
            Text(
              data!['application_context'] == null
                  ? 'No application documents saved for this job yet.'
                  : interviewMap(
                          interviewMap(data!['application_context'])['payload'],
                        )['attribution'] ==
                        'latest_application_documents'
                  ? 'Using your latest application resume and cover letter automatically.'
                  : 'Using your selected application documents or submitted answers.',
            ),
            TextButton.icon(
              onPressed: busy ? null : () => _action(_context),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Change application context'),
            ),
            if (data!['application_context'] != null)
              ExpansionTile(
                title: const Text('Read selected application context'),
                children: [
                  _readable(
                    interviewMap(
                      interviewMap(data!['application_context'])['payload'],
                    ),
                  ),
                ],
              ),
            if ((data!['revisions'] as List).isNotEmpty)
              ExpansionTile(
                title: const Text('Saved preparation revisions'),
                children: [
                  for (final rev in interviewMaps(data!['revisions']))
                    ListTile(
                      title: Text(
                        '${rev['kind']} · ${_when(context, rev['created_at'])}',
                      ),
                      onTap: () => _action(() async {
                        final saved = await widget.repository.revision(
                          widget.jobId,
                          rev['id']! as String,
                        );
                        if (context.mounted) {
                          await showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text('${rev['kind']} revision'),
                              content: SizedBox(
                                width: 650,
                                child: SingleChildScrollView(
                                  child: _readable(saved!['payload']),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      }),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

String _appointment(BuildContext context, DateTime value) {
  final date = value.toLocal();
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(date)}, ${date.year}\n${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))} ${date.timeZoneName}';
}

String _when(BuildContext context, Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '$value';
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(date)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

String _label(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
String _score(Object? score) =>
    score == null ? 'Unassessed' : '${(score as num).toStringAsFixed(1)}/100';
Widget _readable(Object? value) {
  if (value is Map) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in value.entries)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label('${e.key}'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                _readable(e.value),
              ],
            ),
          ),
      ],
    );
  }
  if (value is List) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in value)
          Padding(padding: const EdgeInsets.all(6), child: _readable(item)),
      ],
    );
  }
  return SelectableText(value == null ? 'Not available' : '$value');
}

Widget _input(
  TextEditingController controller,
  String label, {
  int lines = 1,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: TextField(
    controller: controller,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: lines > 1,
    ),
  ),
);
List<String> _lines(String value) =>
    value.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

class _StageDialog extends StatefulWidget {
  const _StageDialog({required this.stage});
  final Map<String, Object?> stage;
  @override
  State<_StageDialog> createState() => _StageDialogState();
}

class _StageDialogState extends State<_StageDialog> {
  late final value = interviewMap(jsonDecode(jsonEncode(widget.stage)));
  late final fields = {
    for (final k in ['name', 'purpose', 'format', 'duration_minutes', 'notes'])
      k: TextEditingController(text: '${value[k]}'),
    'competencies': TextEditingController(
      text: (value['competencies'] as List).join('\n'),
    ),
  };
  late final weights = {
    for (final e in interviewMap(value['weights']).entries)
      e.key: TextEditingController(text: '${e.value}'),
  };
  late DateTime? scheduled = interviewStageStart(value)?.toLocal();
  String? error;

  Future<void> _schedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: scheduled ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: scheduled == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(scheduled!),
    );
    if (time == null || !mounted) return;
    setState(() {
      scheduled = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      value['status'] = 'scheduled';
    });
  }

  @override
  void dispose() {
    for (final c in [...fields.values, ...weights.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _interviewer([int? index]) async {
    final people = interviewMaps(value['interviewers']);
    final p = index == null
        ? {
            'name': '',
            'role': '',
            'evidence': 'user_confirmed',
            'reason': '',
            'source_ids': <Object?>[],
          }
        : people[index];
    final name = TextEditingController(text: p['name'] as String),
        role = TextEditingController(text: p['role'] as String),
        reason = TextEditingController(text: p['reason'] as String),
        sources = TextEditingController(
          text: (p['source_ids'] as List).join('\n'),
        );
    var evidence = p['evidence']! as String;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Interviewer assignment'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _input(name, 'Name (optional)'),
                  _input(role, 'Role'),
                  DropdownButtonFormField<String>(
                    initialValue: evidence,
                    items: [
                      for (final e in [
                        'user_confirmed',
                        'reported',
                        'inferred',
                        'unknown',
                      ])
                        DropdownMenuItem(value: e, child: Text(_label(e))),
                    ],
                    onChanged: (v) => setLocal(() => evidence = v!),
                  ),
                  _input(reason, 'Why this person may interview you', lines: 3),
                  _input(sources, 'Source IDs, one per line', lines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'name': name.text,
                'role': role.text,
                'reason': reason.text,
                'evidence': evidence,
                'source_ids': _lines(sources.text),
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, role, reason, sources]) {
      c.dispose();
    }
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          people.add(result);
        } else {
          people[index] = result;
        }
        value['interviewers'] = people;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit interview stage'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(fields['name']!, 'Stage name'),
            Text(
              scheduled == null
                  ? 'Not scheduled'
                  : _appointment(context, scheduled!),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Times are shown in your computer’s local timezone (${scheduled?.timeZoneName ?? DateTime.now().timeZoneName}).',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _schedule,
                  icon: const Icon(Icons.event),
                  label: Text(
                    scheduled == null
                        ? 'Schedule interview'
                        : 'Change date and time',
                  ),
                ),
                if (scheduled != null)
                  TextButton(
                    onPressed: () => setState(() {
                      scheduled = null;
                      if (value['status'] == 'scheduled') {
                        value['status'] = 'planned';
                      }
                    }),
                    child: const Text('Clear schedule'),
                  ),
              ],
            ),
            _input(fields['duration_minutes']!, 'Duration in minutes'),
            DropdownButtonFormField<String>(
              key: ValueKey(value['status']),
              initialValue: value['status'] as String,
              decoration: const InputDecoration(labelText: 'Stage status'),
              items: [
                for (final v in [
                  'planned',
                  'scheduled',
                  'completed',
                  'skipped',
                  'cancelled',
                ])
                  DropdownMenuItem(value: v, child: Text(_label(v))),
              ],
              onChanged: (v) => setState(() => value['status'] = v),
            ),
            const Text(
              'Scheduled stages complete when their expected duration has elapsed. Choose Planned to keep a stage open without automatic completion.',
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: value['category'] as String,
              decoration: const InputDecoration(labelText: 'Interview role'),
              items: [
                for (final v in [
                  'screen',
                  'manager',
                  'technical',
                  'executive',
                  'panel',
                  'other',
                ])
                  DropdownMenuItem(value: v, child: Text(_label(v))),
              ],
              onChanged: (v) => setState(() => value['category'] = v),
            ),
            _input(fields['purpose']!, 'Purpose and focus', lines: 3),
            _input(
              fields['competencies']!,
              'Competencies, one per line',
              lines: 3,
            ),
            _input(
              fields['format']!,
              'Format (video, coding, take-home, panel…)',
            ),
            _input(fields['notes']!, 'Preparation notes', lines: 3),
            SwitchListTile(
              title: const Text('Archive stage'),
              subtitle: const Text('Keep its questions and practice history.'),
              value: value['archived'] == true,
              onChanged: (v) => setState(() => value['archived'] = v),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Interviewer assignments'),
            ),
            for (final (index, p) in interviewMaps(
              value['interviewers'],
            ).indexed)
              ListTile(
                title: Text('${p['name']} · ${p['role']}'),
                subtitle: Text('${p['evidence']}'),
                onTap: () => _interviewer(index),
                trailing: IconButton(
                  tooltip: 'Remove assignment',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(
                    () => (value['interviewers'] as List).removeAt(index),
                  ),
                ),
              ),
            TextButton(
              onPressed: _interviewer,
              child: const Text('Add interviewer'),
            ),
            ExpansionTile(
              title: const Text('Scoring weights'),
              subtitle: const Text(
                '0 disables a criterion; at least one must be positive.',
              ),
              children: [
                for (final e in weights.entries) _input(e.value, _label(e.key)),
              ],
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            for (final e in fields.entries) {
              value[e.key] = e.key == 'competencies'
                  ? _lines(e.value.text)
                  : e.key == 'duration_minutes'
                  ? int.parse(e.value.text)
                  : e.value.text;
            }
            value['scheduled_at'] = scheduled?.toUtc().toIso8601String() ?? '';
            value['timezone'] = scheduled?.timeZoneName ?? '';
            value['weights'] = {
              for (final e in weights.entries) e.key: num.parse(e.value.text),
            };
            validateInterviewLadder([value]);
            Navigator.pop(context, value);
          } on Object catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Save stage'),
      ),
    ],
  );
}

class _ContextDialog extends StatefulWidget {
  const _ContextDialog({required this.materials});
  final List<Map<String, Object?>> materials;
  @override
  State<_ContextDialog> createState() => _ContextDialogState();
}

class _ContextDialogState extends State<_ContextDialog> {
  final text = TextEditingController();
  String selection = '', attribution = 'selected_for_practice';
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Application context'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose what the employer received, or select materials only for practice. Submitted text is historical context and does not confirm new career facts.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selection,
              decoration: const InputDecoration(labelText: 'Documents'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Paste submitted documents or answers'),
                ),
                for (final m in widget.materials)
                  DropdownMenuItem(
                    value: m['id']! as String,
                    child: Text(
                      'Saved pair · ${_when(context, m['created_at'])}',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => selection = v!),
            ),
            if (selection.isEmpty)
              _input(
                text,
                'Submitted resume, cover letter, or application answers',
                lines: 12,
              )
            else
              _readable(
                widget.materials.firstWhere((m) => m['id'] == selection),
              ),
            DropdownButtonFormField<String>(
              initialValue: attribution,
              decoration: const InputDecoration(
                labelText: 'How these documents were used',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'selected_for_practice',
                  child: Text('Selected for practice'),
                ),
                DropdownMenuItem(
                  value: 'user_confirmed_submitted',
                  child: Text('I confirm I submitted these'),
                ),
              ],
              onChanged: (v) => setState(() => attribution = v!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          if (selection.isEmpty)
            'submitted_text': text.text
          else
            'material_set_id': selection,
          'attribution': attribution,
        }),
        child: const Text('Save context'),
      ),
    ],
  );
}

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({
    required this.stages,
    required this.questions,
    this.question,
  });
  final List<Map<String, Object?>> questions;
  final List<Map<String, Object?>> stages;
  final Map<String, Object?>? question;
  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final dependencies = (widget.question?['depends_on'] as List? ?? [])
      .cast<String>()
      .toSet();
  late final value = {...?widget.question};
  late String stage =
      (value['stage_id'] as String?) ?? widget.stages.first['id']! as String;
  late int difficulty = (value['difficulty'] as int?) ?? 3;
  late bool archived = value['archived'] == true;
  late final fields = {
    for (final k in [
      'prompt',
      'topic',
      'rationale',
      'application_reference',
      'criteria',
      'follow_ups',
      'source_ids',
    ])
      k: TextEditingController(
        text: value[k] is List
            ? (value[k] as List).join('\n')
            : '${value[k] ?? ''}',
      ),
  };
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Practice question'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: stage,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [
                for (final s in widget.stages)
                  DropdownMenuItem(
                    value: s['id']! as String,
                    child: Text(s['name']! as String),
                  ),
              ],
              onChanged: (v) => setState(() {
                stage = v!;
                dependencies.clear();
              }),
            ),
            _input(fields['prompt']!, 'Question or exercise', lines: 4),
            _input(fields['topic']!, 'Topic'),
            _input(fields['rationale']!, 'Why it matters', lines: 3),
            _input(
              fields['criteria']!,
              'Assessment criteria, one per line',
              lines: 3,
            ),
            _input(
              fields['follow_ups']!,
              'Follow-up questions, one per line',
              lines: 4,
            ),
            _input(
              fields['application_reference']!,
              'Application passage to discuss',
              lines: 3,
            ),
            _input(
              fields['source_ids']!,
              'Research source IDs, one per line',
              lines: 2,
            ),
            ExpansionTile(
              title: const Text('Prerequisite questions'),
              children: [
                for (final q in widget.questions.where(
                  (q) =>
                      q['stage_id'] == stage &&
                      q['id'] != value['id'] &&
                      q['archived'] != true,
                ))
                  CheckboxListTile(
                    title: Text(q['prompt']! as String),
                    value: dependencies.contains(q['id']),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        dependencies.add(q['id']! as String);
                      } else {
                        dependencies.remove(q['id']);
                      }
                    }),
                  ),
              ],
            ),
            Text('Difficulty: $difficulty'),
            Slider(
              value: difficulty.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (v) => setState(() => difficulty = v.round()),
            ),
            SwitchListTile(
              title: const Text('Archive question'),
              value: archived,
              onChanged: (v) => setState(() => archived = v),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final q = {
            'id': value['id'] ?? const Uuid().v7(),
            'stage_id': stage,
            'kind': 'user',
            'difficulty': difficulty,
            'archived': archived,
            'depends_on': dependencies.toList(),
            for (final e in fields.entries)
              e.key: ['criteria', 'follow_ups', 'source_ids'].contains(e.key)
                  ? _lines(e.value.text)
                  : e.value.text,
          };
          try {
            validateInterview(q, interviewQuestionSchema);
            Navigator.pop(context, q);
          } on Object catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Save question'),
      ),
    ],
  );
}

class _PracticeDialog extends StatefulWidget {
  const _PracticeDialog({required this.stages});
  final List<Map<String, Object?>> stages;
  @override
  State<_PracticeDialog> createState() => _PracticeDialogState();
}

class _PracticeDialogState extends State<_PracticeDialog> {
  String stage = '';
  String personality = 'neutral';
  int difficulty = 2;
  bool automaticDifficulty = true;
  bool coaching = false;
  final instructions = TextEditingController(
    text: interviewPersonalities['neutral'],
  );
  final minutes = TextEditingController(text: '30'),
      harness = TextEditingController(),
      model = TextEditingController();
  String? error;
  @override
  void dispose() {
    for (final c in [instructions, minutes, harness, model]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up mock interview'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose your stage and interviewer style, then use the generated prompt in your voice harness. Difficulty controls depth and pressure; personality controls conversational style.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: stage,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    'Current stage: ${currentInterviewStage(widget.stages)?['name'] ?? 'not recorded'}',
                  ),
                ),
                for (final s in widget.stages.where(
                  (s) => s['archived'] != true,
                ))
                  DropdownMenuItem(
                    value: s['id']! as String,
                    child: Text(s['name']! as String),
                  ),
              ],
              onChanged: (v) => setState(() => stage = v!),
            ),
            SwitchListTile(
              title: const Text('Increase difficulty as I practice'),
              subtitle: const Text(
                'Start at 2/5. Every two completed practices for this job and stage raises the level, up to 5/5.',
              ),
              value: automaticDifficulty,
              onChanged: (value) => setState(() => automaticDifficulty = value),
            ),
            if (!automaticDifficulty) Text('Difficulty: $difficulty / 5'),
            if (!automaticDifficulty)
              Slider(
                value: difficulty.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setState(() => difficulty = v.round()),
              ),
            DropdownButtonFormField<String>(
              initialValue: personality,
              decoration: const InputDecoration(labelText: 'Personality'),
              items: [
                for (final p in interviewPersonalities.keys)
                  DropdownMenuItem(value: p, child: Text(_label(p))),
              ],
              onChanged: (v) => setState(() {
                personality = v!;
                instructions.text = interviewPersonalities[v]!;
              }),
            ),
            _input(instructions, 'Customize interviewer behavior', lines: 3),
            _input(minutes, 'Practice length in minutes'),
            SwitchListTile(
              title: const Text('Coaching mode'),
              subtitle: const Text(
                'Give feedback during the interview; track separately from unassisted attempts.',
              ),
              value: coaching,
              onChanged: (v) => setState(() => coaching = v),
            ),
            _input(harness, 'Harness (optional)'),
            _input(model, 'Model (optional)'),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final settings = {
              if (!automaticDifficulty) 'difficulty': difficulty,
              'personality': personality,
              'personality_instructions': instructions.text,
              'minutes': int.parse(minutes.text),
              'coaching': coaching,
              'harness': harness.text,
              'model': model.text,
            };
            validateInterview(settings, interviewPracticeSettingsSchema);
            Navigator.pop(context, {
              if (stage.isNotEmpty) 'stage_id': stage,
              'settings': settings,
            });
          } on Object catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Create practice'),
      ),
    ],
  );
}

class _PracticeDetail extends StatefulWidget {
  const _PracticeDetail({required this.practice, required this.repository});
  final Map<String, Object?> practice;
  final InterviewRepository repository;
  @override
  State<_PracticeDetail> createState() => _PracticeDetailState();
}

class _PracticeDetailState extends State<_PracticeDetail> {
  late Map<String, Object?> practice = widget.practice;
  late final debrief = TextEditingController(
    text: practice['debrief']! as String,
  );
  String? error;
  bool busy = false;
  @override
  void dispose() {
    debrief.dispose();
    super.dispose();
  }

  Future<void> _state(String status) async {
    setState(() => busy = true);
    try {
      final result = await widget.repository.setPracticeState(
        practice['practice_id']! as String,
        practice['revision']! as int,
        status,
        debrief.text,
      );
      if (mounted) {
        setState(() => practice = result);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = interviewMap(practice['snapshot']);
    final finished = ['completed', 'abandoned'].contains(practice['status']);
    return AlertDialog(
      title: Text('Practice · ${practice['status']}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${interviewMap(snapshot['stage'])['name']} · ${_score(interviewMap(practice['assessment'])['score'])}',
              ),
              if (snapshot['context_warning'] != null)
                Text('${snapshot['context_warning']}'),
              const SizedBox(height: 12),
              Text(
                'Difficulty: ${interviewMap(snapshot['settings'])['difficulty']} / 5 · ${snapshot['difficulty_progression'] == null ? 'fixed' : interviewMap(snapshot['difficulty_progression'])['mode']}',
              ),
              SelectableText(practice['start_prompt']! as String),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: practice['start_prompt']! as String),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy prompt for your harness'),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final latest = await widget.repository.practice(
                          practice['practice_id']! as String,
                        );
                        if (mounted) {
                          setState(() => practice = latest);
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh checkpoints'),
              ),
              ExpansionTile(
                title: const Text('Pinned context and rubric'),
                children: [_readable(snapshot)],
              ),
              ExpansionTile(
                title: const Text('Score and assessment coverage'),
                children: [_readable(practice['assessment'])],
              ),
              for (final exchange in interviewMaps(practice['exchanges']))
                ExpansionTile(
                  title: Text(
                    'Question ${(exchange['sequence']! as int) + 1} · ${interviewMap(exchange['payload'])['transcript_kind']}',
                  ),
                  children: [
                    for (final turn in interviewMaps(
                      interviewMap(exchange['payload'])['turns'],
                    ))
                      ListTile(
                        title: Text(_label(turn['speaker']! as String)),
                        subtitle: SelectableText(turn['text']! as String),
                      ),
                    _readable(
                      {...interviewMap(exchange['payload'])}..remove('turns'),
                    ),
                    if ((exchange['previous_revisions'] as List).isNotEmpty)
                      ExpansionTile(
                        title: const Text('Earlier checkpoint revisions'),
                        children: [_readable(exchange['previous_revisions'])],
                      ),
                  ],
                ),
              if (!finished)
                _input(debrief, 'Final debrief', lines: 5)
              else
                SelectableText(practice['debrief']! as String),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!finished)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _state(
                              practice['status'] == 'paused'
                                  ? 'active'
                                  : 'paused',
                            ),
                      child: Text(
                        practice['status'] == 'paused' ? 'Resume' : 'Pause',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => _state('abandoned'),
                      child: const Text('Abandon'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : () => _state('completed'),
                      child: const Text('Complete practice'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TrendChart extends StatefulWidget {
  const _TrendChart({required this.groups});
  final List<Map<String, Object?>> groups;
  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int selected = 0;
  String dimension = 'overall';
  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Complete a practice to start a performance trend.'),
      );
    }
    selected = math.min(selected, widget.groups.length - 1);
    final group = widget.groups[selected],
        points = interviewMaps(widget.groups[selected]['points']);
    final plotted = [
      for (final p in points)
        if ((dimension == 'overall'
                ? p['score']
                : interviewMap(p['dimension_means'])[dimension]) !=
            null)
          {
            ...p,
            'plot_score': dimension == 'overall'
                ? p['score']
                : (interviewMap(p['dimension_means'])[dimension]! as num) * 25,
          },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Comparable sessions'),
          items: [
            for (final (i, g) in widget.groups.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '${interviewMap(g['group'])['category']} · difficulty ${interviewMap(g['group'])['difficulty']} · ${interviewMap(g['group'])['personality']} · ${interviewMap(g['group'])['coaching'] == true ? 'coached' : 'unassisted'} · ${interviewMap(g['group'])['model']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => selected = v!),
        ),
        DropdownButtonFormField<String>(
          initialValue: dimension,
          decoration: const InputDecoration(labelText: 'Score dimension'),
          items: [
            for (final d in ['overall', ...interviewDimensions])
              DropdownMenuItem(value: d, child: Text(_label(d))),
          ],
          onChanged: (v) => setState(() => dimension = v!),
        ),
        Text(
          '${group['sample_count']} completed ${group['sample_count'] == 1 ? 'session' : 'sessions'} · ${plotted.length} assessed for this dimension',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _ScorePainter(
              plotted,
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.outline,
              Theme.of(context).textTheme.bodySmall!,
            ),
          ),
        ),
        for (final point in plotted)
          Text(
            '${_when(context, point['date'])} · ${_score(point['plot_score'])} · ${point['graded_questions']} graded ${point['graded_questions'] == 1 ? 'question' : 'questions'}',
          ),
      ],
    );
  }
}

class _ScorePainter extends CustomPainter {
  _ScorePainter(this.points, this.color, this.outline, this.labelStyle);
  final TextStyle labelStyle;
  final List<Map<String, Object?>> points;
  final Color color, outline;
  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTWH(
      35,
      10,
      math.max(0, size.width - 50),
      math.max(0, size.height - 30),
    );
    final axis = Paint()
      ..color = outline
      ..strokeWidth = 1;
    for (final score in [0, 50, 100]) {
      final y = area.bottom - area.height * score / 100;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), axis);
      final label = TextPainter(
        text: TextSpan(
          text: '$score',
          style: labelStyle.copyWith(color: outline, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y - 6));
    }
    if (points.isEmpty) {
      return;
    }
    final dates = [
      for (final p in points)
        DateTime.parse(p['date']! as String).millisecondsSinceEpoch,
    ];
    final span = dates.last - dates.first;
    final coords = [
      for (var i = 0; i < points.length; i++)
        Offset(
          area.left +
              area.width * (span == 0 ? 0.5 : (dates[i] - dates.first) / span),
          area.bottom - area.height * (points[i]['plot_score']! as num) / 100,
        ),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var i = 0; i < coords.length; i++) {
      if (i > 0) {
        canvas.drawLine(coords[i - 1], coords[i], paint);
      }
      canvas.drawCircle(coords[i], 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScorePainter old) => true;
}

class _IntelSection extends StatelessWidget {
  const _IntelSection({required this.title, required this.children});
  final Widget title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle(
          style: Theme.of(context).textTheme.titleMedium!,
          child: title,
        ),
        const SizedBox(height: 8),
        if (children.isEmpty) const Text('No information found yet.'),
        ...children,
      ],
    ),
  );
}
