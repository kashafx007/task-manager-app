/// Main screen: header, category filter, four task views (Today, Repeated,
/// Completed, All) with a bottom navigation bar, and the "New task" button.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logic/settings_controller.dart';
import '../logic/task_controller.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../utils/format_utils.dart';
import 'export_sheet.dart';
import 'settings_page.dart';
import 'task_card.dart';
import 'task_form_page.dart';
import 'teddy.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.settings,
    required this.notifications,
  });

  final TaskController controller;
  final SettingsController settings;
  final NotificationService notifications;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  String _webPermission = 'n/a';

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    if (kIsWeb) {
      _webPermission = widget.notifications.webPermission;
    } else {
      widget.notifications.requestPermission();
    }
  }

  // ---------------------------------------------------------------- actions

  void _openForm([Task? task]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskFormPage(controller: widget.controller, task: task),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          notifications: widget.notifications,
        ),
      ),
    );
  }

  void _openExport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportSheet(controller: widget.controller),
    );
  }

  Future<void> _confirmDelete(Task task) async {
    final c = AppColors.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete task?', style: TextStyle(color: c.text, fontWeight: FontWeight.w800)),
        content: Text('"${task.title}" will be removed.', style: TextStyle(color: c.subtext)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final backup = task.clone();
    await widget.controller.deleteTask(task);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Task deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.controller.restoreTask(backup),
        ),
      ));
  }

  Future<void> _allowWebNotifications() async {
    await widget.notifications.requestPermission();
    if (mounted) setState(() => _webPermission = widget.notifications.webPermission);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = AppColors.of(context);
        final ctrl = widget.controller;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return CutePage(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TeddyBear(size: 34, dark: isDark),
                  const SizedBox(width: 8),
                  const Text('TaskNest'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Export',
                  onPressed: _openExport,
                  icon: const Icon(Icons.file_download_outlined),
                ),
                IconButton(
                  tooltip: isDark ? 'Light mode' : 'Dark mode',
                  onPressed: () => widget.settings
                      .setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
                  icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_rounded),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _buildBody(ctrl, c),
              ),
            ),
            floatingActionButton: ctrl.isLoading || ctrl.loadError != null
                ? null
                : FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New task', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            drawer: _buildDrawer(ctrl, c, isDark),
          ),
        );
      },
    );
  }

  /// Side menu (the three-line icon in the app bar) used to switch views.
  Widget _buildDrawer(TaskController ctrl, AppColors c, bool isDark) {
    final items = <(IconData, IconData, String, int)>[
      (Icons.today_outlined, Icons.today_rounded, 'Today', ctrl.todayCount),
      (Icons.repeat_rounded, Icons.repeat_on_rounded, 'Repeated', ctrl.repeatedCount),
      (Icons.warning_amber_outlined, Icons.warning_amber_rounded, 'Overdue', ctrl.overdueCount),
      (Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'Completed', ctrl.completedCount),
      (Icons.list_alt_outlined, Icons.list_alt_rounded, 'All tasks', ctrl.allCount),
    ];
    return Drawer(
      backgroundColor: c.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  TeddyBear(size: 42, dark: isDark),
                  const SizedBox(width: 12),
                  Text(
                    'TaskNest',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text),
                  ),
                ],
              ),
            ),
            Divider(color: c.border),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  selected: _tab == i,
                  selectedTileColor: c.cardAlt,
                  selectedColor: c.primary,
                  leading: Icon(_tab == i ? items[i].$2 : items[i].$1),
                  title: Text(
                    items[i].$3,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  trailing: items[i].$4 > 0
                      ? Badge(
                    label: Text('${items[i].$4}'),
                    backgroundColor: i == 2 ? c.danger : null,
                  )
                      : null,
                  onTap: () {
                    setState(() => _tab = i);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(TaskController ctrl, AppColors c) {
    if (ctrl.isLoading) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }
    if (ctrl.loadError != null) {
      return _ErrorView(message: ctrl.loadError!, onRetry: ctrl.load);
    }

    final lists = <List<Task>>[
      ctrl.todayTasks,
      ctrl.repeatedTasks,
      ctrl.overdueTasks,
      ctrl.completedTasks,
      ctrl.allTasks,
    ];
    final tasks = lists[_tab];

    const empties = <(String, String, String)>[
      ('🧸', 'Nothing due today', 'Enjoy the calm, or tap "New task" to add something.'),
      ('🔁', 'No repeating tasks', 'Add a task and set it to repeat daily or on chosen days.'),
      ('🎉', 'Nothing overdue', 'You are all caught up. Great job!'),
      ('🍯', 'No completed tasks yet', 'Tasks you finish will show up here.'),
      ('🐻', 'Your nest is empty', 'Tap "New task" to create your first task.'),
    ];

    return Column(
      children: [
        if (kIsWeb && _webPermission != 'granted') _buildPermissionBanner(c),
        _Header(controller: ctrl),
        _CategoryBar(controller: ctrl),
        Expanded(
          child: tasks.isEmpty
              ? EmptyState(
            emoji: empties[_tab].$1,
            title: ctrl.categoryFilter == null
                ? empties[_tab].$2
                : 'Nothing in ${ctrl.categoryFilter}',
            subtitle: empties[_tab].$3,
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            itemCount: tasks.length,
            itemBuilder: (context, i) {
              final task = tasks[i];
              return TaskCard(
                key: ObjectKey(task),
                task: task,
                onToggle: () => ctrl.toggleComplete(task),
                onEdit: () => _openForm(task),
                onDelete: () => _confirmDelete(task),
                onToggleSubtask: (s) => ctrl.toggleSubtask(task, s),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionBanner(AppColors c) {
    final blocked = _webPermission == 'denied';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.accent.withAlpha(45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.accent.withAlpha(120)),
      ),
      child: Row(
        children: [
          const Text('🔔', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              blocked
                  ? 'Notifications are blocked. Allow them from the lock icon in the address bar.'
                  : 'Allow browser notifications to get task reminders.',
              style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (!blocked)
            TextButton(onPressed: _allowWebNotifications, child: const Text('Allow')),
        ],
      ),
    );
  }
}

/// Greeting plus "today's progress" bar.
class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning ☀️'
        : now.hour < 17
        ? 'Good afternoon 🧸'
        : 'Good evening 🌙';
    final pending = controller.todayCount;
    final done = controller.doneTodayCount;
    final total = pending + done;
    final value = total == 0 ? 0.0 : done / total;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 2),
          Text(formatDate(now), style: TextStyle(color: c.subtext, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    backgroundColor: c.cardAlt,
                    color: c.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                total == 0 ? 'No tasks today' : '$done of $total done',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Category filter on a single line. If the window is too narrow the whole row
/// is scaled down a little instead of being cut off, so "Other" is always
/// fully visible.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.controller});
  final TaskController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CategoryPill(
              label: 'All',
              selected: controller.categoryFilter == null,
              onTap: () => controller.setCategoryFilter(null),
            ),
            for (final cat in kCategories) ...[
              const SizedBox(width: 8),
              _CategoryPill(
                label: '${kCategoryEmoji[cat]} $cat',
                selected: controller.categoryFilter == cat,
                onTap: () => controller.setCategoryFilter(
                  controller.categoryFilter == cat ? null : cat,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One rounded filter button of the category bar.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: selected ? c.primary : c.card,
      shape: StadiumBorder(side: BorderSide(color: selected ? c.primary : c.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 14,
              color: selected ? c.onPrimary : c.text,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😿', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text('The database could not be opened',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 8),
            Text(
              kIsWeb
                  ? 'On Chrome, run this once in the project folder and restart the app:\n'
                  'dart run sqflite_common_ffi_web:setup'
                  : 'Please restart the app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.subtext, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.subtext, fontSize: 11)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}