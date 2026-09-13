import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main() async {
  final buildOutput = Directory(p.join('build', 'agent-plugin-cli'));
  final process = await Process.start(Platform.resolvedExecutable, [
    'build',
    'cli',
    '--target=bin/careershopper_agent.dart',
    '--output=${buildOutput.path}',
  ], mode: ProcessStartMode.inheritStdio);
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      const ['build', 'cli'],
      'Hook-aware Dart CLI build failed.',
      result,
    );
  }

  final bundle = Directory(p.join(buildOutput.path, 'bundle'));
  final builtExecutable = File(
    p.join(
      bundle.path,
      'bin',
      Platform.isWindows ? 'careershopper_agent.exe' : 'careershopper_agent',
    ),
  );
  if (!builtExecutable.existsSync()) {
    throw StateError('Dart did not produce ${builtExecutable.path}.');
  }

  final pluginBin = Directory(p.join('agent-plugin', 'bin'));
  await pluginBin.create(recursive: true);
  final installedExecutable = File(
    p.join(
      pluginBin.path,
      Platform.isWindows ? 'careershopper-agent.exe' : 'careershopper-agent',
    ),
  );
  await builtExecutable.copy(installedExecutable.path);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['0755', installedExecutable.path]);
  }

  final builtLibraries = Directory(p.join(bundle.path, 'lib'));
  if (builtLibraries.existsSync()) {
    await _copyDirectory(
      builtLibraries,
      Directory(p.join('agent-plugin', 'lib')),
    );
  }
  stdout.writeln('Built portable agent integration in agent-plugin/.');
  await File('LICENSE').copy(p.join('agent-plugin', 'LICENSE'));
  await _copyDirectory(
    Directory(p.join('assets', 'fonts')),
    Directory(p.join('agent-plugin', 'assets', 'fonts')),
  );
  await File(
    p.join('assets', 'writing-style.md'),
  ).copy(p.join('agent-plugin', 'assets', 'writing-style.md'));
  await File(
    p.join('assets', 'JobSpy-LICENSE'),
  ).copy(p.join('agent-plugin', 'assets', 'JobSpy-LICENSE'));
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final outputPath = p.join(destination.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(outputPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(outputPath));
    }
  }
}
