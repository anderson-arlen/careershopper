import 'dart:io';

import 'package:path/path.dart' as p;

const _managedMarker = 'Managed by CareerShopper make install.';

Future<void> main(List<String> arguments) async {
  if (!Platform.isLinux) {
    throw UnsupportedError('Desktop installation currently supports Linux.');
  }
  final bundleOption = _option(arguments, '--bundle');
  final prefixOption = _option(arguments, '--prefix');
  final dataHomeOption = _option(arguments, '--data-home');
  if (bundleOption == null || prefixOption == null || dataHomeOption == null) {
    stderr.writeln(
      'Usage: dart run tool/install_linux_desktop.dart '
      '--bundle PATH --prefix PATH --data-home PATH',
    );
    exitCode = 64;
    return;
  }

  final projectRoot = Directory.current.path;
  final bundle = Directory(p.normalize(p.absolute(bundleOption)));
  final sourceExecutable = File(p.join(bundle.path, 'careershopper'));
  if (!sourceExecutable.existsSync()) {
    throw StateError('Linux release bundle is missing at ${bundle.path}.');
  }

  final prefix = p.normalize(p.absolute(prefixOption));
  final dataHome = p.normalize(p.absolute(dataHomeOption));
  final appTarget = Directory(p.join(prefix, 'lib', 'careershopper'));
  final appMarker = File(p.join(appTarget.path, '.careershopper-managed'));
  _requireManagedDirectory(appTarget, appMarker);

  final appParent = Directory(p.dirname(appTarget.path));
  await appParent.create(recursive: true);
  final staging = Directory(
    p.join(
      appParent.path,
      '.careershopper.staging.${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await _copyDirectory(bundle, staging);
  await File(
    p.join(staging.path, '.careershopper-managed'),
  ).writeAsString('$_managedMarker\n', flush: true);
  if (appTarget.existsSync()) {
    final suffix = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    await appTarget.rename('${appTarget.path}.backup.$suffix');
  }
  await staging.rename(appTarget.path);

  final installedExecutable = File(p.join(appTarget.path, 'careershopper'));
  final binDirectory = Directory(p.join(prefix, 'bin'));
  await binDirectory.create(recursive: true);
  final launcher = File(p.join(binDirectory.path, 'careershopper'));
  _requireManagedFile(launcher);
  await launcher.writeAsString(
    '#!/bin/sh\n# $_managedMarker\nexec ${_shellQuote(installedExecutable.path)} "\$@"\n',
    flush: true,
  );
  await _chmodExecutable(installedExecutable.path);
  await _chmodExecutable(launcher.path);

  final iconSource = File(p.join(projectRoot, 'assets', 'careershopper.svg'));
  if (!iconSource.existsSync()) {
    throw StateError('Application icon is missing at ${iconSource.path}.');
  }
  final icon = File(
    p.join(
      dataHome,
      'icons',
      'hicolor',
      'scalable',
      'apps',
      'careershopper.svg',
    ),
  );
  _requireManagedFile(icon);
  await icon.parent.create(recursive: true);
  await iconSource.copy(icon.path);

  final desktopEntry = File(
    p.join(dataHome, 'applications', 'com.example.careershopper.desktop'),
  );
  _requireManagedFile(desktopEntry);
  await desktopEntry.parent.create(recursive: true);
  await desktopEntry.writeAsString('''# $_managedMarker
[Desktop Entry]
Version=1.0
Type=Application
Name=CareerShopper
Comment=Find, evaluate, and manage job opportunities
Exec=${_desktopQuote(launcher.path)}
Icon=careershopper
Terminal=false
Categories=Office;
Keywords=career;jobs;applications;search;
StartupNotify=true
StartupWMClass=com.example.careershopper
''', flush: true);

  // Previous application IDs used different filenames. Remove only launchers
  // created by this installer for the same executable, never unrelated entries.
  await for (final entry in desktopEntry.parent.list(followLinks: false)) {
    if (entry is! File ||
        entry.path == desktopEntry.path ||
        !p.basename(entry.path).endsWith('.careershopper.desktop')) {
      continue;
    }
    final lines = await entry.readAsLines();
    if (lines.firstOrNull == '# $_managedMarker' &&
        lines.contains('Name=CareerShopper') &&
        lines.contains('Exec=${_desktopQuote(launcher.path)}')) {
      await entry.delete();
    }
  }

  await _refreshDesktopDatabase(desktopEntry.parent.path);
  stdout.writeln('Installed CareerShopper desktop bundle at ${appTarget.path}');
  stdout.writeln('Installed application launcher at ${launcher.path}');
  stdout.writeln('Installed desktop entry at ${desktopEntry.path}');
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

void _requireManagedDirectory(Directory directory, File marker) {
  final type = FileSystemEntity.typeSync(directory.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw StateError('Refusing to replace a symlink at ${directory.path}.');
  }
  if (directory.existsSync() && !marker.existsSync()) {
    throw StateError(
      'Refusing to overwrite an unmanaged application at ${directory.path}.',
    );
  }
}

void _requireManagedFile(File file) {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw StateError('Refusing to replace a symlink at ${file.path}.');
  }
  if (file.existsSync() && !file.readAsStringSync().contains(_managedMarker)) {
    throw StateError(
      'Refusing to overwrite an unmanaged file at ${file.path}.',
    );
  }
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
      throw StateError('Refusing to install bundle link: ${entity.path}');
    }
  }
}

Future<void> _chmodExecutable(String path) async {
  final result = await Process.run('chmod', ['755', path]);
  if (result.exitCode != 0) {
    throw ProcessException('chmod', ['755', path], '${result.stderr}');
  }
}

Future<void> _refreshDesktopDatabase(String applicationsDirectory) async {
  try {
    final result = await Process.run('update-desktop-database', [
      applicationsDirectory,
    ]);
    if (result.exitCode == 0) return;
    stderr.writeln('warning: desktop application cache was not refreshed.');
  } on ProcessException {
    stderr.writeln(
      'warning: update-desktop-database is unavailable; the launcher may appear after the desktop environment refreshes.',
    );
  }
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _desktopQuote(String value) =>
    '"${value.replaceAll(r'\\', r'\\\\').replaceAll('"', r'\\"').replaceAll(r'$', r'\\$').replaceAll('`', r'\\`')}"';
