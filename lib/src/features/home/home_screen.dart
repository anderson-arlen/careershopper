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
  inbox,
  allJobs,
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
    super.key,
  });

  final JobStore jobs;
  final ConfigurationStore configuration;
  final ProfileStore profile;
  final DocumentTemplateStore templates;
  final AiHarnessStore harnesses;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeDestination _destination = HomeDestination.inbox;
  late final _inboxCounts = widget.jobs
      .watchInbox()
      .map((jobs) => jobs.length)
      .distinct();

  Future<void> _addListing() async {
    final jobId = await showDialog<String>(
      context: context,
      builder: (context) => AddListingDialog(repository: widget.jobs),
    );
    if (!mounted || jobId == null) return;
    setState(() => _destination = HomeDestination.allJobs);
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
                    icon: inboxIcon(Icons.inbox_outlined),
                    selectedIcon: inboxIcon(Icons.inbox),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Inbox'),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          Text('$count', key: const ValueKey('inbox-count')),
                        ],
                      ],
                    ),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.work_outline),
                    selectedIcon: Icon(Icons.work),
                    label: Text('All jobs'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.business_outlined),
                    selectedIcon: Icon(Icons.business),
                    label: Text(extended ? 'Blocked employers' : 'Blocked'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.badge_outlined),
                    selectedIcon: Icon(Icons.badge),
                    label: Text('Profile'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.description_outlined),
                    selectedIcon: Icon(Icons.description),
                    label: Text('Documents'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.manage_search),
                    selectedIcon: Icon(Icons.manage_search),
                    label: Text('Searches'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: Text('Sources'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.smart_toy_outlined),
                    selectedIcon: Icon(Icons.smart_toy),
                    label: Text('AI'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.query_stats_outlined),
                    selectedIcon: Icon(Icons.query_stats),
                    label: Text('Statistics'),
                  ),
                ],
                onDestinationSelected: (index) {
                  setState(() => _destination = HomeDestination.values[index]);
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
      HomeDestination.inbox => JobBrowser(
        key: const ValueKey('inbox-browser'),
        title: 'Inbox',
        emptyTitle: 'Nothing needs your attention',
        emptyMessage:
            'Jobs needing review, ready to apply, or needing an AI retry appear here, ordered by best fit.',
        jobs: widget.jobs.watchInbox(),
        refreshJobs: () => widget.jobs.watchInbox().first,
        repository: widget.jobs,
        harnesses: widget.harnesses,
        onQueueApplication: (job) => _queueApplication(job.id),
        onAddListing: _addListing,
        onRunAi: (job) => _runAi(job.id, showActivity: job.aiError == null),
      ),
      HomeDestination.allJobs => JobBrowser(
        key: const ValueKey('all-jobs-browser'),
        title: 'All jobs',
        emptyTitle: 'No listings encountered',
        emptyMessage:
            'Add a URL or configure a saved search to start building local history.',
        jobs: widget.jobs.watchAllJobs(),
        repository: widget.jobs,
        harnesses: widget.harnesses,
        onQueueApplication: (job) => _queueApplication(job.id),
        onAddListing: _addListing,
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
