import 'package:flutter/material.dart';

import '../../domain/job_statistics.dart';
import '../../storage/job_repository.dart';
import 'application_sankey.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.jobs});
  final JobStore jobs;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  StatisticsPeriod _period = StatisticsPeriod.allTime;
  late Stream<JobStatistics> _statistics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _statistics = widget.jobs.watchStatistics(
      changedSince: _period.start(DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Application statistics',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in StatisticsPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _period == period,
                    onSelected: (_) => setState(() {
                      _period = period;
                      _load();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            StreamBuilder<JobStatistics>(
              key: ValueKey(_period),
              stream: _statistics,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Could not load statistics.'),
                      TextButton.icon(
                        onPressed: () => setState(_load),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final stats = snapshot.data;
                if (stats == null) return const CircularProgressIndicator();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 600
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: width,
                              child: _ConversionCard(
                                title: 'Jobs found per application',
                                ratio: stats.jobsFoundPerApplication,
                                icon: Icons.search,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _ConversionCard(
                                title: 'Applications per interview',
                                ratio: stats.applicationsPerInterview,
                                icon: Icons.record_voice_over_outlined,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    if (stats.found == 0) ...[
                      const Text('No jobs changed state in this period.'),
                      const SizedBox(height: 20),
                    ],
                    const _ChartTitle(
                      title: 'Application funnel',
                      explanation:
                          'Dates select jobs by their last state change, using your local calendar. New jobs start at their first-seen date. Listing refreshes and note edits do not count as state changes. Each selected job shows its furthest recorded progress, including after rejection or withdrawal. Each job counts once per stage; later stages include earlier stages, and hired counts as an offer. Hidden and declined listings remain in Jobs found. The funnel shape represents stage order, not proportional counts.',
                    ),
                    const SizedBox(height: 12),
                    Center(
                      key: const ValueKey('application-funnel'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: _ApplicationFunnel(statistics: stats),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const _ChartTitle(
                      title: 'Application flow',
                      explanation:
                          'Dates select jobs by their last state change, using your local calendar. Each selected job enters through its first recorded source and shows its furthest recorded progress. Flow width represents the number of jobs. Clock icons mark states still in progress. Inbox counts jobs ready for your action within the selected period. Other branches show completed outcomes at the furthest recorded stage.',
                    ),
                    const SizedBox(height: 12),
                    ApplicationSankey(
                      key: const ValueKey('application-sankey'),
                      statistics: stats,
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversionCard extends StatelessWidget {
  const _ConversionCard({
    required this.title,
    required this.ratio,
    required this.icon,
  });

  final String title;
  final double? ratio;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = ratio?.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return Card.filled(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 18)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value ?? '—',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle({required this.title, required this.explanation});

  final String title;
  final String explanation;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'About $title',
        icon: const Icon(Icons.info_outline),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(explanation)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ApplicationFunnel extends StatelessWidget {
  const _ApplicationFunnel({required this.statistics});

  final JobStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = [
      ('Jobs found', statistics.found, const Color(0xFFB93846), Colors.white),
      (
        'Applied',
        statistics.applied,
        const Color(0xFFEBA253),
        const Color(0xFF30200F),
      ),
      (
        'Interviewed',
        statistics.interviewed,
        const Color(0xFF39B7A5),
        const Color(0xFF102E28),
      ),
      ('Offers', statistics.offers, const Color(0xFF7252A3), Colors.white),
    ];
    // Fixed stage geometry keeps zero-count stages visible. Counts, rather than
    // segment area, express volume, as in a conventional process funnel.
    return Column(
      children: [
        for (var index = 0; index < stages.length; index++)
          Semantics(
            label: '${stages[index].$1}: ${stages[index].$2}',
            excludeSemantics: true,
            child: ClipPath(
              clipper: _FunnelStageClipper(index),
              child: ColoredBox(
                color: stages[index].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 1 - (index + 1) * 0.2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          children: [
                            Text(
                              '${stages[index].$2}',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                color: stages[index].$4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              stages[index].$1,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: stages[index].$4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FunnelStageClipper extends CustomClipper<Path> {
  const _FunnelStageClipper(this.index);
  final int index;

  @override
  Path getClip(Size size) {
    final topInset = size.width * index * 0.1;
    final bottomInset = size.width * (index + 1) * 0.1;
    return Path()
      ..moveTo(topInset, 0)
      ..lineTo(size.width - topInset, 0)
      ..lineTo(size.width - bottomInset, size.height)
      ..lineTo(bottomInset, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_FunnelStageClipper oldClipper) =>
      oldClipper.index != index;
}
