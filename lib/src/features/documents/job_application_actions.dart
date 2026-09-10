import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/job.dart';
import '../../documents/application_exporter.dart';
import '../../platform/external_url_launcher.dart';
import '../../storage/ai_harness_repository.dart';
import '../../storage/application_material_repository.dart';
import '../../storage/job_repository.dart';

/// The job-level application action, independent of which detail tab is open.
class JobApplicationActions extends StatefulWidget {
  const JobApplicationActions({
    super.key,
    required this.job,
    required this.harnesses,
    required this.dirty,
    this.onApprove,
    this.secondaryActions = const [],
    required this.onBusyChanged,
    required this.repository,
    required this.onChanged,
    this.openUrl = openExternalUrl,
  });
  final InboxJob job;
  final AiHarnessStore harnesses;
  final bool dirty;
  final VoidCallback? onApprove;
  final List<Widget> secondaryActions;
  final ValueChanged<bool> onBusyChanged;
  final JobStore repository;
  final Future<void> Function() onChanged;
  final Future<void> Function(Uri) openUrl;
  @override
  State<JobApplicationActions> createState() => _JobApplicationActionsState();
}

class _JobApplicationActionsState extends State<JobApplicationActions> {
  late final _materials = widget.harnesses.watchMaterials(widget.job.id);
  late final _status = widget.harnesses.watchMaterialStatus(widget.job.id);
  var _format = ApplicationDocumentFormat.docx;
  var _busy = false;
  String? _output;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    widget.onBusyChanged(true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  Future<void> _export(
    ApplicationMaterials draft, {
    required bool openListing,
  }) async {
    var changed = false;
    await _run(() async {
      final url = widget.job.applicationUrl;
      if (openListing && url == null) {
        throw StateError('This job has no listing URL.');
      }
      Uint8List? regular, bold, italic, boldItalic;
      if (_format == ApplicationDocumentFormat.pdf) {
        regular = (await rootBundle.load(
          'assets/fonts/DejaVuSans.ttf',
        )).buffer.asUint8List();
        bold = (await rootBundle.load(
          'assets/fonts/DejaVuSans-Bold.ttf',
        )).buffer.asUint8List();
        italic = (await rootBundle.load(
          'assets/fonts/DejaVuSans-Oblique.ttf',
        )).buffer.asUint8List();
        boldItalic = (await rootBundle.load(
          'assets/fonts/DejaVuSans-BoldOblique.ttf',
        )).buffer.asUint8List();
      }
      final output = await widget.harnesses.exportApplication(
        widget.job.id,
        draft.id,
        _format,
        ApplicationDocumentRenderer(
          regularFont: regular,
          boldFont: bold,
          italicFont: italic,
          boldItalicFont: boldItalic,
        ),
      );
      if (mounted) setState(() => _output = output);
      if (openListing) {
        await widget.openUrl(url!);
        if (mounted) changed = await _confirmCompletion();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Files exported to $output. No listing opened or application status changed.',
            ),
          ),
        );
      }
    });
    if (changed && mounted) await widget.onChanged();
  }

  Future<bool> _confirmCompletion() async {
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Did you complete the application?'),
        content: Text(
          'Complete the application for ${widget.job.title} in your browser, then answer here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, applied'),
          ),
        ],
      ),
    );
    if (!mounted || completed == null) return false;
    if (completed) {
      await widget.repository.setApplicationStatus(
        widget.job.id,
        ApplicationStatus.applied,
        actor: 'user',
        origin: 'desktop_ui',
      );
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this job listing?'),
        content: const Text(
          'The listing will be retained as discarded. It will not be marked applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep job'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard job'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return false;
    await widget.repository.setReviewState(
      widget.job.id,
      ReviewState.discarded,
      actor: 'user',
      origin: 'desktop_ui',
    );
    return true;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: _status,
    builder: (context, status) => StreamBuilder<ApplicationMaterials?>(
      stream: _materials,
      builder: (context, materials) {
        final draft = materials.data;
        final loading =
            status.connectionState == ConnectionState.waiting ||
            materials.connectionState == ConnectionState.waiting;
        final error = status.hasError || materials.hasError;
        final generating = status.data == 'running';
        final approved = widget.job.reviewState == ReviewState.approved;
        final ready =
            !loading &&
            !error &&
            approved &&
            !generating &&
            !widget.dirty &&
            draft != null;
        final canApply =
            ready &&
            widget.job.applicationUrl != null &&
            widget.job.availability != JobAvailability.closed &&
            widget.job.applicationOutcome == ApplicationOutcome.active &&
            widget.job.applicationStatus.index <
                ApplicationStatus.applied.index;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onApprove != null)
                  FilledButton.icon(
                    onPressed: _busy ? null : widget.onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                if (canApply && widget.onApprove == null)
                  Tooltip(
                    message:
                        'Export the saved resume and cover letter, open the listing, then confirm whether you completed the application. Document review is optional.',
                    child: FilledButton.icon(
                      onPressed:
                          ready && !_busy && widget.job.applicationUrl != null
                          ? () => _export(draft, openListing: true)
                          : null,
                      icon: const Icon(Icons.open_in_new),
                      label: Text(_busy ? 'Preparing files…' : 'Apply'),
                    ),
                  ),
                Tooltip(
                  message:
                      'Export the saved resume and cover letter without opening the listing or changing application status. Replaces all files in ~/Documents/CareerShopper. Review is optional.',
                  child: OutlinedButton.icon(
                    onPressed: ready && !_busy
                        ? () => _export(draft, openListing: false)
                        : null,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export documents'),
                  ),
                ),
                PopupMenuButton<ApplicationDocumentFormat>(
                  tooltip: 'Application file format',
                  enabled: !_busy,
                  onSelected: (value) => setState(() => _format = value),
                  itemBuilder: (_) => [
                    for (final format in ApplicationDocumentFormat.values)
                      PopupMenuItem(
                        value: format,
                        child: Text(format.name.toUpperCase()),
                      ),
                  ],
                  child: Chip(
                    label: Text(_format.name.toUpperCase()),
                    avatar: const Icon(Icons.arrow_drop_down, size: 18),
                  ),
                ),
                ...widget.secondaryActions,
              ],
            ),
            if (_output != null) SelectableText('Application files: $_output'),
          ],
        );
      },
    ),
  );
}
