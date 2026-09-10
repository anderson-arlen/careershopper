import 'package:careershopper/src/documents/material_markdown.dart';
import 'package:careershopper/src/features/documents/editable_markdown_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preview edits retain rich text, frontmatter, line breaks and citations',
    (tester) async {
      final controller = TextEditingController(
        text: '''---
document_type: resume
subtitle: Engineer
footer: Alex Example
page_numbers: true
--- <!-- facts: work-1 -->

# Alex Example <!-- facts: identity-1 -->

## DIRECT MATCH <!-- facts: identity-1 -->

- **Ownership:** Built services. <!-- facts: work-1 -->

<!-- pagebreak -->

## PRODUCTS <!-- facts: identity-1 -->

### **SignalKit** · Dart, Flutter <!-- facts: work-1 -->

*Years Active: 2026–Present* <!-- facts: work-1 -->''',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableMarkdownPreview(
              controller: controller,
              enabled: true,
              onChanged: () {},
            ),
          ),
        ),
      );
      expect(find.text('  Page break  '), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      final field = fields.firstWhere(
        (f) => f.controller!.text.startsWith('**Ownership'),
      );
      final project = fields.firstWhere(
        (f) => f.controller!.text.startsWith('**SignalKit**'),
      );
      final projectSpans = project.controller!
          .buildTextSpan(
            context: tester.element(find.byType(EditableMarkdownPreview)),
            style: tester
                .widget<TextField>(
                  find.descendant(
                    of: find.byWidget(project),
                    matching: find.byType(TextField),
                  ),
                )
                .style,
            withComposing: false,
          )
          .children!
          .cast<TextSpan>();
      expect(
        projectSpans
            .singleWhere((s) => s.text == 'SignalKit')
            .style!
            .fontWeight,
        FontWeight.bold,
      );
      expect(
        projectSpans
            .singleWhere((s) => s.text == ' · Dart, Flutter')
            .style!
            .fontWeight,
        FontWeight.normal,
      );
      final spans = field.controller!.buildTextSpan(
        context: tester.element(find.byType(EditableMarkdownPreview)),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(
        (spans.children![1] as TextSpan).style!.fontWeight,
        FontWeight.bold,
      );
      await tester.enterText(
        find.byWidget(field),
        '**Ownership:** Built reliable services.',
      );
      await tester.pump();
      final parsed = parseMaterialDocument(controller.text);
      expect(parsed.metadata['subtitle'], 'Engineer');
      expect(parsed.metadataFactIds, ['work-1']);
      expect(parsed.blocks.where((b) => b.pageBreak), hasLength(1));
      expect(
        controller.text,
        contains(
          '**Ownership:** Built reliable services. <!-- facts: work-1 -->',
        ),
      );
      expect(controller.text, contains('*Years Active: 2026–Present*'));
      await tester.enterText(find.byWidget(fields.first), 'Alex Updated');
      expect(parseMaterialDocument(controller.text).footer, 'Alex Updated');
    },
  );
}
