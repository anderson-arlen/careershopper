import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/protocol/acp_runner.dart';
import 'src/features/ai/acp_permission_prompt.dart';
import 'src/storage/ai_harness_repository.dart';
import 'src/storage/configuration_repository.dart';
import 'src/storage/database.dart';
import 'src/storage/document_template_repository.dart';
import 'src/storage/job_repository.dart';
import 'src/storage/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = CareerShopperDatabase.openDefault();
  final jobs = JobRepository(database);
  final templates = DocumentTemplateRepository(database);
  await templates.ensureDefaults();
  final approvals = AcpPermissionPrompter();
  final harnesses = AiHarnessRepository(
    database,
    runner: StdioAcpAgentRunner(permissionPrompt: approvals.request),
  );
  await harnesses.monitorWorkExpiry();
  runApp(
    CareerShopperApp(
      navigatorKey: approvals.navigatorKey,
      jobs: jobs,
      configuration: ConfigurationRepository(database, jobs),
      profile: ProfileRepository(database),
      templates: templates,
      harnesses: harnesses,
    ),
  );
}
