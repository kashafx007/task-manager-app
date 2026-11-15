/// Bottom sheet for exporting tasks to CSV, PDF or e-mail.
library;

import 'package:flutter/material.dart';

import '../logic/task_controller.dart';
import '../models/task.dart';
import '../services/export_service.dart';
import 'theme.dart';
import 'widgets.dart';

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.controller});
  final TaskController controller;

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  ExportScope _scope = ExportScope.all;
  final TextEditingController _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(String doneMessage, Future<void> Function(List<Task> tasks) action) async {
    final messenger = ScaffoldMessenger.of(context);
    final tasks = ExportService.select(widget.controller.rawTasks, _scope);
    if (tasks.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('There are no tasks to export.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await action(tasks);
      messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Export tasks',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in ExportScope.values)
                  CuteChoiceChip(
                    label: s.label,
                    selected: _scope == s,
                    onSelected: () => setState(() => _scope = s),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run('CSV file ready', ExportService.exportCsv),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('CSV'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                              'PDF file ready',
                              (tasks) => ExportService.exportPdf(tasks, _scope.label),
                            ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Send by email',
                style: TextStyle(fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: c.text),
              decoration: const InputDecoration(
                hintText: 'Recipient email (optional)',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final tasks = ExportService.select(widget.controller.rawTasks, _scope);
                        if (tasks.isEmpty) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('There are no tasks to export.')),
                          );
                          return;
                        }
                        final ok = await ExportService.sendEmail(tasks, to: _email.text);
                        messenger.showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Opening your email app...'
                              : 'Could not open an email app on this device.'),
                        ));
                      },
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Open email draft'),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
