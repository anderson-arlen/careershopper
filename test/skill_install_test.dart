import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../bin/careershopper_agent.dart' as agent;

void main() {
  late Directory agents;

  setUp(() async {
    agents = await Directory.systemTemp.createTemp(
      'careershopper-install-test-',
    );
  });
  tearDown(() async => agents.delete(recursive: true));

  Future<void> run(String command) =>
      agent.main(['skill', command, '--agents-dir', agents.path]);

  Future<Directory> legacy(String name, {bool managed = true}) async {
    final directory = Directory(p.join(agents.path, 'skills', name));
    await directory.create(recursive: true);
    await File(p.join(directory.path, 'SKILL.md')).writeAsString('old skill');
    if (managed) {
      await File(
        p.join(directory.path, '.careershopper-managed'),
      ).writeAsString('Managed by careershopper-agent.\n');
    }
    return directory;
  }

  test(
    'repeat installs expose only one skill and uninstall exposes none',
    () async {
      await run('install');
      await run('install');
      await run('install');
      final skills = Directory(p.join(agents.path, 'skills'));
      expect(skills.listSync().map((e) => p.basename(e.path)), [
        'careershopper',
      ]);
      expect(
        File(p.join(skills.path, 'careershopper', 'SKILL.md')).existsSync(),
        isTrue,
      );
      final archive = Directory(
        p.join(agents.path, 'careershopper-skill-backups'),
      );
      expect(archive.listSync(), hasLength(2));
      await run('uninstall');
      expect(skills.listSync(), isEmpty);
      expect(archive.listSync(), hasLength(3));
    },
  );

  test(
    'archives only managed legacy backups, preserving contents and collisions',
    () async {
      const name = 'careershopper.backup.2026-09-05T19-11-51.601680Z';
      final old = await legacy(name);
      await legacy('careershopper.removed.2026-09-04T15-55-13.659Z');
      final unmanaged = await legacy(
        'careershopper.backup.2026-09-01T12-00-00.123Z',
        managed: false,
      );
      final unrelated = await legacy('another-skill');
      final collision = Directory(
        p.join(agents.path, 'careershopper-skill-backups', name),
      );
      await collision.create(recursive: true);
      await File(p.join(collision.path, 'keep.txt')).writeAsString('keep');
      await run('install');
      expect(old.existsSync(), isFalse);
      expect(unmanaged.existsSync(), isTrue);
      expect(unrelated.existsSync(), isTrue);
      expect(
        await File(p.join(collision.path, 'keep.txt')).readAsString(),
        'keep',
      );
      final archived =
          Directory(p.join(agents.path, 'careershopper-skill-backups'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => p.basename(f.path) == 'SKILL.md');
      expect(archived, hasLength(2));
      for (final file in archived) {
        expect(await file.readAsString(), 'old skill');
      }
    },
  );

  test('does not overwrite an unmanaged active skill', () async {
    final current = await legacy('careershopper', managed: false);
    await expectLater(run('install'), throwsStateError);
    expect(
      await File(p.join(current.path, 'SKILL.md')).readAsString(),
      'old skill',
    );
  });

  test('does not follow a legacy backup symlink', () async {
    final other = await legacy('other');
    final link = Link(
      p.join(
        agents.path,
        'skills',
        'careershopper.backup.2026-09-05T19-11-51.601680Z',
      ),
    );
    await link.create(other.path);
    await run('install');
    expect(link.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  }, skip: Platform.isWindows);
}
