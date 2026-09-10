import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'features/shared/window_activity.dart';
import 'storage/ai_harness_repository.dart';
import 'storage/configuration_repository.dart';
import 'storage/document_template_repository.dart';
import 'storage/job_repository.dart';
import 'storage/profile_repository.dart';

class CareerShopperApp extends StatelessWidget {
  const CareerShopperApp({
    required this.jobs,
    required this.configuration,
    required this.profile,
    required this.templates,
    required this.harnesses,
    this.navigatorKey,
    super.key,
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final JobStore jobs;
  final ConfigurationStore configuration;
  final ProfileStore profile;
  final DocumentTemplateStore templates;
  final AiHarnessStore harnesses;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff335c67);
    return MaterialApp(
      title: 'CareerShopper',
      navigatorKey: navigatorKey,
      builder: (context, child) => WindowActivity(child: child!),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff7f8f6),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        jobs: jobs,
        configuration: configuration,
        profile: profile,
        templates: templates,
        harnesses: harnesses,
      ),
    );
  }
}
