import 'package:careershopper/src/features/sources/sources_page.dart';
import 'package:careershopper/src/storage/configuration_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LinkedIn source editor validates and saves its page limit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _SourceStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcesPage(configuration: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page limit: 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit source'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(
      TextFormField,
      'Maximum pages per search',
    );
    expect(tester.widget<TextFormField>(field).controller!.text, '3');
    await tester.enterText(field, '0');
    await tester.tap(find.text('Save source'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 1 to 100.'), findsOneWidget);
    expect(store.saved, isNull);
    await tester.enterText(field, '7');
    await tester.tap(find.text('Save source'));
    await tester.pumpAndSettle();
    expect(store.saved!.values['max_pages'], 7);
    expect(store.saved!.sourceFamily, 'linkedin');
  });
}

class _SourceStore implements ConfigurationStore {
  SourceConfigurationDraft? saved;
  @override
  Stream<List<SourceConfiguration>> watchSourceConfigurations() =>
      Stream.value([
        const SourceConfiguration(
          id: 'linkedin',
          sourceFamily: 'linkedin',
          adapterId: 'linkedin_guest_search_v1',
          enabled: true,
          values: {'max_pages': 3},
          healthState: 'healthy',
        ),
      ]);
  @override
  Future<String> saveSourceConfiguration(SourceConfigurationDraft draft) async {
    saved = draft;
    return 'linkedin';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
