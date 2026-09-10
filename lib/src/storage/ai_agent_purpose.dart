import 'package:drift/drift.dart';

import 'database.dart';

enum AiAgentPurpose {
  jobMatching('Job matching'),
  applicationWriting('Application writing');

  const AiAgentPurpose(this.label);
  final String label;

  Expression<bool> column(AiHarnessProfiles table) => switch (this) {
    jobMatching => table.isJobMatchingDefault,
    applicationWriting => table.isApplicationWritingDefault,
  };
}

Future<AiHarnessProfileRow?> resolveAiProfile(
  CareerShopperDatabase database, {
  AiAgentPurpose? purpose,
}) {
  final table = database.aiHarnessProfiles;
  final preferred = purpose?.column(table) ?? table.isDefault;
  return (database.select(table)
        ..where((row) => preferred.equals(true) | row.isDefault.equals(true))
        ..orderBy([(row) => OrderingTerm.desc(preferred)])
        ..limit(1))
      .getSingleOrNull();
}
