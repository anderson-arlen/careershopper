import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../storage/profile_repository.dart';
import '../../storage/resume_content_repository.dart';

class ResumeContentEditor extends StatefulWidget {
  const ResumeContentEditor({required this.profile, super.key});
  final ProfileStore profile;
  @override
  State<ResumeContentEditor> createState() => _ResumeContentEditorState();
}

class _ResumeContentEditorState extends State<ResumeContentEditor>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _data;
  String? _revision, _error;
  bool _dirty = false, _saving = false;
  final _expandedSections = <String>{};
  final _sectionKeys = {'skills': GlobalKey(), 'experience': GlobalKey()};
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _linkFocus = FocusNode();
  final _linkAnchors = <String, GlobalKey>{};
  Map? _linkSource, _linkOwner;
  Timer? _dragTimer;
  double _dragScrollStep = 0;
  @override
  void dispose() {
    _dragTimer?.cancel();
    _scroll.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  void _dragScroll(DragUpdateDetails details) {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(details.globalPosition).dy;
    _dragScrollStep = y < 64
        ? -16
        : y > box.size.height - 64
        ? 16
        : 0;
    if (_dragScrollStep == 0) {
      _stopDragScroll();
      return;
    }
    _dragTimer ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
        (_scroll.offset + _dragScrollStep).clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  void _stopDragScroll() {
    _dragTimer?.cancel();
    _dragTimer = null;
  }

  @override
  bool get wantKeepAlive => true;
  ResumeContentRepository get repository =>
      ResumeContentRepository(widget.profile);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await repository.get();
      if (!mounted) return;
      setState(() {
        _data =
            jsonDecode(jsonEncode(value['content'])) as Map<String, dynamic>;
        _revision = value['revision_id'] as String?;
        _linkSource = null;
        _linkOwner = null;
        _linkAnchors.clear();
        _dirty = false;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _dirty = true;
  });
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repository.save(
        _data!,
        expectedRevision: _revision,
        actor: 'desktop_user',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fixed resume wording saved.')),
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editFields(
    String title,
    Map target,
    Map<String, String> labels,
  ) async {
    final value = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) =>
          _WordingDialog(title: title, target: target, labels: labels),
    );
    if (value != null) _change(() => target.addAll(value));
  }

  Future<void> _achievement(List achievements, {Map? target}) async {
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _WordingDialog(
        title: target == null ? 'Add achievement' : 'Achievement',
        target: target ?? {'text': ''},
        labels: const {'text': 'Exact achievement wording'},
        achievementOptions: true,
      ),
    );
    if (value == null) return;
    _change(() {
      if (target == null) {
        achievements.add({'id': const Uuid().v7(), ...value});
      } else {
        target.addAll(value);
      }
    });
  }

  Future<void> _add(String section) async {
    final value = <String, dynamic>{'id': const Uuid().v7(), 'enabled': true};
    final fields = {
      ..._fields(section),
      if (section == 'experience') ...{
        'title': 'Exact job title',
        'dates': 'Date range',
      },
    };
    for (final field in fields.keys) {
      value[field] = '';
    }
    if (section == 'experience') value['achievements'] = <dynamic>[];
    final edited = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _WordingDialog(
        title: 'Add ${_singular(section)}',
        target: value,
        labels: fields,
      ),
    );
    if (edited != null) {
      _change(() {
        value.addAll(edited);
        if (section == 'experience') {
          value['titles'] = [
            {
              'title': value.remove('title'),
              'dates': value.remove('dates'),
              'achievements': value.remove('achievements'),
            },
          ];
        }
        (_data![section] as List).add(value);
        _expandedSections.add(section);
      });
    }
  }

  String _singular(String section) => switch (section) {
    'personal_context' => 'personal context',
    'skills' => 'skill',
    'experience' => 'role',
    'projects' => 'project',
    'patents' => 'patent',
    _ => 'education',
  };
  Map<String, String> _fields(String section) => switch (section) {
    'personal_context' => {
      'topic': 'Interest, domain or credential',
      'text': 'Confirmed details and any limitations',
    },
    'skills' => {
      'name': 'Skill or language',
      'proficiency': 'Proficiency (your assessment)',
      'notes': 'Experience, context and limitations',
    },
    'experience' => {'employer': 'Employer', 'location': 'Location'},
    'projects' => {
      'name': 'Project name',
      'stack': 'Technology stack',
      'dates': 'Dates as they should appear',
      'url': 'Public URL',
      'description': 'Project summary (always included)',
    },
    'patents' => {'text': 'Exact patent listing'},
    _ => {
      'heading': 'Institution / qualification heading',
      'details': 'Exact education details',
    },
  };
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_data == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!),
      );
    }
    final header = _data!['header'] as Map;
    return Focus(
      focusNode: _linkFocus,
      onKeyEvent: (_, event) {
        if (_linkSource != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _finishLinking();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _linkSource == null
                        ? 'All entries inform job matching. Turn entries on to allow them in applications. AI selects your saved wording.'
                        : 'Select prerequisites in this ${_linkOwner!.containsKey('employer') ? 'job' : 'project'}. Click again to unlink. Arrows point to prerequisites.',
                  ),
                ),
                if (_linkSource != null)
                  TextButton.icon(
                    onPressed: _finishLinking,
                    icon: const Icon(Icons.done),
                    label: const Text('Done linking'),
                  ),
                TextButton(
                  onPressed: _saving ? null : _load,
                  child: const Text('Reload'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving || (!_dirty && _revision != null)
                      ? null
                      : _save,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(_saving ? 'Saving…' : 'Save fixed wording'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              key: _viewport,
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_revision == null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Set the exact text below, then save it to enable fixed resume wording. Saving confirms this as your career history.',
                            ),
                          ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text('RESUME HEADER'),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit resume header',
                                      onPressed: () =>
                                          _editFields('Resume header', header, {
                                            'name': 'Full name',
                                            'contact': 'Contact line',
                                          }),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                                Text(
                                  (header['name'] as String).isEmpty
                                      ? 'Your name'
                                      : header['name'] as String,
                                  style: theme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'AI-generated professional headline',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (header['contact'] as String).isEmpty
                                      ? 'Contact information'
                                      : header['contact'] as String,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome, size: 18),
                                  SizedBox(width: 8),
                                  Text('TAILORED FOR EACH JOB'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Opening summary',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'AI writes one paragraph from enabled resume content.',
                              ),
                              const SizedBox(height: 12),
                              _heading('direct_match'),
                              const Text('AI writes relevant match bullets.'),
                              const SizedBox(height: 12),
                              const Text(
                                'Skill groups',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'AI selects and groups supported skills.',
                              ),
                            ],
                          ),
                        ),
                        for (final section in [
                          'skills',
                          'experience',
                          'projects',
                          'patents',
                          'education',
                          'personal_context',
                        ]) ...[
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  key: _sectionKeys[section],
                                  child: _heading(section),
                                ),
                              ),
                              if (section == 'skills')
                                TextButton(
                                  onPressed: _dirty || _saving
                                      ? null
                                      : _importSkills,
                                  child: const Text('Import saved skills'),
                                ),
                              OutlinedButton.icon(
                                onPressed: () => _add(section),
                                icon: const Icon(Icons.add),
                                label: Text('Add ${_singular(section)}'),
                              ),
                            ],
                          ),
                          Text(
                            section == 'personal_context'
                                ? 'Interests, domain connections and credentials can inform matching and tailored letters. Enabled entries may be used in prose; they are not printed automatically on your resume.'
                                : section == 'skills'
                                ? 'Proficiency and context guide matching and tailored writing. These notes are not printed verbatim.'
                                : section == 'experience'
                                ? 'AI may select enabled roles and individual achievements. Your wording and order stay fixed.'
                                : section == 'projects'
                                ? 'Every enabled project includes its summary. AI may select additional detail sentences.'
                                : 'Every enabled entry appears exactly as saved, in this order.',
                          ),
                          const SizedBox(height: 12),
                          if ((_data![section] as List).isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No ${section == 'experience' ? 'roles' : section} yet.',
                              ),
                            ),
                          ..._sectionEntries(section),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importSkills() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = await repository.importLegacySkills(actor: 'desktop_user');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count saved skills imported.')),
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Widget> _sectionEntries(String section) {
    final entries = (_data![section] as List).cast<Map>();
    final collapsible = _sectionKeys.containsKey(section) && entries.length > 3;
    final expanded = _expandedSections.contains(section);
    final preview = collapsible && !expanded;
    return [
      for (final (index, entry)
          in entries.take(preview ? 3 : entries.length).indexed)
        if (preview)
          Card(
            child: ListTile(
              title: Text(
                (entry[section == 'skills' ? 'name' : 'employer']) as String,
              ),
              subtitle: Text(
                section == 'skills'
                    ? ((entry['proficiency'] as String).isEmpty
                          ? 'Proficiency not specified'
                          : entry['proficiency'] as String)
                    : (entry['titles'] as List)
                          .map((t) => '${t['title']} · ${t['dates']}')
                          .join('\n'),
              ),
              leading: Icon(
                entry['enabled'] == true
                    ? Icons.check_circle_outline
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
            ),
          )
        else
          _entry(section, entry, index),
      if (collapsible)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('toggle-$section'),
            onPressed: _linkSource != null
                ? null
                : () {
                    setState(() {
                      if (expanded) {
                        _expandedSections.remove(section);
                      } else {
                        _expandedSections.add(section);
                      }
                    });
                    if (expanded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final target = _sectionKeys[section]?.currentContext;
                        if (target != null) Scrollable.ensureVisible(target);
                      });
                    }
                  },
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(
              expanded
                  ? 'Show fewer ${section == 'skills' ? 'skills' : 'roles'}'
                  : 'Show all ${entries.length} ${section == 'skills' ? 'skills' : 'roles'}',
            ),
          ),
        ),
    ];
  }

  Widget _heading(String section) => section == 'personal_context'
      ? Text(
          'Personal context',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        )
      : Row(
          children: [
            Flexible(
              child: Text(
                (_data!['headings'] as Map)[section] as String,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Edit $section section heading',
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: () => _editFields(
                'Section heading',
                _data!['headings'] as Map,
                {section: 'Heading'},
              ),
            ),
          ],
        );
  Widget _titleRow(List titles, Map title, int index) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (title['dates'] != '')
              Text(
                title['dates'] as String,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Edit title',
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: () => _editFields('Edit title', title, {
          'title': 'Exact job title',
          'dates': 'Date range',
        }),
      ),
      IconButton(
        tooltip: 'Move title up',
        icon: const Icon(Icons.arrow_upward, size: 18),
        onPressed: index == 0
            ? null
            : () => _change(() {
                titles.removeAt(index);
                titles.insert(index - 1, title);
              }),
      ),
      IconButton(
        tooltip: 'Move title down',
        icon: const Icon(Icons.arrow_downward, size: 18),
        onPressed: index == titles.length - 1
            ? null
            : () => _change(() {
                titles.removeAt(index);
                titles.insert(index + 1, title);
              }),
      ),
      IconButton(
        tooltip: 'Remove title',
        icon: const Icon(Icons.close, size: 18),
        onPressed:
            titles.length == 1 || (title['achievements'] as List).isNotEmpty
            ? null
            : () => _change(() => titles.removeAt(index)),
      ),
    ],
  );

  Widget _achievementTarget(
    Map employment,
    Map title,
    int index,
    Widget child, {
    Key? key,
  }) => DragTarget<_AchievementDrag>(
    key: key,
    onWillAcceptWithDetails: (details) =>
        identical(details.data.employment, employment),
    onAcceptWithDetails: (details) => _change(() {
      final from = details.data.title['achievements'] as List;
      final target = title['achievements'] as List;
      final oldIndex = from.indexOf(details.data.achievement);
      var insertAt = index;
      if (identical(from, target) && oldIndex < insertAt) insertAt--;
      from.removeAt(oldIndex);
      target.insert(insertAt.clamp(0, target.length), details.data.achievement);
      _stopDragScroll();
    }),
    builder: (context, candidates, rejected) => Container(
      decoration: BoxDecoration(
        border: candidates.isEmpty
            ? null
            : Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
      ),
      child: child,
    ),
  );

  void _removeAchievement(Map employment, List achievements, Map achievement) {
    _removeLinkedItem(achievements, achievement, [
      for (final title in (employment['titles'] as List).cast<Map>())
        ...(title['achievements'] as List).cast<Map>(),
    ]);
  }

  void _removeLinkedItem(
    List items,
    Map item,
    List<Map> peers, {
    bool project = false,
  }) {
    final dependents = [
      for (final other in peers)
        if (((other['requires'] ?? []) as List).contains(item['id']))
          other['text'] as String,
    ];
    if (dependents.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            project
                ? 'Detail is required by other sentences'
                : 'Achievement is required by other bullets',
          ),
          content: SingleChildScrollView(
            child: Text(
              'Remove the dependency links from these ${project ? 'sentences' : 'achievements'} before deleting this one:\n\n${dependents.join('\n\n')}',
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
      return;
    }
    _change(() => items.remove(item));
  }

  void _finishLinking() => setState(() {
    _linkSource = null;
    _linkOwner = null;
  });

  void _linkItem(Map employment, Map achievement) {
    if (identical(_linkSource, achievement)) {
      _finishLinking();
      return;
    }
    if (_linkSource == null) {
      setState(() {
        _linkSource = achievement;
        _linkOwner = employment;
      });
      _linkFocus.requestFocus();
      return;
    }
    if (!identical(_linkOwner, employment)) return;
    _change(() {
      final dependencies = ((_linkSource!['requires'] ?? []) as List)
          .cast<String>()
          .toList();
      final id = achievement['id'] as String;
      if (dependencies.contains(id)) {
        dependencies.remove(id);
      } else {
        dependencies.add(id);
      }
      _linkSource!['requires'] = dependencies;
    });
  }

  Widget _linkedTitles(Map employment) => _DependencyConnections(
    anchors: _linkAnchors,
    links: [
      for (final title in (employment['titles'] as List).cast<Map>())
        for (final a in (title['achievements'] as List).cast<Map>())
          for (final dependency in (a['requires'] ?? []) as List)
            (a['id'] as String, dependency as String),
    ],
    activeSource: _linkSource?['id'] as String?,
    color: Theme.of(context).colorScheme.primary,
    child: Padding(
      padding: const EdgeInsets.only(left: 42),
      child: Column(
        children: [
          for (final (index, title)
              in (employment['titles'] as List).cast<Map>().indexed)
            _titleSection(employment, title, index),
        ],
      ),
    ),
  );

  Widget _linkableItem(
    Map employment,
    Map achievement,
    Widget child, {
    String kind = 'achievement',
  }) {
    final source = identical(_linkSource, achievement);
    final selecting =
        _linkSource != null && identical(_linkOwner, employment) && !source;
    final selected =
        selecting &&
        ((_linkSource!['requires'] ?? []) as List).contains(achievement['id']);
    return Semantics(
      selected: source || selected,
      child: Material(
        key: ValueKey('$kind-select-${achievement['id']}'),
        color: source
            ? Theme.of(context).colorScheme.primaryContainer
            : selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: selecting ? () => _linkItem(employment, achievement) : null,
          child: child,
        ),
      ),
    );
  }

  Widget _linkButton(
    Map employment,
    Map achievement, {
    String kind = 'achievement',
  }) => SizedBox(
    key: _linkAnchors.putIfAbsent(achievement['id'] as String, GlobalKey.new),
    width: 40,
    height: 48,
    child: IconButton(
      key: ValueKey('$kind-link-${achievement['id']}'),
      tooltip: identical(_linkSource, achievement)
          ? 'Finish linking'
          : _linkSource != null
          ? 'Toggle prerequisite'
          : 'Link prerequisites',
      color: Theme.of(context).colorScheme.primary,
      onPressed: _linkSource != null && !identical(_linkOwner, employment)
          ? null
          : () => _linkItem(employment, achievement),
      icon:
          _linkSource != null &&
              identical(_linkOwner, employment) &&
              !identical(_linkSource, achievement)
          ? Icon(
              ((_linkSource!['requires'] ?? []) as List).contains(
                    achievement['id'],
                  )
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 20,
            )
          : Badge(
              isLabelVisible:
                  ((achievement['requires'] ?? []) as List).isNotEmpty,
              label: Text(
                '${((achievement['requires'] ?? []) as List).length}',
              ),
              child: const Icon(Icons.link, size: 20),
            ),
    ),
  );

  Widget _titleSection(Map employment, Map title, int titleIndex) {
    final achievements = title['achievements'] as List;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(employment['titles'] as List, title, titleIndex),
          for (final (i, achievement) in achievements.cast<Map>().indexed)
            _achievementTarget(
              employment,
              title,
              i,
              _linkableItem(
                employment,
                achievement,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _linkButton(employment, achievement),
                    Draggable<_AchievementDrag>(
                      data: _AchievementDrag(employment, title, achievement),
                      maxSimultaneousDrags: _linkSource == null ? 1 : 0,
                      onDragUpdate: _dragScroll,
                      onDragEnd: (_) => _stopDragScroll(),
                      feedback: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 480,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(achievement['text'] as String),
                          ),
                        ),
                      ),
                      childWhenDragging: const SizedBox(width: 40, height: 48),
                      child: Tooltip(
                        message: 'Drag achievement',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: SizedBox(
                            key: ValueKey(
                              'achievement-drag-${achievement['id']}',
                            ),
                            width: 40,
                            height: 48,
                            child: const Icon(Icons.drag_indicator, size: 20),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(achievement['text'] as String),
                            const SizedBox(height: 4),
                            Text(
                              '${achievement['priority'] ?? 0} points${achievement['required'] == true ? ' · Required when this job is included' : ''}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit achievement',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _linkSource != null
                          ? null
                          : () =>
                                _achievement(achievements, target: achievement),
                    ),
                    IconButton(
                      tooltip: 'Remove achievement',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _linkSource != null
                          ? null
                          : () => _removeAchievement(
                              employment,
                              achievements,
                              achievement,
                            ),
                    ),
                  ],
                ),
              ),
              key: ValueKey('achievement-drop-${achievement['id']}'),
            ),
          _achievementTarget(
            employment,
            title,
            achievements.length,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Text(
                achievements.isEmpty
                    ? 'Add or drop an achievement here'
                    : 'Drop an achievement here to place it last',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            key: ValueKey('achievement-end-${employment['id']}-$titleIndex'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add achievement'),
              onPressed: _linkSource != null
                  ? null
                  : () => _achievement(achievements),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTarget(Map project, int index, Widget child, {Key? key}) =>
      DragTarget<Map>(
        key: key,
        onWillAcceptWithDetails: (drag) =>
            _linkSource == null &&
            ((project['details'] ?? []) as List).contains(drag.data),
        onAcceptWithDetails: (drag) => _change(() {
          final details = project['details'] as List;
          final oldIndex = details.indexOf(drag.data);
          final insertAt = oldIndex < index ? index - 1 : index;
          details.removeAt(oldIndex);
          details.insert(insertAt, drag.data);
          _stopDragScroll();
        }),
        builder: (context, candidates, rejected) => Container(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
          ),
          child: child,
        ),
      );

  Widget _projectDetails(Map project) {
    final details = (project['details'] ?? []) as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Optional detail sentences',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'AI may select relevant sentences together with their prerequisites. Drag to reorder; wording stays exact.',
        ),
        _DependencyConnections(
          anchors: _linkAnchors,
          links: [
            for (final detail in details.cast<Map>())
              for (final dependency in (detail['requires'] ?? []) as List)
                (detail['id'] as String, dependency as String),
          ],
          activeSource: _linkSource?['id'] as String?,
          color: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, detail) in details.cast<Map>().indexed)
                  _detailTarget(
                    project,
                    index,
                    _linkableItem(
                      project,
                      detail,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _linkButton(project, detail, kind: 'detail'),
                          Draggable<Map>(
                            data: detail,
                            maxSimultaneousDrags: _linkSource == null ? 1 : 0,
                            onDragUpdate: _dragScroll,
                            onDragEnd: (_) => _stopDragScroll(),
                            feedback: Material(
                              elevation: 6,
                              child: SizedBox(
                                width: 480,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(detail['text'] as String),
                                ),
                              ),
                            ),
                            child: Tooltip(
                              message: 'Drag to move detail',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: SizedBox(
                                  key: ValueKey('detail-drag-${detail['id']}'),
                                  width: 32,
                                  height: 48,
                                  child: Icon(
                                    Icons.drag_indicator,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(detail['text'] as String),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit detail',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _linkSource != null
                                ? null
                                : () => _editFields('Project detail', detail, {
                                    'text': 'Detail sentence (exact wording)',
                                  }),
                          ),
                          IconButton(
                            tooltip: 'Remove detail',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _linkSource != null
                                ? null
                                : () => _removeLinkedItem(
                                    details,
                                    detail,
                                    details.cast<Map>(),
                                    project: true,
                                  ),
                          ),
                        ],
                      ),
                      kind: 'detail',
                    ),
                    key: ValueKey('detail-drop-${detail['id']}'),
                  ),
                _detailTarget(
                  project,
                  details.length,
                  const SizedBox(height: 24),
                  key: ValueKey('detail-end-${project['id']}'),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add detail sentence'),
            onPressed: _linkSource != null
                ? null
                : () async {
                    final value = await showDialog<Map<String, String>>(
                      context: context,
                      builder: (_) => const _WordingDialog(
                        title: 'Add project detail',
                        target: {'text': ''},
                        labels: {'text': 'Detail sentence (exact wording)'},
                      ),
                    );
                    if (value != null) {
                      _change(() {
                        project['details'] = details;
                        details.add({'id': const Uuid().v7(), ...value});
                      });
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _entry(String section, Map entry, int index) {
    final list = _data![section] as List;
    final title = switch (section) {
      'personal_context' => entry['topic'] as String,
      'skills' => entry['name'] as String,
      'experience' => entry['employer'] as String,
      'projects' => entry['name'] as String,
      'patents' => entry['text'] as String,
      _ => entry['heading'] as String,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (section == 'projects' && entry['stack'] != '')
                            TextSpan(text: ' · ${entry['stack']}'),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Move entry up',
                  onPressed: index == 0
                      ? null
                      : () => _change(() {
                          list.removeAt(index);
                          list.insert(index - 1, entry);
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Move entry down',
                  onPressed: index == list.length - 1
                      ? null
                      : () => _change(() {
                          list.removeAt(index);
                          list.insert(index + 1, entry);
                        }),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  tooltip: 'Edit ${_singular(section)}',
                  onPressed: () => _editFields(
                    'Edit ${_singular(section)}',
                    entry,
                    _fields(section),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                Switch(
                  value: entry['enabled'] == true,
                  onChanged: (v) => _change(() {
                    entry['enabled'] = v;
                    if (v && entry.containsKey('verification_status')) {
                      entry['verification_status'] = 'confirmed';
                    }
                  }),
                ),
              ],
            ),
            if (section == 'experience') ...[
              if (entry['location'] != '')
                Text(
                  entry['location'] as String,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              const SizedBox(height: 8),
              _linkedTitles(entry),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final title = await showDialog<Map<String, String>>(
                      context: context,
                      builder: (_) => const _WordingDialog(
                        title: 'Add title',
                        target: {'title': '', 'dates': ''},
                        labels: {
                          'title': 'Exact job title',
                          'dates': 'Date range',
                        },
                      ),
                    );
                    if (title != null) {
                      _change(
                        () => (entry['titles'] as List).add({
                          ...title,
                          'achievements': <dynamic>[],
                        }),
                      );
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add title'),
                ),
              ),
            ],
            if (section == 'projects') ...[
              if (entry['dates'] != '')
                Text(
                  entry['dates'] as String,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              if (entry['url'] != '') SelectableText(entry['url'] as String),
              const SizedBox(height: 8),
              const Text(
                'Always-included summary',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(entry['description'] as String),
              _projectDetails(entry),
            ],
            if (section == 'skills') ...[
              if (entry['proficiency'] != '')
                Text(entry['proficiency'] as String),
              if (entry['notes'] != '')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(entry['notes'] as String),
                ),
            ],
            if (section == 'education') Text(entry['details'] as String),
            if (section == 'personal_context') Text(entry['text'] as String),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry['enabled'] == true
                        ? (section == 'experience' ||
                                  section == 'skills' ||
                                  section == 'personal_context'
                              ? 'Available for AI selection'
                              : 'Included in resumes')
                        : (entry['verification_status'] == 'pending'
                              ? 'Matching context needs review. Enabling and saving confirms this wording.'
                              : 'Matching only; excluded from applications'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => _change(() {
                    if (identical(_linkOwner, entry)) {
                      _linkSource = null;
                      _linkOwner = null;
                    }
                    list.removeAt(index);
                  }),
                  child: const Text('Remove entry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DependencyConnections extends SingleChildRenderObjectWidget {
  const _DependencyConnections({
    required this.anchors,
    required this.links,
    required this.activeSource,
    required this.color,
    required super.child,
  });
  final Map<String, GlobalKey> anchors;
  final List<(String, String)> links;
  final String? activeSource;
  final Color color;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDependencyConnections(anchors, links, activeSource, color);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDependencyConnections renderObject,
  ) {
    renderObject
      ..anchors = anchors
      ..links = links
      ..activeSource = activeSource
      ..color = color
      ..markNeedsPaint();
  }
}

class _RenderDependencyConnections extends RenderProxyBox {
  _RenderDependencyConnections(
    this.anchors,
    this.links,
    this.activeSource,
    this.color,
  );
  Map<String, GlobalKey> anchors;
  List<(String, String)> links;
  String? activeSource;
  Color color;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    for (final (index, link) in links.indexed) {
      final from = anchors[link.$1]?.currentContext?.findRenderObject();
      final to = anchors[link.$2]?.currentContext?.findRenderObject();
      if (from is! RenderBox ||
          to is! RenderBox ||
          !from.attached ||
          !to.attached ||
          !from.hasSize ||
          !to.hasSize) {
        continue;
      }
      final start =
          from.localToGlobal(Offset(0, from.size.height / 2), ancestor: this) +
          offset;
      final end =
          to.localToGlobal(Offset(0, to.size.height / 2), ancestor: this) +
          offset;
      final lane = start.dx - 26 - (index % 5) * 5;
      final direction = end.dy >= start.dy ? 1.0 : -1.0;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(lane + 6, start.dy)
        ..quadraticBezierTo(lane, start.dy, lane, start.dy + 6 * direction)
        ..lineTo(lane, end.dy - 6 * direction)
        ..quadraticBezierTo(lane, end.dy, lane + 6, end.dy)
        ..lineTo(end.dx - 2, end.dy);
      final active = activeSource == link.$1;
      final paint = Paint()
        ..color = color.withValues(
          alpha: activeSource == null || active ? 0.85 : 0.2,
        )
        ..strokeWidth = active ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;
      context.canvas.drawPath(path, paint);
      context.canvas.drawPath(
        Path()
          ..moveTo(end.dx - 8, end.dy - 4)
          ..lineTo(end.dx - 2, end.dy)
          ..lineTo(end.dx - 8, end.dy + 4),
        paint,
      );
      context.canvas.drawCircle(start, 2, Paint()..color = paint.color);
    }
  }
}

class _AchievementDrag {
  const _AchievementDrag(this.employment, this.title, this.achievement);
  final Map employment, title, achievement;
}

class _WordingDialog extends StatefulWidget {
  const _WordingDialog({
    required this.title,
    required this.target,
    required this.labels,
    this.achievementOptions = false,
  });
  final String title;
  final Map target;
  final Map<String, String> labels;
  final bool achievementOptions;
  @override
  State<_WordingDialog> createState() => _WordingDialogState();
}

class _WordingDialogState extends State<_WordingDialog> {
  late bool requiredAchievement = widget.target['required'] == true;
  String? pointsError;
  late final controllers = {
    for (final key in widget.labels.keys)
      key: TextEditingController(text: widget.target[key]?.toString() ?? ''),
    if (widget.achievementOptions)
      'priority': TextEditingController(
        text: '${widget.target['priority'] ?? 0}',
      ),
  };
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in widget.labels.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: controllers[field.key],
                  decoration: InputDecoration(
                    labelText: field.value,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  minLines:
                      ['description', 'text', 'details'].contains(field.key)
                      ? 3
                      : 1,
                  maxLines:
                      ['description', 'text', 'details'].contains(field.key)
                      ? 7
                      : 1,
                ),
              ),
            if (widget.achievementOptions) ...[
              TextField(
                controller: controllers['priority'],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Priority points',
                  helperText:
                      '0 to 100. Higher points give this achievement more importance when AI selects relevant evidence.',
                  helperMaxLines: 2,
                  errorText: pointsError,
                  border: const OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required when this job is included'),
                subtitle: const Text(
                  'The resume must include this achievement whenever this employment entry appears.',
                ),
                value: requiredAchievement,
                onChanged: (value) =>
                    setState(() => requiredAchievement = value!),
              ),
            ],
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
          final wording = {
            for (final key in widget.labels.keys)
              key: controllers[key]!.text.trim(),
          };
          if (!widget.achievementOptions) {
            Navigator.pop(context, wording);
            return;
          }
          final points = int.tryParse(controllers['priority']!.text.trim());
          if (points == null || points < 0 || points > 100) {
            setState(() => pointsError = 'Enter a whole number from 0 to 100.');
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            ...wording,
            'priority': points,
            'required': requiredAchievement,
          });
        },
        child: const Text('Use wording'),
      ),
    ],
  );
}
