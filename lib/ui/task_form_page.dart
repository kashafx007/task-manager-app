/// Add / edit a task: title, description, category, due date and time,
/// repeat settings, early reminder and subtasks.
library;

import 'package:flutter/material.dart';

import '../logic/task_controller.dart';
import '../models/task.dart';
import '../utils/format_utils.dart';
import 'theme.dart';
import 'widgets.dart';

class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key, required this.controller, this.task});

  final TaskController controller;

  /// The task being edited, or null when adding a new one.
  final Task? task;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  final TextEditingController _subtaskInput = TextEditingController();

  late String _category;
  late DateTime _date;
  late TimeOfDay _time;
  late RepeatType _repeat;
  late Set<int> _days;
  late int _interval;
  late int _reminder;
  late List<Subtask> _subtasks;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t == null) {
      final inOneHour = DateTime.now().add(const Duration(hours: 1));
      _title = TextEditingController();
      _description = TextEditingController();
      _category = kCategories.first;
      _date = dateOnly(inOneHour);
      _time = TimeOfDay(hour: inOneHour.hour, minute: 0);
      _repeat = RepeatType.none;
      _days = <int>{};
      _interval = 2;
      _reminder = 10;
      _subtasks = <Subtask>[];
    } else {
      _title = TextEditingController(text: t.title);
      _description = TextEditingController(text: t.description);
      _category = t.category;
      _date = dateOnly(t.dueDate);
      _time = TimeOfDay(hour: t.dueDate.hour, minute: t.dueDate.minute);
      _repeat = t.repeatType;
      _days = Set<int>.of(t.repeatDays);
      _interval = t.repeatInterval < 1 ? 1 : t.repeatInterval;
      _reminder = t.reminderMinutes;
      _subtasks = t.subtasks.map((s) => Subtask(id: s.id, title: s.title, done: s.done)).toList();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _subtaskInput.dispose();
    super.dispose();
  }

  /// The due date and time currently chosen in the form.
  DateTime get _chosenDue =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// True when [d] is earlier than the current minute.
  bool _isInPast(DateTime d) {
    final n = DateTime.now();
    return d.isBefore(DateTime(n.year, n.month, n.day, n.hour, n.minute));
  }

  /// True when the chosen date/time is in the past. An already overdue task
  /// that is being edited is fine as long as its date and time stay unchanged.
  bool get _dueIsInvalid {
    final due = _chosenDue;
    final unchanged = widget.task != null && due == widget.task!.dueDate;
    return _isInPast(due) && !unchanged;
  }

  void _showPastWarning(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    // Past days cannot be picked. (An old overdue task being edited starts the
    // picker on today instead, so the picker never receives an invalid date.)
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickTime() async {
    // If the current time is already in the past, open the clock on the next
    // full hour so the user starts from a valid time.
    var initial = _time;
    if (_isInPast(_chosenDue)) {
      final next = DateTime.now().add(const Duration(hours: 1));
      initial = TimeOfDay(hour: next.hour, minute: 0);
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    // The time is kept so the red message below the picker explains the
    // problem; saving stays blocked until a valid time is chosen.
    setState(() => _time = picked);
  }

  void _addSubtask() {
    final text = _subtaskInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(Subtask(title: text));
      _subtaskInput.clear();
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_repeat == RepeatType.weekly && _days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one weekday for a weekly repeat.')),
      );
      return;
    }

    // A task cannot be given a due date/time in the past.
    if (_dueIsInvalid) {
      _showPastWarning('Please choose a due date and time that has not passed yet.');
      return;
    }
    final due = _chosenDue;

    // Also keep a subtask that was typed but not added with the + button.
    final pending = _subtaskInput.text.trim();
    if (pending.isNotEmpty) _subtasks.add(Subtask(title: pending));

    final old = widget.task;
    final task = Task(
      id: old?.id,
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category,
      dueDate: due,
      repeatType: _repeat,
      repeatDays: _repeat == RepeatType.weekly ? Set<int>.of(_days) : <int>{},
      repeatInterval: _repeat == RepeatType.interval ? _interval : 1,
      reminderMinutes: _reminder,
      completed: old?.completed ?? false,
      completedAt: old?.completedAt,
      createdAt: old?.createdAt,
      subtasks: _subtasks.map((s) => Subtask(id: s.id, title: s.title, done: s.done)).toList(),
    );

    // Close the page first, then save: the list updates instantly either way.
    Navigator.of(context).pop();
    if (old == null) {
      widget.controller.addTask(task);
    } else {
      widget.controller.updateTask(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CutePage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(_editing ? 'Edit task' : 'New task')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  SectionCard(
                    title: 'Details',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _title,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: c.text),
                          decoration: const InputDecoration(
                            labelText: 'Title',
                            prefixIcon: Icon(Icons.edit_note_rounded),
                          ),
                          validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          minLines: 2,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: c.text),
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Category',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final cat in kCategories)
                          CuteChoiceChip(
                            label: '${kCategoryEmoji[cat]} $cat',
                            selected: _category == cat,
                            onSelected: () => setState(() => _category = cat),
                          ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Due date and time',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _PickerTile(
                                icon: Icons.calendar_month_rounded,
                                label: formatDate(_date),
                                onTap: _pickDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _PickerTile(
                                icon: Icons.access_time_rounded,
                                label: _time.format(context),
                                onTap: _pickTime,
                              ),
                            ),
                          ],
                        ),
                        if (_dueIsInvalid)
                          Padding(
                            padding: const EdgeInsets.only(top: 10, left: 4),
                            child: Text(
                              'This time has already passed. Please choose a later time.',
                              style: TextStyle(
                                color: c.danger,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Repeat',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in const {
                              RepeatType.none: 'Off',
                              RepeatType.daily: 'Daily',
                              RepeatType.weekly: 'Selected days',
                              RepeatType.interval: 'Every N days',
                            }.entries)
                              CuteChoiceChip(
                                label: entry.value,
                                selected: _repeat == entry.key,
                                onSelected: () => setState(() => _repeat = entry.key),
                              ),
                          ],
                        ),
                        if (_repeat == RepeatType.weekly) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                                CuteChoiceChip(
                                  label: weekdayShort(d),
                                  selected: _days.contains(d),
                                  onSelected: () => setState(() {
                                    if (!_days.add(d)) _days.remove(d);
                                  }),
                                ),
                            ],
                          ),
                        ],
                        if (_repeat == RepeatType.interval) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: _interval > 1 ? () => setState(() => _interval--) : null,
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              Expanded(
                                child: Text(
                                  _interval == 1 ? 'Every day' : 'Every $_interval days',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w800, color: c.text),
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: _interval < 60 ? () => setState(() => _interval++) : null,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ],
                        if (_repeat != RepeatType.none) ...[
                          const SizedBox(height: 10),
                          Text(
                            'The task resets automatically on its next scheduled day.',
                            style: TextStyle(color: c.subtext, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Early reminder',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in kReminderOptions)
                              CuteChoiceChip(
                                label: reminderChipLabel(m),
                                selected: _reminder == m,
                                onSelected: () => setState(() => _reminder = m),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'You always get a notification at the due time. '
                              'An early reminder is sent in addition.',
                          style: TextStyle(color: c.subtext, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Subtasks (progress bar)',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _subtaskInput,
                                textCapitalization: TextCapitalization.sentences,
                                style: TextStyle(color: c.text),
                                onSubmitted: (_) => _addSubtask(),
                                decoration: const InputDecoration(hintText: 'Add a subtask'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _addSubtask,
                              icon: const Icon(Icons.add_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: c.primary,
                                foregroundColor: c.onPrimary,
                              ),
                            ),
                          ],
                        ),
                        for (var i = 0; i < _subtasks.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.only(left: 12, right: 4),
                              decoration: BoxDecoration(
                                color: c.cardAlt,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _subtasks[i].done
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    size: 20,
                                    color: _subtasks[i].done ? c.primary : c.subtext,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(_subtasks[i].title,
                                        style: TextStyle(color: c.text)),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() => _subtasks.removeAt(i)),
                                    icon: Icon(Icons.close_rounded, color: c.subtext, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_editing ? 'Save changes' : 'Save task'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: c.cardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}