class MaterialSpan {
  const MaterialSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.marker = false,
  });
  final String text;
  final bool bold, italic, marker;
}

/// Shared inline vocabulary; retaining hidden markers preserves editor offsets.
List<MaterialSpan> parseMaterialInline(
  String text, {
  bool includeMarkers = false,
}) {
  final spans = <MaterialSpan>[];
  var bold = false, italic = false;
  for (final match in RegExp(r'\*{1,3}|[^*]+').allMatches(text)) {
    final part = match.group(0)!;
    if (part.startsWith('*')) {
      if (includeMarkers) spans.add(MaterialSpan(part, marker: true));
      if (part.length >= 2) bold = !bold;
      if (part.length.isOdd) italic = !italic;
    } else {
      spans.add(MaterialSpan(part, bold: bold, italic: italic));
    }
  }
  if (!includeMarkers && (bold || italic)) {
    throw const FormatException('Close each bold (**) or italic (*) marker.');
  }
  return spans;
}

class MaterialBlock {
  const MaterialBlock(
    this.text,
    this.level,
    this.bullet,
    this.factIds, {
    this.pageBreak = false,
    this.metadataSubtitle = false,
  });
  final String text;
  final int level;
  final bool bullet, pageBreak, metadataSubtitle;
  final List<String> factIds;
  List<MaterialSpan> get spans => parseMaterialInline(text);
  String get plainText => spans.map((span) => span.text).join();
  // Explicit emphasis in an H3 chooses which parts of the heading are bold.
  bool get hasExplicitHeadingWeight =>
      level == 3 && spans.any((span) => span.bold);
}

class MaterialDocument {
  MaterialDocument(this.blocks, this.metadata, this.metadataFactIds);
  final List<MaterialBlock> blocks;
  final Map<String, String> metadata;
  final List<String> metadataFactIds;
  bool? get pageNumbers => switch (metadata['page_numbers']) {
    'true' => true,
    'false' => false,
    _ => null,
  };
  String get footer => metadata['footer'] ?? blocks.first.plainText;

  String toMarkdown() {
    final values = {...metadata};
    for (final block in blocks.where((b) => b.metadataSubtitle)) {
      values['subtitle'] = block.text;
    }
    return [
      if (values.isNotEmpty)
        '---\n${values.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n---${metadataFactIds.isEmpty ? '' : ' <!-- facts: ${metadataFactIds.join(', ')} -->'}',
      for (final b in blocks.where((b) => !b.metadataSubtitle))
        if (b.pageBreak)
          '<!-- pagebreak -->'
        else
          '${b.level > 0
              ? '${'#' * b.level} '
              : b.bullet
              ? '- '
              : ''}${b.text.replaceAll('\n', '  \n')} <!-- facts: ${b.factIds.join(', ')} -->',
    ].join('\n\n');
  }
}

List<MaterialBlock> parseMaterialMarkdown(String markdown) =>
    parseMaterialDocument(markdown).blocks;

MaterialDocument parseMaterialDocument(String markdown) {
  if (markdown.trim().isEmpty || markdown.length > 100000) {
    throw const FormatException('Documents must contain 1–100,000 characters.');
  }
  var source = markdown.replaceAll('\r\n', '\n').trim();
  final metadata = <String, String>{};
  var metadataIds = <String>[];
  if (source.startsWith('---\n')) {
    final header = RegExp(
      r'^---\n([\s\S]*?)\n---(?:[ \t]+<!-- facts: ([a-zA-Z0-9_, -]+) -->)?(?:\n|$)',
    ).firstMatch(source);
    if (header == null) {
      throw const FormatException(
        'Close frontmatter with --- on its own line.',
      );
    }
    for (final line in header.group(1)!.split('\n')) {
      final separator = line.indexOf(':');
      if (separator < 1) {
        throw const FormatException('Use simple key: value frontmatter.');
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (!{
            'document_type',
            'subtitle',
            'footer',
            'page_numbers',
          }.contains(key) ||
          metadata.containsKey(key) ||
          value.isEmpty ||
          RegExp(r'[<>`*\[\]{}]').hasMatch(value)) {
        throw const FormatException(
          'Unsupported, repeated, or invalid frontmatter field.',
        );
      }
      metadata[key] = value;
    }
    if (metadata.containsKey('document_type') &&
        !{'resume', 'cover_letter'}.contains(metadata['document_type'])) {
      throw const FormatException(
        'document_type must be resume or cover_letter.',
      );
    }
    if (metadata.containsKey('page_numbers') &&
        !{'true', 'false'}.contains(metadata['page_numbers'])) {
      throw const FormatException('page_numbers must be true or false.');
    }
    metadataIds = _factIds(header.group(2) ?? '');
    if (metadata.containsKey('subtitle') && metadataIds.isEmpty) {
      throw const FormatException(
        'Subtitle frontmatter needs a facts comment after its closing --- line.',
      );
    }
    source = source.substring(header.end).trim();
  }
  final blocks = <MaterialBlock>[];
  // A citation closes its block even when adjacent bullets omit a blank line.
  source = source.replaceAllMapped(
    RegExp(r'(<!-- facts: [a-zA-Z0-9_, -]+ -->)[ \t]*\n(?![ \t]*\n)'),
    (match) => '${match.group(1)}\n\n',
  );
  var blockNumber = 0;
  for (final raw in source.split(RegExp(r'\n\s*\n'))) {
    blockNumber++;
    try {
      if (raw.trim() == '<!-- pagebreak -->') {
        if (blocks.isEmpty || blocks.last.pageBreak) {
          throw const FormatException(
            'Place page breaks between content blocks.',
          );
        }
        blocks.add(const MaterialBlock('', 0, false, [], pageBreak: true));
        continue;
      }
      final match = RegExp(
        r'\s*<!-- facts: ([a-zA-Z0-9_, -]+) -->\s*$',
      ).firstMatch(raw);
      if (match == null) {
        throw const FormatException(
          'Each paragraph, heading, or bullet needs its supporting facts comment: <!-- facts: revision-id -->',
        );
      }
      final text = raw.substring(0, match.start).trim();
      if (text.isEmpty ||
          RegExp(r'[<>`|]').hasMatch(text) ||
          RegExp(r'!?\[[^\]]*\]\(').hasMatch(text)) {
        throw const FormatException(
          'Use headings, paragraphs, bullets, bold and italic text. No HTML, code, tables, images, or Markdown links. Use commas or middle dots instead of pipes between contact details. Keep trailing facts comments.',
        );
      }
      final heading = RegExp(r'^(#{1,3}) ').firstMatch(text);
      final bullet = text.startsWith('- ');
      final content = text.substring(heading?.end ?? (bullet ? 2 : 0));
      if (content.trim().isEmpty || RegExp(r'^#{4,}|^\d+\. ').hasMatch(text)) {
        throw const FormatException(
          'Use #, ##, ### headings, plain paragraphs, or - bullets.',
        );
      }
      final ids = _factIds(match.group(1)!);
      if (ids.isEmpty) {
        throw const FormatException(
          'Each block needs at least one supporting fact revision.',
        );
      }
      if (content
          .split('\n')
          .skip(1)
          .any((line) => RegExp(r'^(#|- )').hasMatch(line))) {
        throw const FormatException(
          'Separate headings and individual bullets with blank lines and a facts comment.',
        );
      }
      final normalized = content.replaceAllMapped(
        RegExp(r'( *)\n'),
        (m) => m.group(1)!.length >= 2 ? '\n' : ' ',
      );
      if (parseMaterialInline(
        normalized,
      ).map((s) => s.text).join().trim().isEmpty) {
        throw const FormatException('Formatting must contain visible text.');
      }
      blocks.add(
        MaterialBlock(normalized, heading?.group(1)?.length ?? 0, bullet, ids),
      );
    } on FormatException catch (error) {
      throw FormatException('Block $blockNumber: ${error.message}');
    }
  }
  if (blocks.isEmpty || blocks.last.pageBreak) {
    throw const FormatException('Documents must end with content.');
  }
  if (metadata.isNotEmpty && blocks.first.level != 1) {
    throw const FormatException(
      'Frontmatter must be followed by the applicant name as H1.',
    );
  }
  if (metadata.containsKey('footer') &&
      metadata['footer'] != blocks.first.plainText) {
    throw const FormatException(
      'The footer must match the applicant name heading.',
    );
  }
  if (metadata.containsKey('subtitle')) {
    blocks.insert(
      1,
      MaterialBlock(
        metadata['subtitle']!,
        3,
        false,
        metadataIds,
        metadataSubtitle: true,
      ),
    );
  }
  return MaterialDocument(blocks, metadata, metadataIds);
}

List<String> _factIds(String value) => value
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList();
