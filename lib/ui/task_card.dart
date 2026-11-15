/// One task in the list: check circle, title, chips, progress and subtasks.
library;

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../utils/format_utils.dart';
import 'theme.dart';

class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleSubtask,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(Subtask subtask) onToggleSubtask;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t = widget.task;
    final now = DateTime.now();
    final overdue = t.isOverdue(now);

    final dueLabel = t.completed && t.isRepeating
        ? 'Next: ${friendlyDate(t.dueDate, now)}, ${formatTime(t.dueDate)}'
        : '${friendlyDate(t.dueDate, now)}, ${formatTime(t.dueDate)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: overdue ? c.danger.withAlpha(150) : c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CheckCircle(checked: t.completed, onTap: widget.onToggle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.completed ? c.subtext : c.text,
                          decoration: t.completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (t.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.subtext, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _InfoChip(
                            label: '${kCategoryEmoji[t.category] ?? '✨'} ${t.category}',
                            background: categoryColor(t.category, dark: dark),
                            foreground: c.text,
                          ),
                          _InfoChip(
                            icon: Icons.schedule_rounded,
                            label: dueLabel,
                            background: overdue ? c.danger.withAlpha(40) : c.cardAlt,
                            foreground: overdue ? c.danger : c.text,
                          ),
                          if (t.isRepeating)
                            _InfoChip(
                              icon: Icons.repeat_rounded,
                              label: t.repeatSummary,
                              background: c.primary.withAlpha(40),
                              foreground: c.text,
                            ),
                          if (t.reminderMinutes > 0)
                            _InfoChip(
                              icon: Icons.notifications_active_outlined,
                              label: reminderChipLabel(t.reminderMinutes),
                              background: c.accent.withAlpha(45),
                              foreground: c.text,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: c.subtext),
                  color: c.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onSelected: (value) {
                    if (value == 'edit') widget.onEdit();
                    if (value == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 20, color: c.text),
                        const SizedBox(width: 10),
                        Text('Edit', style: TextStyle(color: c.text)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline_rounded, size: 20, color: c.danger),
                        const SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: c.danger)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            if (t.subtasks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: t.progress,
                              minHeight: 9,
                              backgroundColor: c.cardAlt,
                              color: c.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${t.doneSubtasks}/${t.subtasks.length}  ·  ${(t.progress * 100).round()}%',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.subtext),
                        ),
                        Icon(
                          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: c.subtext,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: Column(
                    children: [
                      for (final s in t.subtasks)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onToggleSubtask(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Row(
                              children: [
                                Icon(
                                  s.done ? Icons.check_circle_rounded : Icons.circle_outlined,
                                  size: 22,
                                  color: s.done ? c.primary : c.subtext,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: TextStyle(
                                      color: s.done ? c.subtext : c.text,
                                      decoration: s.done ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.checked, required this.onTap});
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: checked ? c.primary : Colors.transparent,
            border: Border.all(color: c.primary, width: 2),
          ),
          child: checked ? Icon(Icons.check_rounded, size: 18, color: c.onPrimary) : null,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData? icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
