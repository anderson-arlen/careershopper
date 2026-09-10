enum StatisticsPeriod {
  today('Today', 'today'),
  thisMonth('This month', 'this_month'),
  thisYear('This year', 'this_year'),
  allTime('All time', 'all_time');

  const StatisticsPeriod(this.label, this.value);
  final String label;
  final String value;

  DateTime? start(DateTime now) => switch (this) {
    today => DateTime(now.year, now.month, now.day),
    thisMonth => DateTime(now.year, now.month),
    thisYear => DateTime(now.year),
    allTime => null,
  };
}

typedef JobFlowNode = ({
  String id,
  String label,
  int count,
  int column,
  bool remainder,
  bool terminal,
});
typedef JobFlowLink = ({String source, String target, int count});

enum JobFlowBranch {
  expired('expired', 'Expired', 'found', 2, optional: true),
  appliedExpired('applied_expired', 'Expired', 'applied', 3, optional: true),
  interviewExpired(
    'interview_expired',
    'Expired',
    'interviewed',
    4,
    optional: true,
  ),
  offerExpired('offer_expired', 'Expired', 'offers', 5, optional: true),
  aiRejected('ai_rejected', 'AI rejected', 'found', 2),
  userRejected('user_rejected', 'User rejected', 'found', 2),
  inbox('inbox', 'Inbox', 'found', 2),
  pendingProcessing(
    'pending_processing',
    'Pending processing',
    'found',
    2,
    optional: true,
  ),
  filteredBySearch(
    'filtered_by_search',
    'Filtered by search',
    'found',
    2,
    optional: true,
  ),
  preApplicationRejected(
    'pre_application_rejected',
    'Employer rejected',
    'found',
    2,
    optional: true,
  ),
  appliedWaiting('applied_waiting', 'Waiting', 'applied', 3),
  appliedRejected('applied_rejected', 'Employer rejected', 'applied', 3),
  appliedWithdrawn(
    'applied_withdrawn',
    'User withdrawn',
    'applied',
    3,
    optional: true,
  ),
  interviewWaiting('interview_waiting', 'Waiting', 'interviewed', 4),
  interviewRejected(
    'interview_rejected',
    'Employer rejected',
    'interviewed',
    4,
  ),
  interviewWithdrawn(
    'interview_withdrawn',
    'User withdrawn',
    'interviewed',
    4,
    optional: true,
  ),
  offerWithdrawn('offer_withdrawn', 'Employer withdrawn', 'offers', 5),
  offerRejected('offer_rejected', 'User rejected', 'offers', 5),
  offerWaiting('offer_waiting', 'Waiting', 'offers', 5),
  hired('hired', 'Accepted offer', 'offers', 5);

  const JobFlowBranch(
    this.id,
    this.label,
    this.parent,
    this.column, {
    this.optional = false,
  });
  final String id;
  final String label;
  final String parent;
  final int column;
  final bool optional;

  bool get terminal => switch (this) {
    inbox ||
    pendingProcessing ||
    appliedWaiting ||
    interviewWaiting ||
    offerWaiting => false,
    _ => true,
  };
}

class JobStatistics {
  const JobStatistics({
    required this.found,
    required this.applied,
    required this.interviewed,
    required this.offers,
    this.sources = const {},
    this.branches = const {},
  });

  final int found;
  final int applied;
  final int interviewed;
  final int offers;
  final Map<String, int> sources;
  final Map<JobFlowBranch, int> branches;

  Map<JobFlowBranch, int> get _flowBranches => branches.isEmpty
      ? {
          JobFlowBranch.inbox: found - applied,
          JobFlowBranch.appliedWaiting: applied - interviewed,
          JobFlowBranch.interviewWaiting: interviewed - offers,
          JobFlowBranch.offerWaiting: offers,
        }
      : branches;

  Map<String, int> get _flowSources =>
      sources.isEmpty ? {'unknown': found} : sources;

  static String sourceLabel(String source) => switch (source) {
    'manual' => 'Manual entry',
    'indeed' => 'Indeed',
    'linkedin' => 'LinkedIn',
    'greenhouse' => 'Greenhouse',
    'lever' => 'Lever',
    'ashby' => 'Ashby',
    'unknown' => 'Unknown source',
    _ => source,
  };

  List<JobFlowNode> get sankeyNodes {
    final nodes = <JobFlowNode>[
      for (final source in _flowSources.entries)
        (
          id: 'source:${source.key}',
          label: sourceLabel(source.key),
          count: source.value,
          column: 0,
          remainder: false,
          terminal: false,
        ),
      (
        id: 'found',
        label: 'Jobs found',
        count: found,
        column: 1,
        remainder: false,
        terminal: false,
      ),
      (
        id: 'applied',
        label: 'Applied',
        count: applied,
        column: 2,
        remainder: false,
        terminal: false,
      ),
      (
        id: 'interviewed',
        label: 'Interviewing',
        count: interviewed,
        column: 3,
        remainder: false,
        terminal: false,
      ),
      (
        id: 'offers',
        label: 'Offer',
        count: offers,
        column: 4,
        remainder: false,
        terminal: false,
      ),
      for (final ending in JobFlowBranch.values)
        if (!ending.optional || (_flowBranches[ending] ?? 0) > 0)
          (
            id: ending.id,
            label: ending.label,
            count: _flowBranches[ending] ?? 0,
            column: ending.column,
            remainder: true,
            terminal: ending.terminal,
          ),
    ];
    return [
      for (var column = 0; column <= 5; column++) ...[
        // The successful final outcome leads even though it is terminal.
        ...nodes.where((node) => node.column == column && node.id == 'hired'),
        for (final terminal in [false, true])
          ...nodes.where(
            (node) =>
                node.column == column &&
                node.terminal == terminal &&
                node.id != 'hired',
          ),
      ],
    ];
  }

  List<JobFlowLink> get sankeyLinks {
    final links = <JobFlowLink>[
      for (final source in _flowSources.entries)
        (source: 'source:${source.key}', target: 'found', count: source.value),
      (source: 'found', target: 'applied', count: applied),
      (source: 'applied', target: 'interviewed', count: interviewed),
      (source: 'interviewed', target: 'offers', count: offers),
      for (final ending in JobFlowBranch.values)
        if (!ending.optional || (_flowBranches[ending] ?? 0) > 0)
          (
            source: ending.parent,
            target: ending.id,
            count: _flowBranches[ending] ?? 0,
          ),
    ];
    // Match ribbon stacking to the target nodes' vertical order.
    return [
      for (final node in sankeyNodes)
        ...links.where((link) => link.target == node.id),
    ];
  }

  Map<String, Object?> sankeyToJson() => {
    'source_attribution': 'first_observed_source',
    'nodes': [
      for (final node in sankeyNodes)
        {
          'id': node.id,
          'label': node.label,
          'count': node.count,
          'column': node.column,
          'remainder': node.remainder,
          'terminal': node.terminal,
        },
    ],
    'links': [
      for (final link in sankeyLinks)
        {'source': link.source, 'target': link.target, 'count': link.count},
    ],
  };

  Map<String, Object?> toJson() => {
    'found': found,
    'applied': applied,
    'interviewed': interviewed,
    'offers': offers,
  };
}
