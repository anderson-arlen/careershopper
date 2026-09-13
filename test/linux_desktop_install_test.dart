import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/install_linux_desktop.dart' as installer;

void main() {
  test(
    'install replaces only owned launchers and preserves application data',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'careershopper-desktop-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final bundle = Directory(p.join(root.path, 'bundle'))..createSync();
      File(
        p.join(bundle.path, 'careershopper'),
      ).writeAsStringSync('test executable');
      final prefix = p.join(root.path, 'prefix');
      final dataHome = p.join(root.path, 'data');
      final applications = Directory(p.join(dataHome, 'applications'))
        ..createSync(recursive: true);
      final database = File(
        p.join(dataHome, 'careershopper', 'careershopper.sqlite3'),
      );
      database.parent.createSync(recursive: true);
      database.writeAsStringSync('existing application data');
      final exec = 'Exec="${p.join(prefix, 'bin', 'careershopper')}"';
      const marker = '# Managed by CareerShopper make install.';
      final old =
          File(p.join(applications.path, 'org.legacy.careershopper.desktop'))
            ..writeAsStringSync(
              '$marker\n[Desktop Entry]\nName=CareerShopper\n$exec\n',
            );
      final unmanaged = File(
        p.join(applications.path, 'org.unmanaged.careershopper.desktop'),
      )..writeAsStringSync('[Desktop Entry]\nName=CareerShopper\n$exec\n');
      final otherInstall =
          File(
            p.join(applications.path, 'org.other.careershopper.desktop'),
          )..writeAsStringSync(
            '$marker\n[Desktop Entry]\nName=CareerShopper\nExec="/other/careershopper"\n',
          );
      final linkedTarget = File(p.join(root.path, 'linked.desktop'))
        ..writeAsStringSync(
          '$marker\n[Desktop Entry]\nName=CareerShopper\n$exec\n',
        );
      final linked = Link(
        p.join(applications.path, 'org.link.careershopper.desktop'),
      )..createSync(linkedTarget.path);

      await installer.main([
        '--bundle',
        bundle.path,
        '--prefix',
        prefix,
        '--data-home',
        dataHome,
      ]);
      expect(old.existsSync(), isFalse);
      expect(unmanaged.existsSync(), isTrue);
      expect(otherInstall.existsSync(), isTrue);
      expect(linked.existsSync(), isTrue);
      expect(linkedTarget.existsSync(), isTrue);
      expect(database.readAsStringSync(), 'existing application data');
      final current = File(
        p.join(applications.path, 'com.example.careershopper.desktop'),
      );
      expect(
        current.readAsStringSync(),
        contains('StartupWMClass=com.example.careershopper'),
      );
      expect(
        File(
          p.join(prefix, 'lib', 'careershopper', 'careershopper'),
        ).readAsStringSync(),
        'test executable',
      );
      expect(
        File('linux/CMakeLists.txt').readAsStringSync(),
        contains('set(APPLICATION_ID "com.example.careershopper")'),
      );
      await installer.main([
        '--bundle',
        bundle.path,
        '--prefix',
        prefix,
        '--data-home',
        dataHome,
      ]);
      expect(current.existsSync(), isTrue);
      expect(database.readAsStringSync(), 'existing application data');
    },
    skip: !Platform.isLinux,
  );
}
