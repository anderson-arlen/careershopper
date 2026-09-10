import 'package:flutter/material.dart';
import '../../documents/material_markdown.dart';

/// Editable rendered blocks. Markdown markers and evidence comments are kept
/// in the backing source, not exposed as employer-facing text.
class EditableMarkdownPreview extends StatefulWidget {
  const EditableMarkdownPreview({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  State<EditableMarkdownPreview> createState() =>
      _EditableMarkdownPreviewState();
}

class _EditableMarkdownPreviewState extends State<EditableMarkdownPreview> {
  late String _source;
  List<MaterialBlock> _blocks = [];
  MaterialDocument? _document;
  final List<TextEditingController> _editors = [];
  String? _error;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EditableMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_source != widget.controller.text) _load();
  }

  void _load() {
    _source = widget.controller.text;
    _revision++;
    try {
      _document = parseMaterialDocument(_source);
      _blocks = _document!.blocks;
      for (final editor in _editors) {
        editor.dispose();
      }
      _editors.clear();
      _editors.addAll(_blocks.map((b) => _InlineController(text: b.text)));
      _error = null;
    } on FormatException catch (e) {
      _error = '${e.message} Use Markdown source to repair it.';
    }
  }

  @override
  void dispose() {
    for (final editor in _editors) {
      editor.dispose();
    }
    super.dispose();
  }

  void _edit(int index, String text) {
    final old = _blocks[index];
    _blocks[index] = MaterialBlock(
      text,
      old.level,
      old.bullet,
      old.factIds,
      metadataSubtitle: old.metadataSubtitle,
    );
    // Editing the name keeps the matching named footer consistent.
    if (index == 0 && _document!.metadata.containsKey('footer')) {
      _document!.metadata['footer'] = parseMaterialInline(
        text,
        includeMarkers: true,
      ).where((span) => !span.marker).map((span) => span.text).join();
    }
    _source = _document!.toMarkdown();
    widget.controller.text = _source;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text(_error!);
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (final (index, block) in _blocks.indexed)
          if (block.pageBreak)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Text('  Page break  '),
                  Expanded(child: Divider()),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (block.bullet)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 8),
                      child: Text('•'),
                    ),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('preview-$_revision-$index'),
                      controller: _editors[index],
                      readOnly: !widget.enabled,
                      maxLines: null,
                      style: block.level == 1
                          ? theme.textTheme.headlineSmall
                          : block.level > 1
                          ? theme.textTheme.titleMedium?.copyWith(
                              fontWeight: block.hasExplicitHeadingWeight
                                  ? FontWeight.normal
                                  : null,
                            )
                          : theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      onChanged: (text) => _edit(index, text),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _InlineController extends TextEditingController {
  _InlineController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => TextSpan(
    style: style,
    children: [
      for (final span in parseMaterialInline(text, includeMarkers: true))
        TextSpan(
          text: span.text,
          style: span.marker
              ? const TextStyle(fontSize: 0, color: Colors.transparent)
              : TextStyle(
                  fontWeight: span.bold ? FontWeight.bold : style?.fontWeight,
                  fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
                ),
        ),
    ],
  );
}
