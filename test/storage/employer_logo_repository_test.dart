import 'dart:io';

import 'package:careershopper/src/storage/database.dart';
import 'package:careershopper/src/storage/employer_logo_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late CareerShopperDatabase db;
  setUp(() async {
    db = CareerShopperDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await db
        .into(db.employers)
        .insert(
          EmployersCompanion.insert(
            id: 'employer',
            displayName: 'Example',
            normalizedName: 'example',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'downloaded logos become local thumbnails and identical source is cached',
    () async {
      var calls = 0;
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 256, height: 64)),
      );
      final logos = EmployerLogoRepository(
        db,
        fetch: (_) async {
          calls++;
          return png;
        },
      );
      final url = Uri.parse('https://example.test/company.png');
      await logos.setFromUrl('employer', url);
      await logos.setFromUrl('employer', url);
      expect(calls, 1);
      final saved = await db.select(db.employers).getSingle();
      expect(saved.logoSourceUrl, url.toString());
      final image = img.decodePng(saved.logoPng!);
      expect(image!.width, 128);
      expect(image.height, 32);
    },
  );

  test(
    'unusable replacement retains existing logo, blocked employers never fetch',
    () async {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      await EmployerLogoRepository(
        db,
        fetch: (_) async => png,
      ).setFromUrl('employer', Uri.parse('https://example.test/good.png'));
      final invalid = EmployerLogoRepository(
        db,
        fetch: (_) async => Uint8List.fromList('not an image'.codeUnits),
      );
      await expectLater(
        invalid.setFromUrl(
          'employer',
          Uri.parse('https://example.test/bad.png'),
        ),
        throwsFormatException,
      );
      expect(
        (await db.select(db.employers).getSingle()).logoSourceUrl,
        'https://example.test/good.png',
      );
      await db
          .update(db.employers)
          .write(EmployersCompanion(blockedAt: Value(DateTime.now())));
      var fetched = false;
      await expectLater(
        EmployerLogoRepository(
          db,
          fetch: (_) async {
            fetched = true;
            return png;
          },
        ).setFromUrl('employer', Uri.parse('https://example.test/new.png')),
        throwsStateError,
      );
      expect(fetched, isFalse);
    },
  );

  test(
    'bounded decodes and public HTTPS policy reject unsafe inputs',
    () async {
      for (final url in [
        'http://example.test/a.png',
        'https://127.0.0.1/a.png',
        'https://localhost/a.png',
        'https://a.local/a.png',
        'file:///a.png',
        'https://user:password@example.test/a.png',
        'https://example.test:8443/a.png',
      ]) {
        expect(
          () => validateLogoUrl(Uri.parse(url)),
          throwsFormatException,
          reason: url,
        );
      }
      for (final address in [
        '127.0.0.1',
        '10.0.0.1',
        '172.16.0.1',
        '192.168.0.1',
        '169.254.169.254',
        '100.64.0.1',
        '::1',
        'fc00::1',
        '::ffff:127.0.0.1',
      ]) {
        expect(
          isPublicLogoAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
      expect(isPublicLogoAddress(InternetAddress('8.8.8.8')), isTrue);
      final oversized = EmployerLogoRepository(
        db,
        fetch: (_) async => Uint8List(EmployerLogoRepository.maxBytes + 1),
      );
      await expectLater(
        oversized.setFromUrl(
          'employer',
          Uri.parse('https://example.test/big.png'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'v10 migration adds optional logo columns without changing employer state',
    () async {
      final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'careershopper-logo-migration-',
      );
      final file = File('${directory.path}/db.sqlite3');
      await db.customStatement('VACUUM INTO ?', [file.path]);
      var migrated = CareerShopperDatabase(NativeDatabase(file));
      try {
        await migrated.customSelect('SELECT * FROM employers').get();
        await migrated.customStatement(
          'ALTER TABLE employers DROP COLUMN logo_png',
        );
        await migrated.customStatement(
          'ALTER TABLE employers DROP COLUMN logo_source_url',
        );
        await migrated.customStatement('PRAGMA user_version = 10');
        await migrated.close();
        migrated = CareerShopperDatabase(NativeDatabase(file));
        final row = await migrated.select(migrated.employers).getSingle();
        expect(row.displayName, 'Example');
        expect(row.logoPng, isNull);
        expect(row.logoSourceUrl, isNull);
      } finally {
        await migrated.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning;
      }
    },
  );
}
