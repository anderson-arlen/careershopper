import 'package:flutter/material.dart';

import '../../storage/job_repository.dart';

class AddListingDialog extends StatefulWidget {
  const AddListingDialog({required this.repository, super.key});

  final JobStore repository;

  @override
  State<AddListingDialog> createState() => _AddListingDialogState();
}

class _AddListingDialogState extends State<AddListingDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uri = Uri.tryParse(_controller.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _error = 'Enter a complete HTTP or HTTPS URL.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final id = await widget.repository.queueManualUrl(uri);
      if (mounted) Navigator.of(context).pop(id);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not queue this URL: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add listing'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste a job URL. Your configured ACP agent will inspect it and return structured listing data through CareerShopper MCP.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_submitting,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Job URL',
                hintText: 'https://example.com/jobs/123',
                errorText: _error,
              ),
              onSubmitted: (_) => _submitting ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link),
          label: const Text('Queue import'),
        ),
      ],
    );
  }
}
