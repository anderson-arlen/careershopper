import 'dart:io';

import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/profile_repository.dart';
import 'package:careershopper/src/storage/resume_content_repository.dart';

/// Run only for an explicit user request to migrate archived skills.
Future<void> main() async {
  final database = CareerShopperDatabase.openDefault();
  try {
    final count = await ResumeContentRepository(
      ProfileRepository(database),
    ).importLegacySkills(actor: 'user_requested_skill_import');
    stdout.writeln('Imported $count confirmed skills into Resume content.');
  } finally {
    await database.close();
  }
}
