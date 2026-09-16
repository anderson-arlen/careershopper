import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/discovery/search_scheduler.dart';
import 'src/protocol/acp_runner.dart';
import 'src/features/ai/acp_permission_prompt.dart';
import 'src/storage/ai_harness_repository.dart';
import 'src/storage/configuration_repository.dart';
import 'src/storage/database.dart';
import 'src/storage/document_template_repository.dart';
import 'src/storage/job_repository.dart';
import 'src/storage/interview_repository.dart';
import 'src/storage/profile_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = CareerShopperDatabase.openDefault();
  final jobs = JobRepository(database);
  final templates = DocumentTemplateRepository(database);
  await templates.ensureDefaults();
  final approvals = AcpPermissionPrompter(
    onPrompt: () async {
      if (defaultTargetPlatform == TargetPlatform.linux) {
        await const MethodChannel(
          'careershopper/window',
        ).invokeMethod<void>('show');
      }
    },
  );
  final harnesses = AiHarnessRepository(
    database,
    runner: StdioAcpAgentRunner(permissionPrompt: approvals.request),
  );
  await harnesses.resumePendingSearchAnalysis();
  unawaited(harnesses.resumeQueuedMaterialGeneration());
  await harnesses.startInterviewPreparationMonitor();
  await harnesses.monitorWorkExpiry();
  final configuration = ConfigurationRepository(database, jobs);
  SearchScheduler(configuration, harnesses).start();
  runApp(
    CareerShopperApp(
      navigatorKey: approvals.navigatorKey,
      jobs: jobs,
      configuration: configuration,
      profile: ProfileRepository(database),
      templates: templates,
      harnesses: harnesses,
      interviews: InterviewRepository(database),
      onPrepareInterviews: (jobId) async {
        await harnesses.queueInterviewPreparation(jobId);
      },
    ),
  );
}
