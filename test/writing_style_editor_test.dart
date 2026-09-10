import 'package:careershopper/src/features/documents/writing_style_editor.dart';
import 'package:careershopper/src/storage/writing_style_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStyle extends WritingStyleRepository {
  String current = 'Existing style';
  int version = 1;
  @override
  Future<Map<String, Object?>> read() async => {
    'text': current,
    'revision': '$version',
    'default_text': 'Default style',
    'path': '/test/writing-style.md',
  };
  @override
  Future<Map<String, Object?>> save(
    String text,
    String expectedRevision,
  ) async {
    if (expectedRevision != '$version') {
      throw StateError('Writing style changed. Reload before saving.');
    }
    current = text;
    version++;
    return read();
  }
}

void main() {
  testWidgets('shared style edit, reset preview, save, and stale reload', (
    tester,
  ) async {
    final store = MemoryStyle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WritingStyleEditor(repository: store),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared writing style'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New voice');
    expect(store.current, 'Existing style');
    await tester.tap(find.text('Save writing style'));
    await tester.pumpAndSettle();
    expect(store.current, 'New voice');
    await tester.tap(find.text('Reset writing style to default'));
    await tester.pumpAndSettle();
    expect(store.current, 'New voice');
    expect(find.text('Default style'), findsOneWidget);
    store.version++;
    await tester.tap(find.text('Save writing style'));
    await tester.pumpAndSettle();
    expect(store.current, 'New voice');
    expect(find.textContaining('Reload before saving'), findsOneWidget);
    await tester.tap(find.text('Reload saved style'));
    await tester.pumpAndSettle();
    expect(find.text('New voice'), findsOneWidget);
  });
}
