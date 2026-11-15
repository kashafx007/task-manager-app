/// Export tasks as CSV, PDF, or an e-mail draft.
///
/// * CSV / PDF: downloaded in Chrome, shared through the Android share sheet.
/// * E-mail: opens the user's mail app with the task list in the message body
///   (a `mailto:` link cannot carry attachments, so the CSV/PDF buttons are the
///   way to get a file).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

import '../models/task.dart';
import '../utils/format_utils.dart';
import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';

/// Which tasks to export.
enum ExportScope { all, today, pending, completed }

extension ExportScopeLabel on ExportScope {
  String get label {
    switch (this) {
      case ExportScope.all:
        return 'All tasks';
      case ExportScope.today:
        return 'Today';
      case ExportScope.pending:
        return 'Pending';
      case ExportScope.completed:
        return 'Completed';
    }
  }
}

class ExportService {
  /// Filters [all] according to [scope].
  static List<Task> select(List<Task> all, ExportScope scope) {
    final now = DateTime.now();
    final list = all.where((t) {
      switch (scope) {
        case ExportScope.all:
          return true;
        case ExportScope.today:
          return !t.completed && sameDay(t.dueDate, now);
        case ExportScope.pending:
          return !t.completed;
        case ExportScope.completed:
          return t.completed;
      }
    }).toList();
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  static String _status(Task t) => t.completed ? 'Completed' : 'Pending';

  static String _progress(Task t) {
    if (t.subtasks.isEmpty) return '-';
    return '${t.doneSubtasks}/${t.subtasks.length} (${(t.progress * 100).round()}%)';
  }

  // --------------------------------------------------------------------- CSV

  static String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  static String buildCsv(List<Task> tasks) {
    final rows = <String>[
      [
        'Title', 'Description', 'Category', 'Due date', 'Due time',
        'Status', 'Repeat', 'Early reminder', 'Subtasks', 'Subtask progress',
      ].map(_csvCell).join(','),
    ];
    for (final t in tasks) {
      rows.add([
        t.title,
        t.description,
        t.category,
        formatDate(t.dueDate),
        formatTime(t.dueDate),
        _status(t),
        t.repeatSummary,
        reminderLabel(t.reminderMinutes),
        t.subtasks.map((s) => '${s.done ? '[x]' : '[ ]'} ${s.title}').join('; '),
        _progress(t),
      ].map(_csvCell).join(','));
    }
    // The BOM makes Excel open the file as UTF-8.
    return '﻿${rows.join('\r\n')}\r\n';
  }

  static Future<void> exportCsv(List<Task> tasks) {
    final bytes = Uint8List.fromList(utf8.encode(buildCsv(tasks)));
    return saveFile('tasknest_tasks_${fileStamp(DateTime.now())}.csv', bytes, 'text/csv');
  }

  // --------------------------------------------------------------------- PDF

  /// The default PDF fonts only cover Latin characters, so anything else
  /// (emoji, Urdu, ...) is replaced by `?` to avoid missing-glyph boxes.
  static String _pdfSafe(String s) =>
      String.fromCharCodes(s.runes.map((r) => r < 256 ? r : 63));

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        _pdfSafe(text),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  static Future<Uint8List> buildPdf(List<Task> tasks, String scopeLabel) async {
    final doc = pw.Document(title: 'TaskNest tasks');
    const headerColor = PdfColor.fromInt(0xFFE8D9B8);
    const sage = PdfColor.fromInt(0xFF6F8250);
    final done = tasks.where((t) => t.completed).length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Text('TaskNest - Task Report',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: sage)),
          pw.SizedBox(height: 4),
          pw.Text(
            '$scopeLabel  |  ${tasks.length} tasks  |  $done completed  |  '
            'Generated ${formatDate(DateTime.now())}, ${formatTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(2.4),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(2),
              5: pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: headerColor),
                children: [
                  _cell('Task', bold: true),
                  _cell('Category', bold: true),
                  _cell('Due', bold: true),
                  _cell('Status', bold: true),
                  _cell('Repeat', bold: true),
                  _cell('Progress', bold: true),
                ],
              ),
              for (final t in tasks)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _pdfSafe(t.title),
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                          if (t.description.isNotEmpty)
                            pw.Text(_pdfSafe(t.description),
                                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                          for (final s in t.subtasks)
                            pw.Text(
                              _pdfSafe('${s.done ? '[x]' : '[ ]'} ${s.title}'),
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                            ),
                        ],
                      ),
                    ),
                    _cell(t.category),
                    _cell('${formatDate(t.dueDate)}\n${formatTime(t.dueDate)}'),
                    _cell(_status(t), color: t.completed ? sage : PdfColors.red700),
                    _cell(t.repeatSummary),
                    _cell(_progress(t)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> exportPdf(List<Task> tasks, String scopeLabel) async {
    final bytes = await buildPdf(tasks, scopeLabel);
    await saveFile('tasknest_tasks_${fileStamp(DateTime.now())}.pdf', bytes, 'application/pdf');
  }

  // ------------------------------------------------------------------- Email

  static String buildEmailBody(List<Task> tasks) {
    final buffer = StringBuffer('My TaskNest tasks\n\n');
    for (final t in tasks) {
      buffer.writeln('${t.completed ? '[x]' : '[ ]'} ${t.title} - '
          '${formatDate(t.dueDate)} ${formatTime(t.dueDate)} (${t.category})');
      if (t.isRepeating) buffer.writeln('    Repeats: ${t.repeatSummary}');
      for (final s in t.subtasks) {
        buffer.writeln('    ${s.done ? '[x]' : '[ ]'} ${s.title}');
      }
    }
    var text = buffer.toString();
    // Mail links have a length limit, so very long lists are shortened.
    if (text.length > 1500) {
      text = '${text.substring(0, 1500)}\n... (list shortened - use the CSV or PDF export for the full list)';
    }
    return text;
  }

  /// Opens the mail app with a prepared message. Returns false if it fails.
  static Future<bool> sendEmail(List<Task> tasks, {String to = ''}) async {
    final uri = Uri.parse(
      'mailto:${Uri.encodeComponent(to.trim())}'
      '?subject=${Uri.encodeComponent('My TaskNest tasks')}'
      '&body=${Uri.encodeComponent(buildEmailBody(tasks))}',
    );
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}
