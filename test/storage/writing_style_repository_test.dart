import 'dart:io';

import 'package:careershopper/src/storage/writing_style_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared file defaults, edit, stale write, and reset preserve other files',
    () async {
      final dir = await Directory.systemTemp.createTemp('careershopper-style-');
      addTearDown(() => dir.delete(recursive: true));
      final store = WritingStyleRepository(directory: dir);
      final initial = await store.read();
      expect(await store.file.exists(), false);
      expect(
        initial['text'],
        await File('assets/writing-style.md').readAsString(),
      );
      final saved = await store.save(
        'Direct sentences. No em dashes.',
        initial['revision'] as String,
      );
      expect(await store.file.readAsString(), saved['text']);
      expect(
        (await WritingStyleRepository(directory: dir).read())['text'],
        saved['text'],
      );
      await expectLater(
        store.save('Overwrite', initial['revision'] as String),
        throwsStateError,
      );
      expect((await store.read())['text'], saved['text']);
      await expectLater(
        store.save('', saved['revision'] as String),
        throwsFormatException,
      );
      final reset = await store.save(
        await store.defaultText(),
        saved['revision'] as String,
      );
      expect(reset['revision'], initial['revision']);
      expect(
        await dir.list().where((file) => file.path.endsWith('.tmp')).isEmpty,
        true,
      );
    },
  );
}
