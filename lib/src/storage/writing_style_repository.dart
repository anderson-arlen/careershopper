import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_data_directory.dart';

/// One editable file shared by document generation and application answers.
class WritingStyleRepository {
  WritingStyleRepository({Directory? directory, this.defaultFile})
    : directory = directory ?? careerShopperDataDirectory();

  final Directory directory;
  final File? defaultFile;
  File get file => File(p.join(directory.path, 'writing-style.md'));

  Future<String> defaultText() async {
    final executable = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      ?defaultFile,
      File(
        p.join(
          executable,
          'data',
          'flutter_assets',
          'assets',
          'writing-style.md',
        ),
      ),
      File(p.join(executable, '..', 'assets', 'writing-style.md')),
      File(
        p.join(directory.path, 'agent-plugin', 'assets', 'writing-style.md'),
      ),
      File(p.join(Directory.current.path, 'assets', 'writing-style.md')),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return _validate(await candidate.readAsString());
      }
    }
    throw StateError(
      'Bundled writing style is unavailable. Reinstall CareerShopper.',
    );
  }

  Future<Map<String, Object?>> read() async {
    final defaults = await defaultText();
    final text = await file.exists()
        ? _validate(await file.readAsString())
        : defaults;
    return {
      'text': text,
      'revision': sha256.convert(utf8.encode(text)).toString(),
      'path': file.path,
      'default_text': defaults,
    };
  }

  Future<Map<String, Object?>> save(
    String text,
    String expectedRevision,
  ) async {
    _validate(text);
    await directory.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      if ((await read())['revision'] != expectedRevision) {
        throw StateError('Writing style changed. Reload before saving.');
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
      return read();
    } finally {
      await lock.close();
    }
  }

  String _validate(String text) {
    if (text.trim().isEmpty || text.length > 20000) {
      throw const FormatException(
        'Writing style must contain 1 to 20,000 characters.',
      );
    }
    return text;
  }
}
