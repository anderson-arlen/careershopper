import 'dart:async';

import 'package:flutter/material.dart';

import '../shared/window_activity.dart';

import '../../domain/job.dart';
import '../../platform/external_url_launcher.dart';
import '../../storage/job_repository.dart';
import '../../storage/ai_harness_repository.dart';
import '../documents/application_materials_panel.dart';
import '../documents/job_application_actions.dart';
import 'job_chat_panel.dart';
import 'job_notes_section.dart';

class JobBrowser extends StatefulWidget {
  const JobBrowser({
    required this.title,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.jobs,
    this.refreshJobs,
    required this.repository,
    required this.onAddListing,
    required this.onRunAi,
    required this.harnesses,
    required this.onQueueApplication,
    super.key,
  });

  final String title;
  final String emptyTitle;
  final String emptyMessage;
  final Stream<List<InboxJob>> jobs;
  final Future<List<InboxJob>> Function()? refreshJobs;
  final JobStore repository;
  final VoidCallback onAddListing;
  final Future<void> Function(InboxJob job) onRunAi;
  final AiHarnessStore harnesses;
  final Future<void> Function(InboxJob job) onQueueApplication;

  @override
  State<JobBrowser> createState() => _JobBrowserState();
}

class _JobBrowserState extends State<JobBrowser> {
  final _search = TextEditingController();
  String? _selectedJobId;
  int _selectedIndex = 0;
  List<InboxJob>? _visibleJobs;
  Listenable? _activity;
  Timer? _refreshTimer;
  int _activityVersion = 0;
  bool _refreshing = false, _protected = false;
  static const _idleInterval = Duration(minutes: 3);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activity = WindowActivity.of(context);
    if (_activity != activity) {
      _activity?.removeListener(_recordActivity);
      _activity = activity;
      _activity?.addListener(_recordActivity);
    }
    _recordActivity();
  }

  void _recordActivity() {
    _activityVersion++;
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (widget.refreshJobs == null) return;
    _refreshTimer = Timer(_idleInterval, () async {
      if (!_protected && ModalRoute.of(context)?.isCurrent != false) {
        await _refresh();
      }
      if (mounted) _scheduleRefresh();
    });
  }

  Future<void> _refresh({bool manual = false}) async {
    if (_refreshing || _protected || widget.refreshJobs == null) return;
    final version = _activityVersion;
    setState(() => _refreshing = true);
    try {
      final jobs = await widget.refreshJobs!();
      if (mounted && !_protected && (manual || version == _activityVersion)) {
        setState(() => _visibleJobs = jobs);
      }
    } on Object catch (error) {
      if (mounted && manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh inbox: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _afterAction(String id) async {
    if (widget.refreshJobs == null) return;
    final latest = await widget.refreshJobs!();
    if (!mounted || _visibleJobs == null) return;
    final updated = latest.where((job) => job.id == id).firstOrNull;
    setState(() {
      // Apply only the user's action; unrelated arrivals and reordering wait.
      _visibleJobs = [
        for (final job in _visibleJobs!)
          if (job.id != id) job else ?updated,
      ];
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _refreshTimer?.cancel();
    _activity?.removeListener(_recordActivity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InboxJob>>(
      stream: widget.jobs,
      builder: (context, snapshot) {
        if (snapshot.hasError && _visibleJobs == null) {
          return _ErrorState(error: snapshot.error);
        }
        if (!snapshot.hasData && _visibleJobs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final availableJobs = widget.refreshJobs == null
            ? snapshot.data!
            : (_visibleJobs ??= snapshot.data!);

        final jobs = searchJobsByText(
          availableJobs,
          _search.text,
        ).map((match) => match.job).toList(growable: false);
        final retainedIndex = jobs.indexWhere(
          (job) => job.id == _selectedJobId,
        );
        _selectedIndex = jobs.isEmpty
            ? 0
            : retainedIndex < 0
            ? _selectedIndex.clamp(0, jobs.length - 1)
            : retainedIndex;
        final selected = jobs.isEmpty ? null : jobs[_selectedIndex];
        _selectedJobId = selected?.id;
        return Column(
          children: [
            _Toolbar(
              title: widget.title,
              count: jobs.length,
              onAddListing: widget.onAddListing,
              onRefresh: widget.refreshJobs == null
                  ? null
                  : () => _refresh(manual: true),
              refreshing: _refreshing,
              protected: _protected,
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 390,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            key: const ValueKey('job-list-search'),
                            controller: _search,
                            enabled: !_protected,
                            decoration: InputDecoration(
                              hintText: 'Search jobs',
                              helperText: 'Title, description, or employer',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: _protected
                                          ? null
                                          : () => setState(() {
                                              _search.clear();
                                              _selectedIndex = 0;
                                            }),
                                      icon: const Icon(Icons.clear),
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) =>
                                setState(() => _selectedIndex = 0),
                          ),
                        ),
                        Expanded(
                          child: _JobList(
                            jobs: jobs,
                            selectedJobId: selected?.id,
                            onSelected: (id) => setState(() {
                              _selectedJobId = id;
                              _protected = false;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? _EmptyState(
                            title: _search.text.trim().isEmpty
                                ? widget.emptyTitle
                                : 'No matching jobs',
                            message: _search.text.trim().isEmpty
                                ? widget.emptyMessage
                                : 'Try another search or clear it to show all jobs in this view.',
                          )
                        : _JobDetail(
                            key: ValueKey(selected.id),
                            job: selected,
                            repository: widget.repository,
                            onRunAi: (job) async {
                              await widget.onRunAi(job);
                              await _afterAction(job.id);
                            },
                            harnesses: widget.harnesses,
                            onQueueApplication: (job) async {
                              await widget.onQueueApplication(job);
                              await _afterAction(job.id);
                            },
                            onChanged: () => _afterAction(selected.id),
                            onProtectedChanged: (value) {
                              if (_protected != value) {
                                setState(() => _protected = value);
                              }
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.title,
    required this.count,
    required this.onAddListing,
    this.onRefresh,
    this.refreshing = false,
    this.protected = false,
  });

  final String title;
  final int count;
  final VoidCallback onAddListing;
  final VoidCallback? onRefresh;
  final bool refreshing, protected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(width: 10),
          Badge(label: Text('$count')),
          if (onRefresh != null) ...[
            Tooltip(
              message: protected
                  ? 'Save or revert document edits before refreshing'
                  : 'Refresh inbox',
              child: OutlinedButton.icon(
                onPressed: refreshing || protected ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(refreshing ? 'Refreshing…' : 'Refresh'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.tune),
            label: const Text('Filters'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onAddListing,
            icon: const Icon(Icons.add_link),
            label: const Text('Add listing'),
          ),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.selectedJobId,
    required this.onSelected,
  });

  final List<InboxJob> jobs;
  final String? selectedJobId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: jobs.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final selected = job.id == selectedJobId;
        return Material(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(job.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      _EmployerLogo(job: job),
                      const SizedBox(height: 8),
                      _ScoreBadge(score: job.overallScore),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          job.employerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (job.location.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            job.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (job.aiError != null)
                              Chip(
                                avatar: Icon(
                                  Icons.error_outline,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                                label: const Text('AI failed · action needed'),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.errorContainer,
                                labelStyle: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            Chip(
                              label: Text(_jobStatusLabel(job)),
                              visualDensity: VisualDensity.compact,
                            ),
                            if (job.applicationOutcome !=
                                ApplicationOutcome.active)
                              Chip(
                                label: Text(
                                  _applicationOutcomeLabel(
                                    job.applicationOutcome,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmployerLogo extends StatelessWidget {
  const _EmployerLogo({required this.job});
  final InboxJob job;
  @override
  Widget build(BuildContext context) {
    final words = job.employerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    final initials = words
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
    Widget fallback() => Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
    return Semantics(
      label: '${job.employerName} logo',
      image: true,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: job.employerLogoPng == null
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: job.employerLogoPng == null
            ? fallback()
            : Padding(
                padding: const EdgeInsets.all(3),
                child: Image.memory(
                  job.employerLogoPng!,
                  fit: BoxFit.contain,
                  cacheWidth: 128,
                  errorBuilder: (_, error, stackTrace) => fallback(),
                ),
              ),
      ),
    );
  }
}

String _applicationStatusLabel(ApplicationStatus status) => switch (status) {
  ApplicationStatus.unknown => 'Stage not recorded',
  ApplicationStatus.notApplied => 'Not applied',
  ApplicationStatus.readyToApply => 'Ready to apply',
  ApplicationStatus.applied => 'Applied',
  ApplicationStatus.interviewing => 'Interviewing',
  ApplicationStatus.offer => 'Offer',
  ApplicationStatus.hired => 'Hired',
};

String _applicationOutcomeLabel(ApplicationOutcome outcome) =>
    switch (outcome) {
      ApplicationOutcome.active => 'Active',
      ApplicationOutcome.expired => 'Expired',
      ApplicationOutcome.rejected => 'Rejected by employer',
      ApplicationOutcome.withdrawn => 'Withdrawn by me',
    };

bool _hasApplicationProgress(InboxJob job) =>
    job.applicationStatus != ApplicationStatus.notApplied &&
    job.applicationStatus != ApplicationStatus.readyToApply;

String _jobStatusLabel(InboxJob job) {
  if (_hasApplicationProgress(job)) {
    return _applicationStatusLabel(job.applicationStatus);
  }
  if (job.readyToApply) return 'Ready to apply';
  if (job.reviewState == ReviewState.approved) return 'Approved';
  if (job.applicationStatus == ApplicationStatus.readyToApply) {
    return 'Ready to apply';
  }
  return switch (job.reviewState) {
    ReviewState.pendingEvaluation => 'Awaiting AI',
    ReviewState.inbox => 'Inbox',
    ReviewState.hiddenBySearch => 'Outside search',
    ReviewState.hiddenLowScore => 'Below threshold',
    ReviewState.approved => 'Approved',
    ReviewState.discarded => 'Discarded',
  };
}

class _ApplicationStatusControl extends StatefulWidget {
  const _ApplicationStatusControl({
    super.key,
    required this.job,
    required this.repository,
    required this.onChanged,
  });
  final InboxJob job;
  final JobStore repository;
  final Future<void> Function() onChanged;
  @override
  State<_ApplicationStatusControl> createState() =>
      _ApplicationStatusControlState();
}

class _ApplicationStatusControlState extends State<_ApplicationStatusControl> {
  bool _saving = false;
  Future<void> _set(ApplicationStatus value) async {
    if (_saving || value == widget.job.applicationStatus) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setApplicationStatus(
        widget.job.id,
        value,
        actor: 'user',
        origin: 'desktop_ui',
      );
      await widget.onChanged();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update application status: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setOutcome(ApplicationOutcome value) async {
    if (_saving || value == widget.job.applicationOutcome) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setApplicationOutcome(
        widget.job.id,
        value,
        actor: 'user',
        origin: 'desktop_ui',
      );
      await widget.onChanged();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update application outcome: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      PopupMenuButton<Object>(
        tooltip: 'Change application stage',
        enabled: !_saving,
        initialValue:
            widget.job.reviewState == ReviewState.approved &&
                widget.job.applicationStatus == ApplicationStatus.readyToApply
            ? ApplicationStatus.notApplied
            : widget.job.applicationStatus,
        onSelected: (value) => switch (value) {
          ApplicationStatus status => _set(status),
          ApplicationOutcome outcome => _setOutcome(outcome),
          _ => Future<void>.value(),
        },
        itemBuilder: (context) => [
          for (final status in ApplicationStatus.values)
            if (status != ApplicationStatus.readyToApply ||
                widget.job.reviewState != ReviewState.approved)
              PopupMenuItem(
                value: status,
                child: Text(
                  status == ApplicationStatus.notApplied &&
                          widget.job.reviewState == ReviewState.approved
                      ? 'Approved'
                      : _applicationStatusLabel(status),
                ),
              ),
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(
            enabled: false,
            child: Text('Application outcome'),
          ),
          for (final outcome in ApplicationOutcome.values)
            CheckedPopupMenuItem<Object>(
              value: outcome,
              checked: widget.job.applicationOutcome == outcome,
              child: Text(_applicationOutcomeLabel(outcome)),
            ),
        ],
        child: Chip(
          avatar: const Icon(Icons.assignment_outlined, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stage: ${_jobStatusLabel(widget.job)}'),
              const SizedBox(width: 8),
              if (_saving)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
          shape: const StadiumBorder(),
        ),
      ),
    ],
  );
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final color = switch (score) {
      null => Theme.of(context).colorScheme.outline,
      >= 80 => const Color(0xff2d6a4f),
      >= 70 => const Color(0xff52796f),
      _ => const Color(0xff9c6644),
    };
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        score?.toString() ?? '—',
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _JobDetail extends StatefulWidget {
  const _JobDetail({
    super.key,
    required this.job,
    required this.repository,
    required this.onRunAi,
    required this.harnesses,
    required this.onQueueApplication,
    required this.onChanged,
    required this.onProtectedChanged,
  });

  final InboxJob job;
  final Future<void> Function() onChanged;
  final ValueChanged<bool> onProtectedChanged;
  final JobStore repository;
  final Future<void> Function(InboxJob job) onRunAi;
  final AiHarnessStore harnesses;
  final Future<void> Function(InboxJob job) onQueueApplication;

  @override
  State<_JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<_JobDetail> {
  final _tabs = GlobalKey<_JobDetailTabsState>();
  bool _dirty = false, _applying = false;
  InboxJob get job => widget.job;
  JobStore get repository => widget.repository;
  AiHarnessStore get harnesses => widget.harnesses;
  Future<void> Function(InboxJob) get onRunAi => widget.onRunAi;
  Future<void> Function(InboxJob) get onQueueApplication =>
      widget.onQueueApplication;

  @override
  void didUpdateWidget(covariant _JobDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.id != job.id) {
      _dirty = false;
      _applying = false;
    }
  }

  Future<void> _openListing(BuildContext context) async {
    final url = job.applicationUrl;
    if (url == null) return;
    try {
      await openExternalUrl(url);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the listing: $error')),
      );
    }
  }

  Future<void> _openChat() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      child: SizedBox(
        width: 640,
        height: double.infinity,
        child: JobChatPanel(job: job, harnesses: harnesses),
      ),
    ),
  );

  Future<void> _blockEmployer(BuildContext context) async {
    if (job.employerId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${job.employerName}?'),
        content: const Text(
          'Existing listings will leave the Inbox, and future listings from this employer will skip AI evaluation. History is retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block employer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.setEmployerBlocked(
      job.employerId!,
      blocked: true,
      actor: 'user',
      origin: 'desktop_ui',
    );
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(32, 28, 44, 48),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              job.employerName,
                              job.location,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _ScoreBadge(score: job.overallScore),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _ApplicationStatusControl(
                          key: ValueKey(job.id),
                          job: job,
                          repository: repository,
                          onChanged: widget.onChanged,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _openChat,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Chat about this job'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (job.aiError != null) ...[
                  Card.filled(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text(
                        'AI work failed. Your input is needed.',
                      ),
                      subtitle: Text(job.aiError!),
                      trailing: FilledButton.icon(
                        onPressed: () => job.reviewState == ReviewState.approved
                            ? onQueueApplication(job)
                            : onRunAi(job),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry AI'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                JobApplicationActions(
                  key: ValueKey('apply-${job.id}'),
                  job: job,
                  harnesses: harnesses,
                  repository: repository,
                  onChanged: widget.onChanged,
                  dirty: _dirty,
                  onApprove:
                      !_hasApplicationProgress(job) &&
                          job.reviewState != ReviewState.approved &&
                          job.availability != JobAvailability.closed &&
                          job.applicationOutcome == ApplicationOutcome.active
                      ? () => onQueueApplication(job)
                      : null,
                  onBusyChanged: (value) {
                    setState(() => _applying = value);
                    widget.onProtectedChanged(_dirty || _applying);
                  },
                  secondaryActions: [
                    if (job.reviewState == ReviewState.pendingEvaluation)
                      FilledButton.icon(
                        onPressed: () => onRunAi(job),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Run with AI'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await repository.setReviewState(
                          job.id,
                          ReviewState.discarded,
                          actor: 'user',
                          origin: 'desktop_ui',
                        );
                        await widget.onChanged();
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Discard'),
                    ),
                    if (job.applicationUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => _openListing(context),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open listing in browser'),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'More job actions',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'check_availability' ||
                            value == 'clear_availability_block') {
                          try {
                            final message = value == 'check_availability'
                                ? (await repository.checkAvailability(
                                    job.id,
                                  )).detail
                                : await repository
                                      .clearAvailabilityBlock(job.id)
                                      .then(
                                        (_) =>
                                            'Listing check block cleared. No request sent.',
                                      );
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            }
                            await widget.onChanged();
                          } on Object catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        }
                        if (value == 'reanalyze') await onRunAi(job);
                        if (value == 'block' && context.mounted) {
                          await _blockEmployer(context);
                        }
                      },
                      itemBuilder: (_) => [
                        if (job.applicationUrl != null) ...[
                          const PopupMenuItem(
                            value: 'check_availability',
                            child: Text('Check listing availability'),
                          ),
                          const PopupMenuItem(
                            value: 'clear_availability_block',
                            child: Text('Clear listing check block'),
                          ),
                        ],
                        if (job.reviewState != ReviewState.pendingEvaluation &&
                            job.applicationUrl != null)
                          const PopupMenuItem(
                            value: 'reanalyze',
                            child: Text('Refresh & reanalyze'),
                          ),
                        PopupMenuItem(
                          value: 'block',
                          enabled: job.employerId != null,
                          child: const Text('Block employer'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _JobDetailTabs(
                  key: _tabs,
                  documents: job.reviewState == ReviewState.approved
                      ? ApplicationMaterialsPanel(
                          key: ValueKey('materials-${job.id}'),
                          job: job,
                          harnesses: harnesses,
                          applying: _applying,
                          onDirtyChanged: (value) {
                            setState(() => _dirty = value);
                            widget.onProtectedChanged(_dirty || _applying);
                          },
                        )
                      : const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Approve this job to queue AI generation of the Markdown resume and cover letter.',
                          ),
                        ),
                  details: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      JobNotesSection(jobId: job.id, jobs: repository),
                      if (job.overallScore != null) ...[
                        const SizedBox(height: 30),
                        Text(
                          'Evaluation',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          children: [
                            Text('Fit ${job.personalFitScore ?? '—'}'),
                            Text(
                              'Attainability ${job.attainabilityScore ?? '—'}',
                            ),
                          ],
                        ),
                        if (job.evaluationSummary case final summary?) ...[
                          const SizedBox(height: 12),
                          Text(summary),
                        ],
                      ],
                      const SizedBox(height: 30),
                      Text(
                        'Job description',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        job.description.isEmpty
                            ? 'Structured details have not been imported yet.'
                            : job.description,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobDetailTabs extends StatefulWidget {
  const _JobDetailTabs({
    super.key,
    required this.details,
    required this.documents,
  });
  final Widget details;
  final Widget documents;
  @override
  State<_JobDetailTabs> createState() => _JobDetailTabsState();
}

class _JobDetailTabsState extends State<_JobDetailTabs>
    with SingleTickerProviderStateMixin {
  late final controller = TabController(length: 2, vsync: this);
  void showDocuments() => controller.animateTo(1);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        TabBar(
          controller: controller,
          tabs: const [
            Tab(text: 'Job details'),
            Tab(text: 'Application documents'),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            children: [
              Offstage(offstage: controller.index != 0, child: widget.details),
              Offstage(
                offstage: controller.index != 1,
                child: widget.documents,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('CareerShopper could not load its local database.\n$error'),
      ),
    );
  }
}
