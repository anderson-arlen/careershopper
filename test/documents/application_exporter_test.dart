import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:careershopper/src/documents/application_exporter.dart';
import 'package:careershopper/src/documents/material_markdown.dart';
import 'package:careershopper/src/documents/material_presentation.dart';
import 'package:careershopper/src/storage/document_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const markdown =
    '# Alex Example <!-- facts: identity-1 -->\n\n## Experience <!-- facts: work-1 -->\n\n- Built systems & supported customers. <!-- facts: work-1 -->';
void main() {
  test('adjacent individually cited bullets remain separate blocks', () {
    final parsed = parseMaterialDocument(
      '# Alex <!-- facts: identity -->\n- Built APIs. <!-- facts: work -->\n- Improved latency. <!-- facts: work -->',
    );
    expect(parsed.blocks, hasLength(3));
    expect(parsed.blocks.skip(1).every((b) => b.bullet), true);
    expect(parseMaterialDocument(parsed.toMarkdown()).blocks, hasLength(3));
    expect(
      () => parseMaterialDocument(
        '- Uncited bullet\n- Cited bullet <!-- facts: work -->',
      ),
      throwsFormatException,
    );
  });

  test(
    'project headings keep the name bold and the separated stack regular',
    () async {
      const source = '''# Alex Example <!-- facts: identity-1 -->

## PROJECTS <!-- facts: identity-1 -->

### **SignalKit** · Dart, Flutter, Go <!-- facts: project-1 -->

*Years Active: 2026 to Present* <!-- facts: project-1 -->

Built an application for tracking equipment maintenance. <!-- facts: project-1 -->

### Plain role heading <!-- facts: work-1 -->''';
      final blocks = parseMaterialMarkdown(source);
      final settings = ResumeTemplateSettings.defaults();
      final style = MaterialPresentation(blocks, 2, settings);
      expect(style.bold, isFalse);
      expect(style.keepWithNext, isTrue);
      expect(blocks[2].spans.first.bold, isTrue);
      expect(blocks[2].spans.last.bold, isFalse);
      expect(blocks[2].plainText, 'SignalKit · Dart, Flutter, Go');
      expect(MaterialPresentation(blocks, 5, settings).bold, isTrue);
      expect(parseMaterialDocument(source).toMarkdown(), source);
      final renderer = ApplicationDocumentRenderer();
      final docx = await renderer.render(
        source,
        settings,
        ApplicationDocumentFormat.docx,
      );
      final archive = ZipDecoder().decodeBytes(docx);
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      final runs = RegExp(
        r'<w:r>.*?</w:r>',
      ).allMatches(xml).map((m) => m.group(0)!);
      expect(
        runs.singleWhere((r) => r.contains('>SignalKit<')),
        contains('<w:b/>'),
      );
      expect(
        runs.singleWhere((r) => r.contains('· Dart, Flutter, Go')),
        isNot(contains('<w:b/>')),
      );
      expect(
        runs.singleWhere((r) => r.contains('Plain role heading')),
        contains('<w:b/>'),
      );
    },
  );

  test(
    'letter styling follows export role or metadata and preserves resume styling',
    () async {
      const letter = '''---
document_type: cover_letter
subtitle: Software Engineer application
--- <!-- facts: identity-1 -->

# Alex Example <!-- facts: identity-1 -->

Example City · alex@example.test <!-- facts: identity-1 -->

September 6, 2026 <!-- facts: identity-1 -->

Hiring Team  
**Example Company** <!-- facts: identity-1 -->

Dear Hiring Team, <!-- facts: identity-1 -->

I build and maintain software that helps customers complete their work. My experience owning production systems connects directly to the responsibilities in this role. <!-- facts: work-1 -->

I would welcome a conversation about the team's needs. <!-- facts: work-1 -->

Sincerely, <!-- facts: identity-1 -->

**Alex Example** <!-- facts: identity-1 -->''';
      final renderer = ApplicationDocumentRenderer(
        regularFont: await File('assets/fonts/DejaVuSans.ttf').readAsBytes(),
        boldFont: await File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytes(),
      );
      final settings = ResumeTemplateSettings.defaults();
      final bytes = await renderer.render(
        letter,
        settings,
        ApplicationDocumentFormat.docx,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      final styles = utf8.decode(archive.findFile('word/styles.xml')!.content);
      expect(styles, contains('w:sz w:val="20"'));
      expect(styles, contains('w:after="160" w:line="269"'));
      expect(
        xml,
        contains('w:top="1008" w:right="1123" w:bottom="1008" w:left="1123"'),
      );
      expect(xml, isNot(contains('<w:footerReference')));
      final paragraphs = RegExp(
        r'<w:p>.*?</w:p>',
      ).allMatches(xml).map((m) => m.group(0)!).toList();
      expect(paragraphs.first, isNot(contains('<w:b/>')));
      expect(paragraphs[1], contains('SOFTWARE ENGINEER APPLICATION'));
      expect(paragraphs[4], contains('<w:br/>'));
      expect(paragraphs.last, contains('<w:b/>'));
      expect(paragraphs[paragraphs.length - 2], contains('<w:keepNext/>'));
      final pdf = await renderer.render(
        letter,
        settings,
        ApplicationDocumentFormat.pdf,
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');

      final numbered = await renderer.render(
        letter.replaceFirst(
          'document_type: cover_letter',
          'document_type: cover_letter\npage_numbers: true',
        ),
        settings,
        ApplicationDocumentFormat.docx,
      );
      expect(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(numbered)
              .findFile('word/document.xml')!
              .content,
        ),
        contains('<w:footerReference'),
      );

      // Existing drafts may lack frontmatter, or supply the wrong type: the
      // known resume/letter export slot is authoritative for typography.
      final dir = await Directory.systemTemp.createTemp(
        'careershopper-letter-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final output = await ApplicationExporter(dir).export(
        markdown,
        markdown,
        settings,
        ApplicationDocumentFormat.docx,
        renderer,
      );
      final resumeArchive = ZipDecoder().decodeBytes(
        await File('$output/resume.docx').readAsBytes(),
      );
      final letterArchive = ZipDecoder().decodeBytes(
        await File('$output/cover letter.docx').readAsBytes(),
      );
      expect(
        utf8.decode(resumeArchive.findFile('word/styles.xml')!.content),
        contains('w:sz w:val="19"'),
      );
      expect(
        utf8.decode(resumeArchive.findFile('word/document.xml')!.content),
        contains('<w:footerReference'),
      );
      expect(
        utf8.decode(letterArchive.findFile('word/styles.xml')!.content),
        contains('w:line="269"'),
      );
      expect(
        utf8.decode(letterArchive.findFile('word/document.xml')!.content),
        isNot(contains('<w:footerReference')),
      );
      final forcedResume = await renderer.render(
        letter,
        settings,
        ApplicationDocumentFormat.docx,
        coverLetter: false,
      );
      expect(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(forcedResume)
              .findFile('word/styles.xml')!
              .content,
        ),
        contains('w:sz w:val="19"'),
      );
    },
  );
  test(
    'keeps headings and italic metadata with content without forced breaks',
    () async {
      const source = '''# Alex Example <!-- facts: identity-1 -->

Contact information <!-- facts: identity-1 -->

## Relevant Work History <!-- facts: work-1 -->

### Employer: Engineer <!-- facts: work-1 -->

*Remote · 2020–Present* <!-- facts: work-1 -->

- Built useful systems. <!-- facts: work-1 -->

## Projects <!-- facts: work-1 -->

### Example product <!-- facts: work-1 -->

*Years Active: 2021–Present* <!-- facts: work-1 -->

Helps end users. <!-- facts: work-1 -->''';
      final blocks = parseMaterialMarkdown(source);
      final settings = ResumeTemplateSettings.defaults();
      expect(
        [
          for (var i = 0; i < blocks.length; i++)
            MaterialPresentation(blocks, i, settings).keepWithNext,
        ],
        [true, false, true, true, true, false, true, true, true, false],
      );
      final bytes = await ApplicationDocumentRenderer().render(
        source,
        settings,
        ApplicationDocumentFormat.docx,
      );
      final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content,
      );
      final paragraphs = RegExp(
        r'<w:p>.*?</w:p>',
      ).allMatches(xml).map((m) => m.group(0)!).toList();
      expect(paragraphs[4], contains('<w:keepNext/>'));
      expect(paragraphs[5], isNot(contains('<w:keepNext/>')));
      expect(paragraphs[8], contains('<w:keepNext/>'));
      expect(xml, isNot(contains('w:type="page"')));
    },
  );
  test(
    'pipeline DOCX has centered masthead, section rules, named footer and stable bytes',
    () async {
      final renderer = ApplicationDocumentRenderer();
      final settings = ResumeTemplateSettings.defaults();
      final first = await renderer.render(
        markdown,
        settings,
        ApplicationDocumentFormat.docx,
      );
      expect(
        await renderer.render(
          markdown,
          settings,
          ApplicationDocumentFormat.docx,
        ),
        first,
      );
      final archive = ZipDecoder().decodeBytes(first);
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, contains('ALEX EXAMPLE'));
      expect(xml, contains('w:val="center"'));
      expect(xml, contains('A9B7C5'));
      final footer = utf8.decode(archive.findFile('word/footer.xml')!.content);
      expect(footer, contains('Alex Example'));
      expect(footer, contains('NUMPAGES'));
    },
  );
  test(
    'restricted markdown rejects missing citations and unsupported structures',
    () {
      expect(parseMaterialMarkdown(markdown), hasLength(3));
      for (final invalid in [
        'No citation',
        '**Unclosed bold <!-- facts: x -->',
        '# Empty <!-- facts: , -->',
        '[Link](https://example.test) <!-- facts: x -->',
      ]) {
        expect(() => parseMaterialMarkdown(invalid), throwsFormatException);
      }
    },
  );
  test(
    'pipeline format survives parsing, editing serialization and export',
    () async {
      final source = await File(
        'test/fixtures/pipeline_resume.md',
      ).readAsString();
      final parsed = parseMaterialDocument(source);
      expect(parsed.blocks[1].metadataSubtitle, isTrue);
      expect(parsed.blocks[1].factIds, ['identity-1', 'work-1']);
      expect(parsed.blocks.where((b) => b.pageBreak), hasLength(1));
      final skills = parsed.blocks.firstWhere(
        (b) => b.text.startsWith('**Backend and data:'),
      );
      expect(skills.spans.where((s) => s.bold), hasLength(3));
      expect(skills.plainText.split('\n'), hasLength(3));
      final roundTrip = parseMaterialDocument(parsed.toMarkdown());
      expect(roundTrip.toMarkdown(), parsed.toMarkdown());
      final renderer = ApplicationDocumentRenderer(
        regularFont: await File('assets/fonts/DejaVuSans.ttf').readAsBytes(),
        boldFont: await File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytes(),
        italicFont: await File(
          'assets/fonts/DejaVuSans-Oblique.ttf',
        ).readAsBytes(),
        boldItalicFont: await File(
          'assets/fonts/DejaVuSans-BoldOblique.ttf',
        ).readAsBytes(),
      );
      final settings = ResumeTemplateSettings.defaults();
      final docx = await renderer.render(
        source,
        settings,
        ApplicationDocumentFormat.docx,
      );
      final archive = ZipDecoder().decodeBytes(docx);
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('<w:i/>'));
      expect(xml, contains('<w:br w:type="page"/>'));
      expect(xml, contains('<w:br/>'));
      expect(xml, contains('SOFTWARE ENGINEER'));
      expect(xml, isNot(contains('facts:')));
      expect(xml, isNot(contains('**')));
      expect(xml, isNot(contains('document_type:')));
      final pdf = await renderer.render(
        source,
        settings,
        ApplicationDocumentFormat.pdf,
      );
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      // Opt-in retention for visual regression review, never application output.
      final qa = Platform.environment['CAREERSHOPPER_RENDER_QA'];
      if (qa != null) {
        await Directory(qa).create(recursive: true);
        await File('$qa/pipeline.docx').writeAsBytes(docx);
        await File('$qa/pipeline.pdf').writeAsBytes(pdf);
      }
      final disabled = await renderer.render(
        source.replaceFirst('page_numbers: true', 'page_numbers: false'),
        settings,
        ApplicationDocumentFormat.docx,
      );
      expect(
        utf8.decode(
          ZipDecoder()
              .decodeBytes(disabled)
              .findFile('word/document.xml')!
              .content,
        ),
        isNot(contains('<w:footerReference')),
      );
    },
  );

  test('formatting cannot bypass content and metadata validation', () {
    for (final source in [
      '---\nsubtitle: Engineer\n---\n\n$markdown',
      '---\nfooter: Somebody Else\n---\n\n$markdown',
      '---\npage_numbers: yes\n---\n\n$markdown',
      '---\ncommand: run something\n---\n\n$markdown',
      '<!-- pagebreak -->\n\n$markdown',
      '$markdown\n\n<!-- pagebreak -->',
      '$markdown\n\n<script>bad</script> <!-- facts: work-1 -->',
    ]) {
      expect(() => parseMaterialDocument(source), throwsFormatException);
    }
    expect(
      parseMaterialMarkdown(
        '***Both*** <!-- facts: work-1 -->',
      ).single.spans.single.bold,
      isTrue,
    );
    expect(
      parseMaterialMarkdown(
        '***Both*** <!-- facts: work-1 -->',
      ).single.spans.single.italic,
      isTrue,
    );
  });
  test(
    'exports exact names, clears old files, strips sources, renders both formats',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'careershopper-export-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final exporter = ApplicationExporter(dir);
      expect(exporter.outputPath, '${dir.path}/Documents/CareerShopper');
      await Directory('${dir.path}/Documents').create();
      final sibling = File('${dir.path}/Documents/keep.txt');
      await sibling.writeAsString('keep');
      final oldOutput = Directory('${dir.path}/application-output');
      await oldOutput.create();
      final oldFile = File('${oldOutput.path}/resume.docx');
      await oldFile.writeAsString('old export');
      final renderer = ApplicationDocumentRenderer(
        regularFont: await File('assets/fonts/DejaVuSans.ttf').readAsBytes(),
        boldFont: await File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytes(),
      );
      final path = await exporter.export(
        markdown,
        markdown,
        ResumeTemplateSettings.defaults(),
        ApplicationDocumentFormat.docx,
        renderer,
      );
      expect(
        Directory(path).listSync().map((f) => f.uri.pathSegments.last).toSet(),
        {'resume.docx', 'cover letter.docx'},
      );
      final archive = ZipDecoder().decodeBytes(
        await File('$path/resume.docx').readAsBytes(),
      );
      final xml = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(xml, contains('systems &amp; supported'));
      expect(xml, isNot(contains('facts:')));
      await File('$path/leftover.txt').writeAsString('old');
      await Directory('$path/old-subdir').create();
      await exporter.export(
        markdown,
        markdown,
        ResumeTemplateSettings.defaults(),
        ApplicationDocumentFormat.pdf,
        renderer,
      );
      expect(
        Directory(path).listSync().map((f) => f.uri.pathSegments.last).toSet(),
        {'resume.pdf', 'cover letter.pdf'},
      );
      expect(
        ascii.decode(
          (await File('$path/resume.pdf').readAsBytes()).take(5).toList(),
        ),
        '%PDF-',
      );
      await expectLater(
        exporter.export(
          markdown,
          markdown,
          ResumeTemplateSettings.defaults(),
          ApplicationDocumentFormat.pdf,
          ApplicationDocumentRenderer(),
        ),
        throwsStateError,
      );
      expect(Directory(path).listSync(), isEmpty);
      expect(await sibling.readAsString(), 'keep');
      expect(await oldFile.readAsString(), 'old export');
    },
  );
  test('never follows a shared-output directory symlink', () async {
    if (Platform.isWindows) return;
    final dir = await Directory.systemTemp.createTemp(
      'careershopper-export-link-',
    );
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/keep').create();
    final sentinel = File('${dir.path}/keep/keep.txt');
    await sentinel.writeAsString('keep');
    await Directory('${dir.path}/Documents').create();
    await Link(
      '${dir.path}/Documents/CareerShopper',
    ).create('${dir.path}/keep');
    await expectLater(
      ApplicationExporter(dir).export(
        markdown,
        markdown,
        ResumeTemplateSettings.defaults(),
        ApplicationDocumentFormat.docx,
        ApplicationDocumentRenderer(),
      ),
      throwsStateError,
    );
    expect(await sentinel.readAsString(), 'keep');
  });
}
