import 'package:flutter/material.dart';

import '../../storage/document_template_repository.dart';
import '../../storage/profile_repository.dart';
import '../../documents/document_prompt.dart';
import 'writing_style_editor.dart';

class DocumentTemplatesPage extends StatelessWidget {
  const DocumentTemplatesPage({
    required this.templates,
    required this.profile,
    super.key,
  });

  final DocumentTemplateStore templates;
  final ProfileStore profile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ResumeTemplateDefinition?>(
      stream: templates.watchDefaultResumeTemplate(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
              'Unable to load document templates:\n${snapshot.error}',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final template = snapshot.data;
        if (template == null) {
          return const Center(child: Text('No resume template is available.'));
        }
        return StreamBuilder<List<CareerProfileFact>>(
          stream: profile.watchCareerFacts(),
          builder: (context, profileSnapshot) => _ResumeTemplateEditor(
            key: ValueKey(
              '${template.id}-${template.updatedAt}-${template.name}-${template.settings.toJson()}',
            ),
            store: templates,
            template: template,
            identity: _previewIdentity(
              profileSnapshot.data ?? const <CareerProfileFact>[],
            ),
          ),
        );
      },
    );
  }
}

class _ResumeTemplateEditor extends StatefulWidget {
  const _ResumeTemplateEditor({
    required this.store,
    required this.template,
    required this.identity,
    super.key,
  });

  final DocumentTemplateStore store;
  final ResumeTemplateDefinition template;
  final _PreviewIdentity identity;

  @override
  State<_ResumeTemplateEditor> createState() => _ResumeTemplateEditorState();
}

class _ResumeTemplateEditorState extends State<_ResumeTemplateEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _fontFamily;
  late final TextEditingController _nameSize;
  late final TextEditingController _bodySize;
  late final TextEditingController _headingSize;
  late final TextEditingController _lineSpacing;
  late final TextEditingController _paragraphSpacing;
  late final TextEditingController _marginTop;
  late final TextEditingController _marginRight;
  late final TextEditingController _marginBottom;
  late final TextEditingController _marginLeft;
  late final TextEditingController _textColor;
  late final TextEditingController _accentColor;
  late final TextEditingController _sectionOrder;
  late final TextEditingController _generationPrompt;
  late String _paperSize;
  late bool _showSectionRules;
  late bool _pageNumbers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.template.settings;
    _generationPrompt = TextEditingController(text: settings.generationPrompt);
    _name = TextEditingController(text: widget.template.name);
    _fontFamily = TextEditingController(text: settings.fontFamily);
    _nameSize = _numberController(settings.nameFontSize);
    _bodySize = _numberController(settings.bodyFontSize);
    _headingSize = _numberController(settings.headingFontSize);
    _lineSpacing = _numberController(settings.lineSpacing);
    _paragraphSpacing = _numberController(settings.paragraphSpacing);
    _marginTop = _numberController(settings.marginTop);
    _marginRight = _numberController(settings.marginRight);
    _marginBottom = _numberController(settings.marginBottom);
    _marginLeft = _numberController(settings.marginLeft);
    _textColor = TextEditingController(text: settings.textColor);
    _accentColor = TextEditingController(text: settings.accentColor);
    _sectionOrder = TextEditingController(
      text: settings.sectionOrder.join(', '),
    );
    _paperSize = settings.paperSize;
    _showSectionRules = settings.showSectionRules;
    _pageNumbers = settings.pageNumbers;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _fontFamily,
      _nameSize,
      _bodySize,
      _headingSize,
      _lineSpacing,
      _paragraphSpacing,
      _marginTop,
      _marginRight,
      _marginBottom,
      _marginLeft,
      _textColor,
      _accentColor,
      _sectionOrder,
      _generationPrompt,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  ResumeTemplateSettings _settings({bool forgiving = false}) {
    double number(TextEditingController controller, double fallback) =>
        double.tryParse(controller.text.trim()) ?? fallback;
    final fallback = widget.template.settings;
    final sections = _sectionOrder.text
        .split(RegExp(r'[,\n]'))
        .map((item) => item.trim().toLowerCase().replaceAll(' ', '_'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return ResumeTemplateSettings(
      layout: widget.template.settings.layout,
      generationPrompt: _generationPrompt.text,
      paperSize: _paperSize,
      fontFamily: _fontFamily.text.trim().isEmpty
          ? fallback.fontFamily
          : _fontFamily.text.trim(),
      nameFontSize: number(_nameSize, fallback.nameFontSize),
      bodyFontSize: number(_bodySize, fallback.bodyFontSize),
      headingFontSize: number(_headingSize, fallback.headingFontSize),
      lineSpacing: number(_lineSpacing, fallback.lineSpacing),
      paragraphSpacing: number(_paragraphSpacing, fallback.paragraphSpacing),
      marginTop: number(_marginTop, fallback.marginTop),
      marginRight: number(_marginRight, fallback.marginRight),
      marginBottom: number(_marginBottom, fallback.marginBottom),
      marginLeft: number(_marginLeft, fallback.marginLeft),
      textColor: _validHex(_textColor.text)
          ? _textColor.text.trim().toUpperCase()
          : fallback.textColor,
      accentColor: _validHex(_accentColor.text)
          ? _accentColor.text.trim().toUpperCase()
          : fallback.accentColor,
      showSectionRules: _showSectionRules,
      pageNumbers: _pageNumbers,
      sectionOrder: sections.isEmpty && forgiving
          ? fallback.sectionOrder
          : sections,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.store.saveResumeTemplate(
        ResumeTemplateDraft(
          id: widget.template.id,
          name: _name.text,
          settings: _settings(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Resume template saved.')));
      }
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _usePipeline() async {
    setState(() => _saving = true);
    try {
      await widget.store.saveResumeTemplate(
        ResumeTemplateDraft(
          id: widget.template.id,
          name: 'Pipeline Classic',
          settings: ResumeTemplateSettings.fromJson({
            ...ResumeTemplateSettings.defaults().toJson(),
            'generation_prompt': _generationPrompt.text,
          }),
        ),
      );
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset resume template?'),
        content: const Text(
          'Typography, spacing, margins, colors, and section order will return to the ATS Plain defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset template'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.store.resetResumeTemplate(widget.template.id);
    } on Object catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document templates',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'AI supplies restricted Markdown content. CareerShopper owns the reusable document presentation.',
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _usePipeline,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Use pipeline template'),
              ),
              TextButton.icon(
                onPressed: _saving ? null : _reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset defaults'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save template'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Card.filled(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('Resume template · ATS-safe single-column layout'),
              subtitle: Text(
                'The preview reflects these reusable settings. Generated Markdown remains separately reviewable and reproducible.',
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final settings = _settings(forgiving: true);
              final form = _settingsForm();
              final preview = _ResumePreview(
                settings: settings,
                identity: widget.identity,
              );
              if (constraints.maxWidth < 920) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  children: [preview, const SizedBox(height: 16), form],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 12, 32),
                      child: form,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 24, 32),
                      child: preview,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _settingsForm() {
    final letter = _settings(forgiving: true).forCoverLetter();
    return Form(
      key: _formKey,
      onChanged: () => setState(() {}),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Template settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Cover letter export: ${letter.bodyFontSize} pt body, '
                '${letter.lineSpacing} line spacing, ${letter.paragraphSpacing} pt paragraph spacing; '
                '${letter.marginTop}/${letter.marginRight}/${letter.marginBottom}/${letter.marginLeft} inch margins (top/right/bottom/left). '
                'Pipeline letter defaults replace untouched resume values; customized values are retained. '
                'Letters omit page numbering unless explicitly enabled in Markdown frontmatter.',
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('Document generation prompt'),
                subtitle: const Text(
                  'Document structure; shared voice and prose rules are edited separately below',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _generationPrompt.text =
                                  defaultDocumentGenerationPrompt,
                            ),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset prompt to default'),
                    ),
                  ),
                  TextFormField(
                    controller: _generationPrompt,
                    minLines: 10,
                    maxLines: 20,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Generation prompt',
                      helperText:
                          'Use Save template to save prompt edits or a reset. Applies to the next generation or regeneration; existing drafts stay unchanged.',
                      helperMaxLines: 3,
                    ),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            value.length > 20000
                        ? 'Enter 1–20,000 characters.'
                        : null,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Factual-support rules and the restricted Markdown/MCP format are fixed and cannot be disabled by this prompt.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const WritingStyleEditor(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Template name'),
                validator: _required,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _paperSize,
                      decoration: const InputDecoration(
                        labelText: 'Paper size',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'letter',
                          child: Text('US Letter'),
                        ),
                        DropdownMenuItem(value: 'a4', child: Text('A4')),
                      ],
                      onChanged: (value) => setState(() => _paperSize = value!),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: TextFormField(
                      controller: _fontFamily,
                      decoration: const InputDecoration(
                        labelText: 'Font family',
                      ),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Typography',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _numberFields([
                (_nameSize, 'Name size', 6.0, 36.0, 'pt'),
                (_bodySize, 'Body size', 6.0, 36.0, 'pt'),
                (_headingSize, 'Heading size', 6.0, 36.0, 'pt'),
                (_lineSpacing, 'Line spacing', 0.8, 2.0, '×'),
                (_paragraphSpacing, 'Paragraph spacing', 0.0, 24.0, 'pt'),
              ]),
              const SizedBox(height: 20),
              Text('Margins', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _numberFields([
                (_marginTop, 'Top', 0.25, 2.0, 'in'),
                (_marginRight, 'Right', 0.25, 2.0, 'in'),
                (_marginBottom, 'Bottom', 0.25, 2.0, 'in'),
                (_marginLeft, 'Left', 0.25, 2.0, 'in'),
              ]),
              const SizedBox(height: 20),
              Text('Color', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _colorField(_textColor, 'Text color'),
                  _colorField(_accentColor, 'Accent color'),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _sectionOrder,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Section order',
                  helperText:
                      'Comma-separated: summary, direct_match, skills, experience, projects, education, patents, publications. Omitted empty sections stay hidden.',
                  alignLabelWithHint: true,
                ),
                validator: _sectionOrderValidator,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Section divider rules'),
                value: _showSectionRules,
                onChanged: (value) => setState(() => _showSectionRules = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Page numbers on multi-page resumes'),
                value: _pageNumbers,
                onChanged: (value) => setState(() => _pageNumbers = value),
              ),
              const Divider(height: 28),
              Text(
                'Template ${widget.template.id} · Format v${widget.template.formatVersion}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberFields(
    List<(TextEditingController, String, double, double, String)> fields,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final field in fields)
          SizedBox(
            width: 132,
            child: TextFormField(
              controller: field.$1,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: field.$2,
                suffixText: field.$5,
              ),
              validator: (value) => _numberRange(value, field.$3, field.$4),
            ),
          ),
      ],
    );
  }

  Widget _colorField(TextEditingController controller, String label) {
    return SizedBox(
      width: 210,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _color(controller.text, Colors.black),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        validator: (value) => _validHex(value ?? '') ? null : 'Use #RRGGBB',
      ),
    );
  }
}

class _ResumePreview extends StatelessWidget {
  const _ResumePreview({required this.settings, required this.identity});

  final ResumeTemplateSettings settings;
  final _PreviewIdentity identity;

  @override
  Widget build(BuildContext context) {
    final ratio = settings.paperSize == 'a4' ? 210 / 297 : 8.5 / 11;
    final accent = _color(settings.accentColor, const Color(0xff15304A));
    final text = _color(settings.textColor, const Color(0xff191C1F));
    final pageWidth = 510.0;
    final pageHeight = pageWidth / ratio;
    final horizontalScale = pageWidth / 8.5;
    final verticalScale = pageHeight / 11;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Layout preview',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              settings.paperSize == 'a4' ? 'A4' : 'US Letter',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: ratio,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Container(
                  width: pageWidth,
                  height: pageHeight,
                  padding: EdgeInsets.fromLTRB(
                    settings.marginLeft * horizontalScale,
                    settings.marginTop * verticalScale,
                    settings.marginRight * horizontalScale,
                    settings.marginBottom * verticalScale,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xffd8d8d8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: text,
                      fontFamily: settings.fontFamily,
                      fontSize: settings.bodyFontSize,
                      height: settings.lineSpacing,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          (identity.name ?? 'YOUR NAME').toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontFamily: settings.fontFamily,
                            fontSize: settings.nameFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          identity.contactLine ??
                              'Contact details from saved resume content',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xff555555),
                          ),
                        ),
                        SizedBox(height: settings.paragraphSpacing + 5),
                        for (final section in settings.sectionOrder.take(
                          5,
                        )) ...[
                          _PreviewSection(
                            label: _humanize(section).toUpperCase(),
                            accent: accent,
                            headingSize: settings.headingFontSize,
                            showRule: settings.showSectionRules,
                            paragraphSpacing: settings.paragraphSpacing,
                          ),
                        ],
                        const Spacer(),
                        if (settings.pageNumbers)
                          Text(
                            '${identity.name ?? 'Your name'} · Page 1 of 2',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 7,
                              color: Color(0xff777777),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.label,
    required this.accent,
    required this.headingSize,
    required this.showRule,
    required this.paragraphSpacing,
  });

  final String label;
  final Color accent;
  final double headingSize;
  final bool showRule;
  final double paragraphSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: paragraphSpacing + 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: headingSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (showRule) Divider(height: 4, thickness: 0.7, color: accent),
          const SizedBox(height: 2),
          Container(height: 5, color: const Color(0xffd6d9dc)),
          const SizedBox(height: 4),
          FractionallySizedBox(
            widthFactor: 0.82,
            alignment: Alignment.centerLeft,
            child: Container(height: 5, color: const Color(0xffe1e3e5)),
          ),
        ],
      ),
    );
  }
}

class _PreviewIdentity {
  const _PreviewIdentity({required this.name, required this.contactValues});

  final String? name;
  final List<String> contactValues;

  String? get contactLine =>
      contactValues.isEmpty ? null : contactValues.join(' · ');
}

_PreviewIdentity _previewIdentity(List<CareerProfileFact> facts) {
  final saved = facts
      .where((f) => f.kind == 'resume_content' && f.canDiscloseInApplications)
      .firstOrNull;
  final value = saved?.value;
  final header = value is Map ? value['header'] : null;
  return _PreviewIdentity(
    name: header is Map ? header['name'] as String? : null,
    contactValues: [
      if (header is Map && header['contact'] is String)
        header['contact'] as String,
    ],
  );
}

TextEditingController _numberController(double value) => TextEditingController(
  text: value == value.roundToDouble() ? value.toInt().toString() : '$value',
);

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _numberRange(String? value, double minimum, double maximum) {
  final number = double.tryParse(value?.trim() ?? '');
  if (number == null || number < minimum || number > maximum) {
    return '$minimum–$maximum';
  }
  return null;
}

String? _sectionOrderValidator(String? value) {
  const allowed = {
    'summary',
    'direct_match',
    'skills',
    'experience',
    'projects',
    'education',
    'patents',
    'publications',
  };
  final sections = (value ?? '')
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim().toLowerCase().replaceAll(' ', '_'))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (sections.isEmpty) return 'Include at least one section';
  if (sections.toSet().length != sections.length) return 'Remove duplicates';
  if (sections.any((section) => !allowed.contains(section))) {
    return 'Use only the supported sections listed below';
  }
  return null;
}

bool _validHex(String value) =>
    RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value.trim());

Color _color(String value, Color fallback) {
  if (!_validHex(value)) return fallback;
  return Color(int.parse('FF${value.trim().substring(1)}', radix: 16));
}

String _humanize(String value) {
  final spaced = value.replaceAll('_', ' ');
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
