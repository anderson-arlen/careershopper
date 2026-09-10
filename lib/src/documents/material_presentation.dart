import '../storage/document_template_repository.dart';
import 'material_markdown.dart';

/// Ported from the pipeline's final renderer, with no runtime dependency on it.
class MaterialPresentation {
  MaterialPresentation(
    List<MaterialBlock> blocks,
    int index,
    ResumeTemplateSettings s, {
    bool coverLetter = false,
  }) {
    final b = blocks[index];
    // Keep role/project metadata with its heading and the first content lines
    // when there is too little space at a page boundary.
    keepWithNext =
        b.level > 0 ||
        (coverLetter &&
            index == blocks.length - 2 &&
            !b.pageBreak &&
            blocks.last.plainText == blocks.first.plainText) ||
        (index > 0 &&
            blocks[index - 1].level == 3 &&
            b.level == 0 &&
            !b.bullet &&
            !b.pageBreak &&
            b.spans.isNotEmpty &&
            b.spans.every((span) => span.italic || span.text.trim().isEmpty));
    text = b.text;
    size = b.level == 1
        ? s.nameFontSize
        : b.level > 1
        ? s.headingFontSize
        : s.bodyFontSize;
    bold = b.level > 0 && !b.hasExplicitHeadingWeight;
    color = b.level > 1 ? s.accentColor : s.textColor;
    before = b.level > 1 ? 8 : 0;
    after = s.paragraphSpacing;
    rule = b.level == 2 && s.showSectionRules;
    ruleColor = s.accentColor;
    if (s.layout != 'pipeline-v1') return;
    final name = index == 0 && b.level == 1;
    final subtitle = index == 1 && b.level == 3 && blocks.first.level == 1;
    final contact =
        b.level == 0 &&
        !b.bullet &&
        blocks.first.level == 1 &&
        (index == 1 || (index == 2 && blocks[1].level == 3));
    centered = name || subtitle || contact;
    if (name) {
      if (coverLetter) bold = false;
      text = text.toUpperCase();
      color = s.accentColor;
      before = 0;
      after = 1.5;
    } else if (subtitle) {
      text = text.toUpperCase();
      size = coverLetter ? 10.0 : 10.2;
      color = '#405060';
      before = 0;
      after = 2.2;
    } else if (contact) {
      size = 8.5;
      color = '#5A6269';
      after = 5;
      rule = true;
      ruleColor = '#15304A';
      ruleWidth = 1.25;
    } else if (b.level == 2) {
      text = text.toUpperCase();
      before = 7.5;
      after = 3.2;
      ruleColor = '#A9B7C5';
    } else if (b.level == 3) {
      size = 9.9;
      before = 4.5;
      after = 0.8;
    } else if (b.bullet) {
      after = 1.4;
    }
  }
  late String text, color, ruleColor;
  late double size, before, after;
  late bool bold, rule;
  late bool keepWithNext;
  bool centered = false;
  double ruleWidth = 0.5;
}
