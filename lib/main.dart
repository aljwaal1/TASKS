import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const storageKey = 'task_status_reminder_tasks_v1';
const developerEmail = 'fastunlocked2017@gmail.com';

final notifications = FlutterLocalNotificationsPlugin();
bool notificationsReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaskStatusReminderApp());
}

Future<void> setupNotifications() async {
  if (notificationsReady) return;
  try {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Amman'));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await notifications.initialize(settings);

    final androidPlugin = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {
      // بعض الأجهزة لا تحتاج هذا الطلب أو لا تدعمه.
    }
    notificationsReady = true;
  } catch (_) {
    notificationsReady = false;
  }
}

Future<void> showTestNotification() async {
  await setupNotifications();
  if (!notificationsReady) return;
  await notifications.show(
    7001,
    'اختبار الإشعار',
    'الإشعارات تعمل في تطبيق مهامي الملوّنة',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'tasks_channel_v2',
        'تذكيرات المهام',
        channelDescription: 'إشعارات تذكير بتاريخ ووقت المهمة',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
    ),
  );
}

Future<void> scheduleTaskNotification(AppTask task) async {
  if (task.status == TaskStatus.done || task.reminderAt == null) return;
  await setupNotifications();
  if (!notificationsReady) return;

  final when = task.reminderAt!;
  if (!when.isAfter(DateTime.now())) return;
  final scheduledAt = tz.TZDateTime.from(when, tz.local);

  Future<void> schedule(AndroidScheduleMode mode) {
    return notifications.zonedSchedule(
      task.notificationId,
      'تذكير مهمة',
      '${task.title} - ${task.status.label}',
      scheduledAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'tasks_channel_v2',
          'تذكيرات المهام',
          channelDescription: 'إشعارات تذكير بتاريخ ووقت المهمة',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          styleInformation: BigTextStyleInformation('لا تنسَ متابعة المهمة في وقتها.'),
        ),
      ),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: task.id,
    );
  }

  try {
    await schedule(AndroidScheduleMode.exactAllowWhileIdle);
  } catch (_) {
    await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

Future<void> rescheduleAllNotifications(List<AppTask> tasks) async {
  await setupNotifications();
  for (final task in tasks) {
    if (task.status != TaskStatus.done && task.reminderAt != null) {
      await scheduleTaskNotification(task);
    }
  }
}

Future<void> cancelTaskNotification(AppTask task) async {
  await setupNotifications();
  if (!notificationsReady) return;
  await notifications.cancel(task.notificationId);
}

class TaskStatusReminderApp extends StatelessWidget {
  const TaskStatusReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مهامي الملوّنة',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAF7),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF15803D),
          secondary: Color(0xFFF97316),
          tertiary: Color(0xFFDC2626),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Color(0xFFF8FAF7),
          foregroundColor: Color(0xFF172A16),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE2E8D8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAF7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E4D2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E4D2)),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: TasksHome(),
      ),
    );
  }
}

enum TaskStatus {
  requiredTask('مطلوب', Color(0xFFDC2626), Icons.error_outline_rounded),
  inProgress('تحت الإنجاز', Color(0xFFF97316), Icons.timelapse_rounded),
  done('منجز', Color(0xFF15803D), Icons.check_circle_outline_rounded);

  const TaskStatus(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

class AppTask {
  AppTask({
    required this.id,
    required this.title,
    required this.note,
    required this.status,
    required this.createdAt,
    this.reminderAt,
  });

  final String id;
  String title;
  String note;
  TaskStatus status;
  DateTime createdAt;
  DateTime? reminderAt;

  int get notificationId {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed % 2147483647;
    return id.codeUnits.fold<int>(0, (sum, unit) => (sum + unit) % 2147483647);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
      };

  factory AppTask.fromJson(Map<String, dynamic> json) {
    return AppTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      note: json['note'] as String? ?? '',
      status: TaskStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => TaskStatus.requiredTask,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      reminderAt: json['reminderAt'] == null
          ? null
          : DateTime.tryParse(json['reminderAt'] as String),
    );
  }
}

class TasksHome extends StatefulWidget {
  const TasksHome({super.key});

  @override
  State<TasksHome> createState() => _TasksHomeState();
}

class _TasksHomeState extends State<TasksHome> {
  final List<AppTask> tasks = [];
  TaskStatus? filter;
  int tab = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await setupNotifications();
      await rescheduleAllNotifications(tasks);
      if (mounted) setState(() {});
    });
  }

  Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      tasks
        ..clear()
        ..addAll(decoded.map((item) => AppTask.fromJson(item)));
    } else {
      tasks.addAll([
        AppTask(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: 'مراجعة المهام اليومية',
          note: 'مثال سريع يمكن تعديله أو حذفه.',
          status: TaskStatus.requiredTask,
          createdAt: DateTime.now(),
        ),
      ]);
    }
    setState(() => loading = false);
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
  }

  Future<void> upsertTask(AppTask task, {AppTask? oldTask}) async {
    if (oldTask == null) {
      tasks.add(task);
    } else {
      final index = tasks.indexWhere((item) => item.id == oldTask.id);
      if (index != -1) tasks[index] = task;
      await cancelTaskNotification(oldTask);
    }
    if (task.status == TaskStatus.done) {
      await cancelTaskNotification(task);
    } else {
      await scheduleTaskNotification(task);
    }
    await saveTasks();
    setState(() {});
  }

  Future<void> deleteTask(AppTask task) async {
    tasks.removeWhere((item) => item.id == task.id);
    await cancelTaskNotification(task);
    await saveTasks();
    setState(() {});
  }

  Future<void> changeStatus(AppTask task, TaskStatus status) async {
    task.status = status;
    if (status == TaskStatus.done) {
      await cancelTaskNotification(task);
    } else {
      await scheduleTaskNotification(task);
    }
    await saveTasks();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [
      _TasksPage(
        tasks: tasks,
        filter: filter,
        onFilter: (value) => setState(() => filter = value),
        onAdd: () => openTaskSheet(),
        onEdit: (task) => openTaskSheet(task: task),
        onDelete: deleteTask,
        onStatus: changeStatus,
        onTestNotification: () async {
          await showTestNotification();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم إرسال إشعار اختبار. إن لم يظهر، فعّل إشعارات التطبيق من إعدادات الهاتف.')),
            );
          }
        },
      ),
      const _DeveloperPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tab == 0 ? 'مهامي الملوّنة' : 'مراسلة المطور')),
      body: pages[tab],
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => openTaskSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('مهمة جديدة'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl_outlined),
            selectedIcon: Icon(Icons.checklist_rtl_rounded),
            label: 'المهام',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline_rounded),
            selectedIcon: Icon(Icons.mail_rounded),
            label: 'المطور',
          ),
        ],
      ),
    );
  }

  Future<void> openTaskSheet({AppTask? task}) async {
    final result = await showModalBottomSheet<AppTask>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _TaskSheet(task: task),
      ),
    );
    if (result != null) {
      await upsertTask(result, oldTask: task);
      if (mounted && result.reminderAt != null && result.status != TaskStatus.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ المهمة وجدولة التذكير.')),
        );
      }
    }
  }
}

class _TasksPage extends StatelessWidget {
  const _TasksPage({
    required this.tasks,
    required this.filter,
    required this.onFilter,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
    required this.onTestNotification,
  });

  final List<AppTask> tasks;
  final TaskStatus? filter;
  final ValueChanged<TaskStatus?> onFilter;
  final VoidCallback onAdd;
  final ValueChanged<AppTask> onEdit;
  final ValueChanged<AppTask> onDelete;
  final void Function(AppTask task, TaskStatus status) onStatus;
  final VoidCallback onTestNotification;

  @override
  Widget build(BuildContext context) {
    final visible = tasks
        .where((task) => filter == null || task.status == filter)
        .toList()
      ..sort((a, b) {
        final aDate = a.reminderAt ?? DateTime(2099);
        final bDate = b.reminderAt ?? DateTime(2099);
        return aDate.compareTo(bDate);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _SummaryPanel(tasks: tasks),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onTestNotification,
          icon: const Icon(Icons.notifications_active_rounded),
          label: const Text('اختبار الإشعار الآن'),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  selected: filter == null,
                  label: const Text('الكل'),
                  onSelected: (_) => onFilter(null),
                ),
              ),
              for (final status in TaskStatus.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    selected: filter == status,
                    label: Text(status.label),
                    avatar: Icon(status.icon, color: status.color, size: 18),
                    onSelected: (_) => onFilter(status),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          _EmptyState(onAdd: onAdd)
        else
          for (final task in visible) ...[
            _TaskCard(
              task: task,
              onEdit: () => onEdit(task),
              onDelete: () => onDelete(task),
              onStatus: (status) => onStatus(task, status),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.tasks});

  final List<AppTask> tasks;

  @override
  Widget build(BuildContext context) {
    int count(TaskStatus status) =>
        tasks.where((task) => task.status == status).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFFF97316), Color(0xFFDC2626)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تابع المطلوب حتى يصبح منجزًا',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CounterPill(
                label: 'مطلوب',
                value: count(TaskStatus.requiredTask),
                color: TaskStatus.requiredTask.color,
              ),
              const SizedBox(width: 8),
              _CounterPill(
                label: 'تحت الإنجاز',
                value: count(TaskStatus.inProgress),
                color: TaskStatus.inProgress.color,
              ),
              const SizedBox(width: 8),
              _CounterPill(
                label: 'منجز',
                value: count(TaskStatus.done),
                color: TaskStatus.done.color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CounterPill extends StatelessWidget {
  const _CounterPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
  });

  final AppTask task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<TaskStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final overdue = task.reminderAt != null &&
        task.reminderAt!.isBefore(DateTime.now()) &&
        task.status != TaskStatus.done;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: task.status.color,
                  child: Icon(task.status.icon, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
            if (task.note.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.note, style: const TextStyle(color: Color(0xFF64748B))),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusBadge(status: task.status),
                if (task.reminderAt != null)
                  _DateBadge(
                    text: '${overdue ? "متأخرة: " : "تذكير: "}${formatDateTime(task.reminderAt!)}',
                    color: overdue ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final status in TaskStatus.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: OutlinedButton(
                        onPressed:
                            task.status == status ? null : () => onStatus(status),
                        child: Text(
                          status.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: task.status == status ? null : status.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: status.color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.task});

  final AppTask? task;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final TextEditingController titleController;
  late final TextEditingController noteController;
  late TaskStatus status;
  DateTime? reminderAt;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.task?.title ?? '');
    noteController = TextEditingController(text: widget.task?.note ?? '');
    status = widget.task?.status ?? TaskStatus.requiredTask;
    reminderAt = widget.task?.reminderAt;
  }

  @override
  void dispose() {
    titleController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: reminderAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('ar'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: reminderAt == null
          ? TimeOfDay.fromDateTime(now.add(const Duration(minutes: 10)))
          : TimeOfDay.fromDateTime(reminderAt!),
    );
    if (time == null) return;
    setState(() {
      reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void submit() {
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    final task = AppTask(
      id: widget.task?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      note: noteController.text.trim(),
      status: status,
      createdAt: widget.task?.createdAt ?? DateTime.now(),
      reminderAt: reminderAt,
    );
    Navigator.pop(context, task);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.task == null ? 'مهمة جديدة' : 'تعديل المهمة',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'اسم المهمة',
                prefixIcon: Icon(Icons.task_alt_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in TaskStatus.values)
                  ChoiceChip(
                    selected: status == item,
                    label: Text(item.label),
                    avatar: Icon(item.icon, color: item.color, size: 18),
                    onSelected: (_) => setState(() => status = item),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: pickReminder,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                reminderAt == null
                    ? 'اختيار تاريخ ووقت التذكير'
                    : 'التذكير: ${formatDateTime(reminderAt!)}',
              ),
            ),
            if (reminderAt != null)
              TextButton.icon(
                onPressed: () => setState(() => reminderAt = null),
                icon: const Icon(Icons.notifications_off_outlined),
                label: const Text('إلغاء التذكير'),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ المهمة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.task_alt_rounded, size: 52, color: Color(0xFF15803D)),
            const SizedBox(height: 10),
            const Text(
              'لا توجد مهام هنا',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('أضف مهمة جديدة وحدد حالتها وتذكيرها.'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة مهمة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeveloperPage extends StatefulWidget {
  const _DeveloperPage();

  @override
  State<_DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<_DeveloperPage> {
  final noteController = TextEditingController();

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مراسلة المطور',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  developerEmail,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'اكتب ملاحظتك أو اقتراحك',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final note = noteController.text.trim().isEmpty
                        ? 'ملاحظة على تطبيق مهامي الملوّنة'
                        : noteController.text.trim();
                    await Clipboard.setData(
                      ClipboardData(text: 'إلى: $developerEmail\n\n$note'),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ الرسالة')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('نسخ الرسالة'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String formatDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}/${value.month}/${value.day} - $hour:$minute';
}
