// Local renderer smoke test; uses synthetic data and a fresh temporary folder.
import 'dart:io';
import 'package:careershopper/src/documents/application_exporter.dart';
import 'package:careershopper/src/storage/document_template_repository.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('careershopper-render-');
  final renderer = ApplicationDocumentRenderer(
    regularFont: await File('assets/fonts/DejaVuSans.ttf').readAsBytes(),
    boldFont: await File('assets/fonts/DejaVuSans-Bold.ttf').readAsBytes(),
  );
  const resume = '''# Alex Example <!-- facts: identity -->

alex@example.test · Denver, Colorado <!-- facts: identity -->

## Summary <!-- facts: work -->

Backend engineer with experience building reliable services and supporting customer-facing products. <!-- facts: work -->

## Experience <!-- facts: work -->

### Software Engineer — Example Company <!-- facts: work -->

2020–2026 · Remote <!-- facts: work -->

- Built and maintained backend services, improved SQL queries, and collaborated with product teams on customer workflows. <!-- facts: work -->

- Supported production systems and documented incident follow-up work. <!-- facts: work -->

## Education <!-- facts: education -->

Bachelor of Science, Computer Science — Example University <!-- facts: education -->''';
  const cover = '''# Alex Example <!-- facts: identity -->

alex@example.test · Denver, Colorado <!-- facts: identity -->

Dear hiring team, <!-- facts: identity -->

I am interested in the backend engineering position. My experience building services and supporting customer-facing products would help me contribute to your team. <!-- facts: work -->

At Example Company, I maintained backend services, improved SQL queries, and worked with product teams on customer workflows. I also supported production systems and documented incident follow-up work. <!-- facts: work -->

Thank you for considering my application. I would welcome the opportunity to discuss the position. <!-- facts: identity -->

Alex Example <!-- facts: identity -->''';
  for (final format in ApplicationDocumentFormat.values) {
    final path =
        await ApplicationExporter(
          Directory('${root.path}/${format.name}'),
        ).export(
          resume,
          cover,
          ResumeTemplateSettings.defaults(),
          format,
          renderer,
        );
    stdout.writeln(path);
  }
}
