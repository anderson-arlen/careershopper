import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final installRoot = _option(arguments, '--install-root');
  final agentsDir = _option(arguments, '--agents-dir');
  if (installRoot == null || agentsDir == null) {
    stderr.writeln(
      'Usage: dart run tool/install_agent_integration.dart '
      '--install-root PATH --agents-dir PATH',
    );
    exitCode = 64;
    return;
  }

  final source = Directory(p.join(Directory.current.path, 'agent-plugin'));
  final executableName = Platform.isWindows
      ? 'careershopper-agent.exe'
      : 'careershopper-agent';
  if (!File(p.join(source.path, 'bin', executableName)).existsSync()) {
    throw StateError(
      'The native MCP helper has not been built. Run '
      '`dart run tool/build_agent_plugin.dart` first.',
    );
  }

  final root = Directory(p.normalize(p.absolute(installRoot)));
  final target = Directory(p.join(root.path, 'agent-plugin'));
  final targetType = FileSystemEntity.typeSync(target.path, followLinks: false);
  if (targetType == FileSystemEntityType.link) {
    throw StateError('Refusing to replace a symlink at ${target.path}.');
  }
  if (target.existsSync() &&
      !File(p.join(target.path, '.careershopper-managed')).existsSync()) {
    throw StateError(
      'Refusing to overwrite an unmanaged plugin at ${target.path}.',
    );
  }

  await root.create(recursive: true);
  final staging = Directory(
    p.join(
      root.path,
      '.agent-plugin.staging.${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await _copyDirectory(source, staging);
  await File(
    p.join(staging.path, '.careershopper-managed'),
  ).writeAsString('Managed by CareerShopper make install.\n', flush: true);

  if (target.existsSync()) {
    final suffix = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    await target.rename('${target.path}.backup.$suffix');
  }
  await staging.rename(target.path);

  final installedExecutable = File(p.join(target.path, 'bin', executableName));
  final skillInstall = await Process.start(installedExecutable.path, [
    'skill',
    'install',
    '--agents-dir',
    p.normalize(p.absolute(agentsDir)),
  ], mode: ProcessStartMode.inheritStdio);
  final skillExitCode = await skillInstall.exitCode;
  if (skillExitCode != 0) {
    throw ProcessException(
      installedExecutable.path,
      const ['skill', 'install'],
      'The plugin was installed, but skill installation failed.',
      skillExitCode,
    );
  }

  stdout.writeln('');
  stdout.writeln('CareerShopper agent integration installed.');
  stdout.writeln('Plugin directory: ${target.path}');
  stdout.writeln('MCP stdio command:');
  stdout.writeln('  ${installedExecutable.path} mcp');
  stdout.writeln('');
  stdout.writeln('Register it with a supported harness:');
  stdout.writeln(
    '  codex mcp add careershopper -- ${installedExecutable.path} mcp',
  );
  stdout.writeln(
    '  claude mcp add --scope user --transport stdio careershopper -- '
    '${installedExecutable.path} mcp',
  );
  stdout.writeln(
    '  gemini mcp add --scope user careershopper '
    '${installedExecutable.path} mcp',
  );
  stdout.writeln('');
  stdout.writeln('Or give a compatible Agent Plugin installer this directory:');
  stdout.writeln('  ${target.path}');
  stdout.writeln('');
  stdout.writeln('Generic MCP configuration:');
  stdout.writeln('''
{
  "mcpServers": {
    "careershopper": {
      "command": "${installedExecutable.path}",
      "args": ["mcp"]
    }
  }
}
''');
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final destinationPath = p.join(destination.path, p.basename(entity.path));
    if (entity is File) {
      await entity.copy(destinationPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(destinationPath));
    } else {
      throw StateError(
        'Refusing to install non-file plugin entry: ${entity.path}',
      );
    }
  }
}
