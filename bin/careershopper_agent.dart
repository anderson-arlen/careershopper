import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/storage/database.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    _printHelp();
    return;
  }

  switch (arguments.first) {
    case 'mcp':
      final database = CareerShopperDatabase.openDefault();
      try {
        await McpServer(database).serve();
      } finally {
        await database.close();
      }
    case 'plugin':
      await _pluginCommand(arguments.skip(1).toList());
    case 'skill':
      await _skillCommand(arguments.skip(1).toList());
    default:
      stderr.writeln('Unknown command: ${arguments.first}');
      _printHelp();
      exitCode = 64;
  }
}

void _printHelp() {
  stdout.writeln(
    '''
CareerShopper agent integration

Usage:
  careershopper-agent mcp
  careershopper-agent plugin path
  careershopper-agent skill path
  careershopper-agent skill install [--agents-dir PATH]
  careershopper-agent skill uninstall [--agents-dir PATH]
'''
        .trim(),
  );
}

Future<void> _pluginCommand(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == 'path') {
    stdout.writeln(_pluginRoot().path);
    return;
  }
  throw const FormatException('Usage: careershopper-agent plugin path');
}

Future<void> _skillCommand(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == 'path') {
    stdout.writeln(p.join(_pluginRoot().path, 'skills', 'careershopper'));
    return;
  }
  if (arguments.isNotEmpty && arguments.first == 'install') {
    final agentsDir = _agentsDirectory(arguments.skip(1).toList());
    await _installSkill(agentsDir);
    return;
  }
  if (arguments.isNotEmpty && arguments.first == 'uninstall') {
    final agentsDir = _agentsDirectory(arguments.skip(1).toList());
    await _uninstallSkill(agentsDir);
    return;
  }
  throw const FormatException(
    'Usage: careershopper-agent skill path|install|uninstall',
  );
}

Directory _pluginRoot() {
  final override = Platform.environment['CAREERSHOPPER_PLUGIN_ROOT'];
  if (override != null && override.isNotEmpty) {
    return Directory(p.normalize(p.absolute(override)));
  }

  final besideExecutable = Directory(
    p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '..')),
  );
  if (File(p.join(besideExecutable.path, 'plugin.json')).existsSync()) {
    return besideExecutable;
  }

  final fromWorkingDirectory = Directory(
    p.join(Directory.current.path, 'agent-plugin'),
  );
  if (File(p.join(fromWorkingDirectory.path, 'plugin.json')).existsSync()) {
    return fromWorkingDirectory;
  }

  throw StateError(
    'Could not locate the CareerShopper Agent Plugin. Set CAREERSHOPPER_PLUGIN_ROOT.',
  );
}

Directory _agentsDirectory(List<String> arguments) {
  if (arguments.isEmpty) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('Cannot determine the user home directory.');
    }
    return Directory(p.join(home, '.agents'));
  }
  if (arguments.length == 2 && arguments.first == '--agents-dir') {
    return Directory(p.normalize(p.absolute(arguments.last)));
  }
  throw const FormatException('Expected optional --agents-dir PATH.');
}

Future<void> _installSkill(Directory agentsDirectory) async {
  final source = Directory(
    p.join(_pluginRoot().path, 'skills', 'careershopper'),
  );
  if (!source.existsSync()) {
    throw StateError('Bundled CareerShopper skill is missing.');
  }

  final skillsDirectory = Directory(p.join(agentsDirectory.path, 'skills'));
  final target = Directory(p.join(skillsDirectory.path, 'careershopper'));
  final targetType = FileSystemEntity.typeSync(target.path, followLinks: false);
  if (targetType == FileSystemEntityType.link) {
    throw StateError('Refusing to replace a symlink at ${target.path}.');
  }
  if (target.existsSync() &&
      !File(p.join(target.path, '.careershopper-managed')).existsSync()) {
    throw StateError(
      'Refusing to overwrite an unmanaged skill at ${target.path}.',
    );
  }

  await skillsDirectory.create(recursive: true);
  await _archiveLegacySkills(agentsDirectory);
  final archive = Directory(
    p.join(agentsDirectory.path, 'careershopper-skill-backups'),
  );
  await archive.create(recursive: true);
  final staging = await archive.createTemp('staging-');
  Directory? backup;
  try {
    await _copyDirectory(source, staging);
    await File(
      p.join(staging.path, '.careershopper-managed'),
    ).writeAsString('Managed by careershopper-agent.\n', flush: true);
    if (target.existsSync()) {
      backup = await target.rename(
        p.join(
          archive.path,
          'careershopper.backup.${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
    }
    try {
      await staging.rename(target.path);
    } catch (_) {
      if (backup != null) await backup.rename(target.path);
      rethrow;
    }
  } finally {
    if (staging.existsSync()) await staging.delete(recursive: true);
  }
  stdout.writeln('Installed CareerShopper skill at ${target.path}');
}

Future<void> _uninstallSkill(Directory agentsDirectory) async {
  await _archiveLegacySkills(agentsDirectory);
  final target = Directory(
    p.join(agentsDirectory.path, 'skills', 'careershopper'),
  );
  final targetType = FileSystemEntity.typeSync(target.path, followLinks: false);
  if (targetType == FileSystemEntityType.link) {
    throw StateError('Refusing to remove a symlink at ${target.path}.');
  }
  if (!target.existsSync()) {
    stdout.writeln('CareerShopper skill is not installed.');
    return;
  }
  if (!File(p.join(target.path, '.careershopper-managed')).existsSync()) {
    throw StateError(
      'Refusing to remove an unmanaged skill at ${target.path}.',
    );
  }
  final archive = Directory(
    p.join(agentsDirectory.path, 'careershopper-skill-backups'),
  );
  await archive.create(recursive: true);
  final recovered = Directory(
    p.join(
      archive.path,
      'careershopper.removed.${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await target.rename(recovered.path);
  stdout.writeln('Moved the installed skill to ${recovered.path}');
}

// Backups containing SKILL.md must never live in the skill-discovery tree.
Future<void> _archiveLegacySkills(Directory agentsDirectory) async {
  final skills = Directory(p.join(agentsDirectory.path, 'skills'));
  if (!skills.existsSync()) return;
  final legacyName = RegExp(
    r'^careershopper\.(backup|removed)\.\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.\d+Z$',
  );
  final archive = Directory(
    p.join(agentsDirectory.path, 'careershopper-skill-backups'),
  );
  await for (final entry in skills.list(followLinks: false)) {
    if (entry is! Directory || !legacyName.hasMatch(p.basename(entry.path))) {
      continue;
    }
    final marker = File(p.join(entry.path, '.careershopper-managed'));
    if (FileSystemEntity.typeSync(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        (await marker.readAsString()).trim() !=
            'Managed by careershopper-agent.') {
      continue;
    }
    await archive.create(recursive: true);
    var destination = p.join(archive.path, p.basename(entry.path));
    if (FileSystemEntity.typeSync(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      destination = p.join(
        (await archive.createTemp('recovered-')).path,
        p.basename(entry.path),
      );
    }
    await entry.rename(destination);
    stdout.writeln('Archived duplicate skill at $destination');
  }
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    final destinationPath = p.join(destination.path, name);
    if (entity is File) {
      await entity.copy(destinationPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(destinationPath));
    } else {
      throw StateError('Refusing to copy non-file skill entry: ${entity.path}');
    }
  }
}
