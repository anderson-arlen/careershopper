import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../storage/document_template_repository.dart';
import 'material_markdown.dart';
import 'material_presentation.dart';

enum ApplicationDocumentFormat { docx, pdf }

class ApplicationDocumentRenderer {
  ApplicationDocumentRenderer({
    this.regularFont,
    this.boldFont,
    this.italicFont,
    this.boldItalicFont,
  });
  final Uint8List? regularFont;
  final Uint8List? boldFont;
  final Uint8List? italicFont, boldItalicFont;

  Future<List<int>> render(
    String markdown,
    ResumeTemplateSettings settings,
    ApplicationDocumentFormat format, {
    bool? coverLetter,
  }) async {
    final document = parseMaterialDocument(markdown);
    final isLetter =
        coverLetter ?? document.metadata['document_type'] == 'cover_letter';
    final effective = ResumeTemplateSettings.fromJson({
      ...(isLetter ? settings.forCoverLetter() : settings).toJson(),
      if (document.pageNumbers != null) 'page_numbers': document.pageNumbers,
    });
    return format == ApplicationDocumentFormat.docx
        ? _docx(document.blocks, effective, isLetter)
        : _pdf(document.blocks, effective, isLetter);
  }

  Future<List<int>> _pdf(
    List<MaterialBlock> blocks,
    ResumeTemplateSettings s,
    bool coverLetter,
  ) async {
    if (regularFont == null || boldFont == null) {
      throw StateError('PDF fonts are unavailable.');
    }
    final regular = pw.Font.ttf(ByteData.sublistView(regularFont!));
    final bold = pw.Font.ttf(ByteData.sublistView(boldFont!));
    final hasItalics = blocks.any((b) => b.spans.any((span) => span.italic));
    if (hasItalics && (italicFont == null || boldItalicFont == null)) {
      throw StateError('Italic PDF fonts are unavailable.');
    }
    final italic = italicFont == null
        ? regular
        : pw.Font.ttf(ByteData.sublistView(italicFont!));
    final boldItalic = boldItalicFont == null
        ? bold
        : pw.Font.ttf(ByteData.sublistView(boldItalicFont!));
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: s.paperSize == 'a4'
            ? PdfPageFormat.a4
            : PdfPageFormat.letter,
        margin: pw.EdgeInsets.fromLTRB(
          s.marginLeft * 72,
          s.marginTop * 72,
          s.marginRight * 72,
          s.marginBottom * 72,
        ),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
          italic: italic,
          boldItalic: boldItalic,
        ),
        footer: s.pageNumbers
            ? (context) => pw.Align(
                alignment: s.layout == 'pipeline-v1'
                    ? pw.Alignment.center
                    : pw.Alignment.centerRight,
                child: pw.Text(
                  s.layout == 'pipeline-v1'
                      ? '${blocks.first.plainText} · Page ${context.pageNumber} of ${context.pagesCount}'
                      : '${context.pageNumber}',
                  style: pw.TextStyle(font: regular, fontSize: 8),
                ),
              )
            : null,
        build: (_) {
          final widgets = <pw.Widget>[];
          for (var index = 0; index < blocks.length; index++) {
            if (blocks[index].pageBreak) {
              widgets.add(pw.NewPage());
              continue;
            }
            // Measure the actual heading/metadata/content group rather than
            // guessing remaining space from a fixed line count.
            final group = <pw.Widget>[];
            while (index + 1 < blocks.length &&
                !blocks[index + 1].pageBreak &&
                MaterialPresentation(
                  blocks,
                  index,
                  s,
                  coverLetter: coverLetter,
                ).keepWithNext) {
              group.add(
                _pdfBlock(blocks, index++, s, regular, bold, coverLetter),
              );
            }
            group.add(_pdfBlock(blocks, index, s, regular, bold, coverLetter));
            widgets.add(
              pw.Inseparable(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: group,
                ),
              ),
            );
          }
          return widgets;
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfBlock(
    List<MaterialBlock> blocks,
    int index,
    ResumeTemplateSettings s,
    pw.Font regular,
    pw.Font bold,
    bool coverLetter,
  ) {
    final block = blocks[index];
    final style = MaterialPresentation(
      blocks,
      index,
      s,
      coverLetter: coverLetter,
    );
    final text = pw.RichText(
      text: pw.TextSpan(
        children: [
          for (final span in parseMaterialInline(style.text))
            pw.TextSpan(
              text: span.text,
              style: pw.TextStyle(
                fontWeight: style.bold || span.bold
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                fontStyle: span.italic
                    ? pw.FontStyle.italic
                    : pw.FontStyle.normal,
              ),
            ),
        ],
        style: pw.TextStyle(
          fontSize: style.size,
          color: PdfColor.fromHex(style.color),
          lineSpacing: s.bodyFontSize * (s.lineSpacing - 1),
        ),
      ),
      textAlign: style.centered ? pw.TextAlign.center : pw.TextAlign.left,
    );
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: style.before, bottom: style.after),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (block.bullet)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 9.36),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 10.08,
                    child: pw.Text(
                      '•',
                      style: pw.TextStyle(font: regular, fontSize: style.size),
                    ),
                  ),
                  pw.Expanded(child: text),
                ],
              ),
            )
          else
            text,
          if (style.rule)
            pw.Divider(
              color: PdfColor.fromHex(style.ruleColor),
              thickness: style.ruleWidth,
              height: 2,
            ),
        ],
      ),
    );
  }

  List<int> _docx(
    List<MaterialBlock> blocks,
    ResumeTemplateSettings s,
    bool coverLetter,
  ) {
    String xml(String value) => const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(
        ArchiveFile(name, bytes.length, bytes)..lastModTime = 946684800,
      );
    }

    add(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/word/footer.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/></Types>''',
    );
    add(
      '_rels/.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    );
    add(
      'word/_rels/document.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="numbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="footer" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer.xml"/></Relationships>',
    );
    add(
      'word/styles.xml',
      '''<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="${xml(s.fontFamily)}" w:hAnsi="${xml(s.fontFamily)}"/><w:sz w:val="${(s.bodyFontSize * 2).round()}"/><w:color w:val="${s.textColor.substring(1)}"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="${(s.paragraphSpacing * 20).round()}" w:line="${(s.lineSpacing * 240).round()}" w:lineRule="auto"/><w:widowControl/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/></w:pPr><w:rPr><w:b/><w:sz w:val="${(s.nameFontSize * 2).round()}"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="160"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="${(s.headingFontSize * 2).round()}"/><w:color w:val="${s.accentColor.substring(1)}"/></w:rPr></w:style></w:styles>''',
    );
    add(
      'word/numbering.xml',
      '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="240" w:hanging="180"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>',
    );
    final pipeline = s.layout == 'pipeline-v1';
    add(
      'word/footer.xml',
      '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:jc w:val="${pipeline ? 'center' : 'right'}"/><w:rPr><w:sz w:val="15"/></w:rPr></w:pPr>${pipeline ? '<w:r><w:rPr><w:sz w:val="15"/></w:rPr><w:t xml:space="preserve">${xml(blocks.first.plainText)} · Page </w:t></w:r>' : ''}<w:fldSimple w:instr="PAGE"><w:r><w:rPr><w:sz w:val="15"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>${pipeline ? '<w:r><w:rPr><w:sz w:val="15"/></w:rPr><w:t xml:space="preserve"> of </w:t></w:r><w:fldSimple w:instr="NUMPAGES"><w:r><w:rPr><w:sz w:val="15"/></w:rPr><w:t>1</w:t></w:r></w:fldSimple>' : ''}</w:p></w:ftr>',
    );
    final paragraphs = blocks.indexed.map((entry) {
      final (index, b) = entry;
      if (b.pageBreak) return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
      final style = MaterialPresentation(
        blocks,
        index,
        s,
        coverLetter: coverLetter,
      );
      final runs = parseMaterialInline(style.text).map((span) {
        final content = span.text
            .split('\n')
            .map((line) => '<w:t xml:space="preserve">${xml(line)}</w:t>')
            .join('<w:br/>');
        return '<w:r><w:rPr>${style.bold || span.bold ? '<w:b/>' : ''}${span.italic ? '<w:i/>' : ''}<w:sz w:val="${(style.size * 2).round()}"/><w:color w:val="${style.color.substring(1)}"/></w:rPr>$content</w:r>';
      }).join();
      return '<w:p><w:pPr><w:pStyle w:val="Normal"/><w:jc w:val="${style.centered ? 'center' : 'left'}"/><w:spacing w:before="${(style.before * 20).round()}" w:after="${(style.after * 20).round()}"/>${style.keepWithNext ? '<w:keepNext/>' : ''}${b.level > 0 ? '<w:outlineLvl w:val="${b.level - 1}"/>' : ''}${b.bullet ? '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr><w:ind w:left="389" w:hanging="202"/>' : ''}${style.rule ? '<w:pBdr><w:bottom w:val="single" w:space="1" w:sz="${(style.ruleWidth * 8).round()}" w:color="${style.ruleColor.substring(1)}"/></w:pBdr>' : ''}</w:pPr>$runs</w:p>';
    }).join();
    add(
      'word/document.xml',
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>$paragraphs<w:sectPr>${s.pageNumbers ? '<w:footerReference w:type="default" r:id="footer"/>' : ''}<w:pgSz w:w="${s.paperSize == 'a4' ? 11906 : 12240}" w:h="${s.paperSize == 'a4' ? 16838 : 15840}"/><w:pgMar w:top="${(s.marginTop * 1440).round()}" w:right="${(s.marginRight * 1440).round()}" w:bottom="${(s.marginBottom * 1440).round()}" w:left="${(s.marginLeft * 1440).round()}" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr></w:body></w:document>',
    );
    return ZipEncoder().encode(archive);
  }
}

/// One app-owned export destination shared by every application.
class ApplicationExporter {
  ApplicationExporter(this.homeDirectory);
  final Directory homeDirectory;
  static bool _busy = false;
  String get outputPath =>
      p.join(homeDirectory.path, 'Documents', 'CareerShopper');

  Future<String> export(
    String resume,
    String coverLetter,
    ResumeTemplateSettings settings,
    ApplicationDocumentFormat format,
    ApplicationDocumentRenderer renderer,
  ) async {
    if (_busy) throw StateError('Another application export is in progress.');
    _busy = true;
    try {
      parseMaterialMarkdown(resume);
      parseMaterialMarkdown(coverLetter);
      final output = Directory(outputPath);
      await output.parent.create(recursive: true);
      final type = await FileSystemEntity.type(output.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError(
          'The application output path must be a real directory, not a symbolic link.',
        );
      }
      await output.create();
      // Only this fixed app-owned directory is cleared, never a user-selected
      // folder. Links are removed themselves, not followed to their targets.
      await for (final entry in output.list(followLinks: false)) {
        await entry.delete(recursive: entry is Directory);
      }
      final files = <File>[];
      try {
        for (final (name, markdown) in [
          ('resume', resume),
          ('cover letter', coverLetter),
        ]) {
          final bytes = await renderer.render(
            markdown,
            settings,
            format,
            coverLetter: name == 'cover letter',
          );
          final file = File(p.join(output.path, '$name.${format.name}'));
          files.add(file);
          await file.writeAsBytes(bytes, flush: true);
        }
      } on Object {
        for (final file in files) {
          if (await file.exists()) await file.delete();
        }
        rethrow;
      }
      return output.path;
    } finally {
      _busy = false;
    }
  }
}
