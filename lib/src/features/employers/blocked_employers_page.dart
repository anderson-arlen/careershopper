import 'package:flutter/material.dart';

import '../../storage/database.dart';
import '../../storage/job_repository.dart';

class BlockedEmployersPage extends StatefulWidget {
  const BlockedEmployersPage({super.key, required this.jobs});

  final JobStore jobs;

  @override
  State<BlockedEmployersPage> createState() => _BlockedEmployersPageState();
}

class _BlockedEmployersPageState extends State<BlockedEmployersPage> {
  late Stream<List<EmployerRow>> _employers;
  final _unblocking = <String>{};

  @override
  void initState() {
    super.initState();
    _employers = widget.jobs.watchBlockedEmployers();
  }

  Future<void> _unblock(EmployerRow employer) async {
    setState(() => _unblocking.add(employer.id));
    try {
      await widget.jobs.setEmployerBlocked(
        employer.id,
        blocked: false,
        actor: 'user',
        origin: 'desktop',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${employer.displayName} unblocked.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unblock employer: $error')),
      );
    } finally {
      if (mounted) setState(() => _unblocking.remove(employer.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Blocked employers',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<List<EmployerRow>>(
              stream: _employers,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Could not load blocked employers.'),
                      TextButton.icon(
                        onPressed: () => setState(
                          () =>
                              _employers = widget.jobs.watchBlockedEmployers(),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final employers = snapshot.data;
                if (employers == null) return const CircularProgressIndicator();
                if (employers.isEmpty) {
                  return const Text('No blocked employers.');
                }
                return ListView.separated(
                  itemCount: employers.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final employer = employers[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.block),
                      title: Text(employer.displayName),
                      subtitle: Text(
                        [
                          if (employer.blockedAt != null)
                            'Blocked ${MaterialLocalizations.of(context).formatFullDate(employer.blockedAt!.toLocal())}',
                          if (employer.blockReason?.trim().isNotEmpty ?? false)
                            employer.blockReason!,
                        ].join('\n'),
                      ),
                      trailing: OutlinedButton(
                        onPressed: _unblocking.contains(employer.id)
                            ? null
                            : () => _unblock(employer),
                        child: Text(
                          _unblocking.contains(employer.id)
                              ? 'Unblocking…'
                              : 'Unblock',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
