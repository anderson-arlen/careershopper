import '../../storage/interview_repository.dart';
import 'package:flutter/material.dart';

import '../../storage/ai_harness_repository.dart';
import '../../storage/configuration_repository.dart';
import '../../storage/document_template_repository.dart';
import '../../storage/job_repository.dart';
import '../../storage/profile_repository.dart';
import '../inbox/add_listing_dialog.dart';
import '../inbox/job_browser.dart';
import '../ai/ai_page.dart';
import '../documents/document_templates_page.dart';
import '../profile/profile_page.dart';
import '../searches/saved_searches_page.dart';
import '../sources/sources_page.dart';
import '../statistics/statistics_page.dart';
import '../employers/blocked_employers_page.dart';

enum HomeDestination {
  jobs,
  interviews,
  blockedEmployers,
  profile,
  documents,
  searches,
  sources,
  ai,
  statistics,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.jobs,
    required this.configuration,
    required this.profile,
    required this.templates,
    required this.harnesses,
    this.interviews,
    this.onPrepareInterviews,
    super.key,
  });

  final JobStore jobs;
  final ConfigurationStore configuration;
  final ProfileStore profile;
  final DocumentTemplateStore templates;
  final AiHarnessStore harnesses;
  final InterviewRepository? interviews;
  final Future<void> Function(String)? onPrepareInterviews;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeDestination _destination = HomeDestination.jobs;
  bool _allJobs = false;
  int _jobsRefreshRequest = 0;
  late final _inboxCounts = widget.jobs.watchJobCount(view: 'inbox').distinct();

  Future<void> _addListing() async {
    final jobId = await showDialog<String>(
      context: context,
      builder: (context) => AddListingDialog(repository: widget.jobs),
    );
    if (!mounted || jobId == null) return;
    setState(() => _destination = HomeDestination.jobs);
    await _runAi(jobId);
  }

  Future<void> _runAi(String jobId, {bool showActivity = true}) async {
    try {
      final result = await widget.harnesses.dispatchManualImport(jobId);
      if (!mounted) return;
      if (showActivity) setState(() => _destination = HomeDestination.ai);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.launched
                ? '${result.profileName} started. The listing will update when import and evaluation finish.'
                : '${result.profileName} is already processing this listing.',
          ),
        ),
      );
    } on NoDefaultAiHarnessException {
      if (!mounted) return;
      setState(() => _destination = HomeDestination.ai);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a default agent from the ACP Registry. Your listing is saved and can be run afterward.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the ACP agent: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          StreamBuilder<int>(
            stream: _inboxCounts,
            builder: (context, snapshot) {
              final count = snapshot.data;
              final extended = MediaQuery.sizeOf(context).width >= 1180;
              Widget inboxIcon(IconData icon) => extended || count == null
                  ? Icon(icon)
                  : Badge(label: Text('$count'), child: Icon(icon));
              // The rail centers destinations independently. Equal label widths
              // keep every icon and label aligned, including the Jobs action.
              Widget navigationLabel(Widget child) =>
                  extended ? SizedBox(width: 168, child: child) : child;
              return NavigationRail(
                selectedIndex: _destination.index,
                extended: MediaQuery.sizeOf(context).width >= 1180,
                labelType: MediaQuery.sizeOf(context).width >= 1180
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.selected,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton.filled(
                    tooltip: 'Add listing',
                    onPressed: _addListing,
                    icon: const Icon(Icons.add_link),
                  ),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: inboxIcon(Icons.work_outline),
                    selectedIcon: inboxIcon(Icons.work),
                    label: navigationLabel(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Jobs'),
                          if (count != null) ...[
                            const SizedBox(width: 8),
                            Text('$count', key: const ValueKey('inbox-count')),
                          ],
                          if (extended &&
                              _destination == HomeDestination.jobs) ...[
                            const Spacer(),
                            const Tooltip(
                              message: 'Refresh jobs',
                              child: Icon(Icons.refresh, size: 18),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.record_voice_over_outlined),
                    selectedIcon: Icon(Icons.record_voice_over),
                    label: navigationLabel(Text('Interviews')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.business_outlined),
                    selectedIcon: Icon(Icons.business),
                    label: navigationLabel(
                      Text(extended ? 'Blocked employers' : 'Blocked'),
                    ),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.badge_outlined),
                    selectedIcon: Icon(Icons.badge),
                    label: navigationLabel(Text('Profile')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.description_outlined),
                    selectedIcon: Icon(Icons.description),
                    label: navigationLabel(Text('Documents')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.manage_search),
                    selectedIcon: Icon(Icons.manage_search),
                    label: navigationLabel(Text('Searches')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: navigationLabel(Text('Sources')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.smart_toy_outlined),
                    selectedIcon: Icon(Icons.smart_toy),
                    label: navigationLabel(Text('AI')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.query_stats_outlined),
                    selectedIcon: Icon(Icons.query_stats),
                    label: navigationLabel(Text('Statistics')),
                  ),
                ],
                onDestinationSelected: (index) {
                  if (_destination == HomeDestination.jobs &&
                      index == HomeDestination.jobs.index) {
                    setState(() => _jobsRefreshRequest++);
                  } else {
                    setState(
                      () => _destination = HomeDestination.values[index],
                    );
                  }
                },
              );
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    return switch (_destination) {
      HomeDestination.jobs => JobBrowser(
        key: const ValueKey('jobs-browser'),
        refreshRequest: _jobsRefreshRequest,
        view: _allJobs ? 'all' : 'inbox',
        title: 'Jobs',
        viewSelector: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Inbox')),
            ButtonSegment(value: true, label: Text('All jobs')),
          ],
          selected: {_allJobs},
          onSelectionChanged: (value) =>
              setState(() => _allJobs = value.single),
        ),
        emptyTitle: _allJobs
            ? 'No listings encountered'
            : 'Nothing needs your attention',
        emptyMessage: _allJobs
            ? 'Add a URL or configure a saved search to start building local history.'
            : 'Jobs needing review, ready to apply, or needing an AI retry appear here, ordered by best fit.',
        jobs: widget.jobs.watchJobs(view: _allJobs ? 'all' : 'inbox'),
        pageJobs: (limit, search, filters) => widget.jobs.watchJobs(
          view: _allJobs ? 'all' : 'inbox',
          limit: limit,
          search: search,
          filters: filters,
        ),
        refreshJobs: () =>
            widget.jobs.watchJobs(view: _allJobs ? 'all' : 'inbox').first,
        repository: widget.jobs,
        interviews: widget.interviews,
        onPrepareInterviews: widget.onPrepareInterviews,
        harnesses: widget.harnesses,
        onQueueApplication: (job) => _queueApplication(job.id),
        onRunAi: (job) => _runAi(job.id, showActivity: job.aiError == null),
      ),
      HomeDestination.interviews => JobBrowser(
        key: const ValueKey('interviews-browser'),
        view: 'interviewing',
        title: 'Interviews',
        openInterviews: true,
        emptyTitle: 'No active interviews',
        emptyMessage:
            'Set a job to Interviewing to research the company and practice here.',
        jobs: widget.jobs.watchJobs(view: 'interviewing'),
        pageJobs: (limit, search, filters) => widget.jobs.watchJobs(
          view: 'interviewing',
          limit: limit,
          search: search,
          filters: filters,
        ),
        repository: widget.jobs,
        interviews: widget.interviews,
        onPrepareInterviews: widget.onPrepareInterviews,
        harnesses: widget.harnesses,
        onQueueApplication: (job) => _queueApplication(job.id),
        onRunAi: (job) => _runAi(job.id, showActivity: job.aiError == null),
      ),
      HomeDestination.blockedEmployers => BlockedEmployersPage(
        jobs: widget.jobs,
      ),
      HomeDestination.profile => ProfilePage(profile: widget.profile),
      HomeDestination.documents => DocumentTemplatesPage(
        templates: widget.templates,
        profile: widget.profile,
      ),
      HomeDestination.searches => SavedSearchesPage(
        configuration: widget.configuration,
        harnesses: widget.harnesses,
      ),
      HomeDestination.sources => SourcesPage(
        configuration: widget.configuration,
      ),
      HomeDestination.ai => AiPage(harnesses: widget.harnesses),
      HomeDestination.statistics => StatisticsPage(jobs: widget.jobs),
    };
  }

  Future<void> _queueApplication(String jobId) async {
    try {
      await widget.harnesses.queueApplication(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approved. Generating resume and cover letter drafts.'),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare application: $error')),
      );
    }
  }
}
