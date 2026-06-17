import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────── Constants ───────────────────────────────────
const storageKey = 'task_status_reminder_tasks_v2';
const developerEmail = 'fastunlocked2017@gmail.com';

// ─────────────────────────────── Notifications ───────────────────────────────
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
bool _notificationsReady = false;

const _channelId = 'tasks_channel_v3';
const _channelName = 'تذكيرات المهام';
const _channelDesc = 'إشعارات تذكير بتاريخ ووقت المهمة';

/// إعداد الإشعارات مرة واحدة مع دعم Android الحديث (API 33+)
Future<void> setupNotifications() async {
  if (_notificationsReady) return;
  try {
    tz.initializeTimeZones();

    // اكتشاف المنطقة الزمنية المحلية تلقائياً بدلاً من التثبيت
    try {
      final String timezoneName = await _getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Amman'));
      } catch (_) {}
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // إنشاء قناة الإشعارات بأعلى أولوية
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      await androidPlugin.requestNotificationsPermission();

      try {
        await androidPlugin.requestExactAlarmsPermission();
      } catch (_) {}
    }

    _notificationsReady = true;
  } catch (e) {
    _notificationsReady = false;
  }
}

@pragma('vm:entry-point')
void _onNotificationTap(NotificationResponse response) {
  // يمكن توسيعه لفتح المهمة مباشرة
}

/// اكتشاف المنطقة الزمنية من النظام
Future<String> _getLocalTimezone() async {
  try {
    if (Platform.isAndroid) {
      final result =
          await const MethodChannel('flutter/timezone').invokeMethod<String>(
        'getLocalTimezone',
      );
      if (result != null && result.isNotEmpty) return result;
    }
  } catch (_) {}
  return 'Asia/Amman';
}

/// إشعار اختبار فوري
Future<void> showTestNotification() async {
  await setupNotifications();
  if (!_notificationsReady) return;
  await _notifications.show(
    7001,
    '✅ اختبار الإشعار',
    'الإشعارات تعمل في تطبيق مهامي الملوّنة',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
    ),
  );
}

/// جدولة إشعار مهمة
Future<void> scheduleTaskNotification(AppTask task) async {
  if (task.status == TaskStatus.done || task.reminderAt == null) return;
  await setupNotifications();
  if (!_notificationsReady) return;

  final when = task.reminderAt!;
  if (!when.isAfter(DateTime.now())) return;

  await _notifications.cancel(task.notificationId);

  final scheduledAt = tz.TZDateTime.from(when, tz.local);

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        task.note.isNotEmpty ? task.note : 'لا تنسَ متابعة المهمة في وقتها.',
        contentTitle: '🔔 تذكير: ${task.title}',
        summaryText: task.status.label,
      ),
      category: AndroidNotificationCategory.reminder,
      ticker: task.title,
      autoCancel: true,
      ongoing: false,
      // تأكد إظهار الإشعار حتى لو التطبيق في الخلفية
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
    ),
  );

  Future<void> trySchedule(AndroidScheduleMode mode) {
    return _notifications.zonedSchedule(
      task.notificationId,
      '🔔 تذكير: ${task.title}',
      task.note.isNotEmpty ? task.note : 'لا تنسَ متابعة المهمة في وقتها.',
      scheduledAt,
      details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: task.id,
    );
  }

  try {
    await trySchedule(AndroidScheduleMode.exactAllowWhileIdle);
  } catch (_) {
    try {
      await trySchedule(AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (_) {}
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
  if (!_notificationsReady) return;
  await _notifications.cancel(task.notificationId);
}

// ─────────────────────────────── App Entry ───────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // إعداد الإشعارات مبكراً
  await setupNotifications();
  runApp(const TaskStatusReminderApp());
}

// ─────────────────────────────── App Root ────────────────────────────────────
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

// ─────────────────────────────── Models ──────────────────────────────────────
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
    this.priority = 0,
  });

  final String id;
  String title;
  String note;
  TaskStatus status;
  DateTime createdAt;
  DateTime? reminderAt;
  int priority; // 0=عادي، 1=مهم، 2=عاجل

  int get notificationId {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed % 2147483647;
    return id.codeUnits.fold<int>(0, (sum, unit) => (sum + unit) % 2147483647);
  }

  bool get isOverdue =>
      reminderAt != null &&
      reminderAt!.isBefore(DateTime.now()) &&
      status != TaskStatus.done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'priority': priority,
      };

  factory AppTask.fromJson(Map<String, dynamic> json) {
    return AppTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      note: json['note'] as String? ?? '',
      status: TaskStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TaskStatus.requiredTask,
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      reminderAt: json['reminderAt'] == null
          ? null
          : DateTime.tryParse(json['reminderAt'] as String),
      priority: (json['priority'] as int?) ?? 0,
    );
  }
}

// ─────────────────────────────── Home ────────────────────────────────────────
class TasksHome extends StatefulWidget {
  const TasksHome({super.key});

  @override
  State<TasksHome> createState() => _TasksHomeState();
}

class _TasksHomeState extends State<TasksHome> {
  final List<AppTask> tasks = [];
  TaskStatus? filter;
  SortMode sortMode = SortMode.reminderDate;
  int tab = 0;
  bool loading = true;
  String searchQuery = '';
  bool showSearch = false;

  @override
  void initState() {
    super.initState();
    loadTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await rescheduleAllNotifications(tasks);
    });
  }

  Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        tasks
          ..clear()
          ..addAll(decoded.map((item) => AppTask.fromJson(item)));
      } catch (_) {}
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
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> upsertTask(AppTask task, {AppTask? oldTask}) async {
    if (oldTask == null) {
      tasks.add(task);
    } else {
      final index = tasks.indexWhere((t) => t.id == oldTask.id);
      if (index != -1) tasks[index] = task;
      await cancelTaskNotification(oldTask);
    }
    if (task.status == TaskStatus.done) {
      await cancelTaskNotification(task);
    } else {
      await scheduleTaskNotification(task);
    }
    await saveTasks();
    if (mounted) setState(() {});
  }

  Future<void> deleteTask(AppTask task) async {
    tasks.removeWhere((t) => t.id == task.id);
    await cancelTaskNotification(task);
    await saveTasks();
    if (mounted) setState(() {});
  }

  Future<void> deleteDoneTasks() async {
    final doneTasks = tasks.where((t) => t.status == TaskStatus.done).toList();
    for (final t in doneTasks) {
      await cancelTaskNotification(t);
    }
    tasks.removeWhere((t) => t.status == TaskStatus.done);
    await saveTasks();
    if (mounted) setState(() {});
  }

  Future<void> changeStatus(AppTask task, TaskStatus status) async {
    task.status = status;
    if (status == TaskStatus.done) {
      await cancelTaskNotification(task);
    } else {
      await scheduleTaskNotification(task);
    }
    await saveTasks();
    if (mounted) setState(() {});
  }

  // ── Export JSON ──
  Future<void> exportTasks() async {
    final json = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ بيانات المهام (JSON) إلى الحافظة'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Import JSON ──
  Future<void> importTasks(String jsonText) async {
    try {
      final decoded = jsonDecode(jsonText) as List<dynamic>;
      final imported = decoded.map((i) => AppTask.fromJson(i)).toList();
      // دمج المهام — تجنب التكرار
      for (final t in imported) {
        final idx = tasks.indexWhere((x) => x.id == t.id);
        if (idx == -1) {
          tasks.add(t);
        } else {
          tasks[idx] = t;
        }
      }
      await saveTasks();
      await rescheduleAllNotifications(tasks);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم استيراد ${imported.length} مهمة')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل الاستيراد: تأكد أن النص بصيغة JSON صحيحة'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  List<AppTask> get visibleTasks {
    var list = tasks.where((t) {
      final matchFilter = filter == null || t.status == filter;
      final matchSearch = searchQuery.isEmpty ||
          t.title.contains(searchQuery) ||
          t.note.contains(searchQuery);
      return matchFilter && matchSearch;
    }).toList();

    switch (sortMode) {
      case SortMode.reminderDate:
        list.sort((a, b) {
          final aD = a.reminderAt ?? DateTime(2099);
          final bD = b.reminderAt ?? DateTime(2099);
          return aD.compareTo(bD);
        });
      case SortMode.createdDate:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.priority:
        list.sort((a, b) => b.priority.compareTo(a.priority));
      case SortMode.status:
        list.sort((a, b) => a.status.index.compareTo(b.status.index));
    }
    return list;
  }

  int get doneCount => tasks.where((t) => t.status == TaskStatus.done).length;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      _TasksPage(
        tasks: visibleTasks,
        allTasks: tasks,
        filter: filter,
        sortMode: sortMode,
        showSearch: showSearch,
        searchQuery: searchQuery,
        doneCount: doneCount,
        onFilter: (v) => setState(() => filter = v),
        onSortMode: (v) => setState(() => sortMode = v),
        onSearchToggle: () => setState(() {
          showSearch = !showSearch;
          if (!showSearch) searchQuery = '';
        }),
        onSearchChanged: (v) => setState(() => searchQuery = v),
        onAdd: () => openTaskSheet(),
        onEdit: (t) => openTaskSheet(task: t),
        onDelete: deleteTask,
        onStatus: changeStatus,
        onDeleteDone: doneCount > 0 ? deleteDoneTasks : null,
        onTestNotification: () async {
          await showTestNotification();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'تم إرسال إشعار اختبار. إن لم يظهر، فعّل إشعارات التطبيق من إعدادات الهاتف.'),
              ),
            );
          }
        },
      ),
      _DeveloperPage(
        onExport: exportTasks,
        onImport: (json) => importTasks(json),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tab == 0 ? 'مهامي الملوّنة' : 'المطور والنسخ الاحتياطي'),
      ),
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
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl_outlined),
            selectedIcon: Icon(Icons.checklist_rtl_rounded),
            label: 'المهام',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'الإعدادات',
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

enum SortMode {
  reminderDate('تاريخ التذكير'),
  createdDate('تاريخ الإنشاء'),
  priority('الأولوية'),
  status('الحالة');

  const SortMode(this.label);
  final String label;
}

// ─────────────────────────────── Tasks Page ──────────────────────────────────
class _TasksPage extends StatelessWidget {
  const _TasksPage({
    required this.tasks,
    required this.allTasks,
    required this.filter,
    required this.sortMode,
    required this.showSearch,
    required this.searchQuery,
    required this.doneCount,
    required this.onFilter,
    required this.onSortMode,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
    required this.onTestNotification,
    this.onDeleteDone,
  });

  final List<AppTask> tasks;
  final List<AppTask> allTasks;
  final TaskStatus? filter;
  final SortMode sortMode;
  final bool showSearch;
  final String searchQuery;
  final int doneCount;
  final ValueChanged<TaskStatus?> onFilter;
  final ValueChanged<SortMode> onSortMode;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAdd;
  final ValueChanged<AppTask> onEdit;
  final ValueChanged<AppTask> onDelete;
  final void Function(AppTask task, TaskStatus status) onStatus;
  final VoidCallback onTestNotification;
  final VoidCallback? onDeleteDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _SummaryPanel(tasks: allTasks),
        const SizedBox(height: 10),

        // ── شريط البحث ──
        if (showSearch) ...[
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'ابحث عن مهمة...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: onSearchToggle,
              ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
        ],

        // ── شريط الأدوات ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTestNotification,
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: const Text('اختبار الإشعار'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: onSearchToggle,
              icon: Icon(
                showSearch ? Icons.search_off_rounded : Icons.search_rounded,
              ),
              tooltip: 'بحث',
            ),
            const SizedBox(width: 8),
            _SortButton(current: sortMode, onChanged: onSortMode),
          ],
        ),
        const SizedBox(height: 10),

        // ── فلاتر الحالة ──
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

        // ── زر حذف المنجزة ──
        if (doneCount > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onDeleteDone,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
            ),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: Text('مسح المنجزة ($doneCount)'),
          ),
        ],

        const SizedBox(height: 14),

        if (tasks.isEmpty)
          _EmptyState(onAdd: onAdd, hasSearch: searchQuery.isNotEmpty)
        else
          for (final task in tasks) ...[
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


// ─────────────────────────────── Summary Panel ───────────────────────────────
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.tasks});

  final List<AppTask> tasks;

  @override
  Widget build(BuildContext context) {
    int count(TaskStatus s) => tasks.where((t) => t.status == s).length;
    final overdueCount = tasks.where((t) => t.isOverdue).length;

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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'تابع المطلوب حتى يصبح منجزًا',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (overdueCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$overdueCount متأخرة',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
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
  const _CounterPill(
      {required this.label, required this.value, required this.color});

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
                  color: color, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Sort Button ─────────────────────────────────
class _SortButton extends StatelessWidget {
  const _SortButton({required this.current, required this.onChanged});

  final SortMode current;
  final ValueChanged<SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortMode>(
      tooltip: 'ترتيب',
      icon: const Icon(Icons.sort_rounded),
      onSelected: onChanged,
      itemBuilder: (_) => SortMode.values
          .map(
            (m) => PopupMenuItem(
              value: m,
              child: Row(
                children: [
                  Icon(
                    m == current
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 18,
                    color: const Color(0xFF15803D),
                  ),
                  const SizedBox(width: 8),
                  Text(m.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ─────────────────────────────── Task Card ───────────────────────────────────
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      if (task.priority > 0)
                        Text(
                          task.priority == 2 ? '🔴 عاجل' : '🟡 مهم',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف',
                          style: TextStyle(color: Color(0xFFDC2626))),
                    ),
                  ],
                ),
              ],
            ),
            if (task.note.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.note,
                  style: const TextStyle(color: Color(0xFF64748B))),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusBadge(status: task.status),
                if (task.reminderAt != null)
                  _DateBadge(
                    text:
                        '${task.isOverdue ? "⚠️ متأخرة: " : "🔔 تذكير: "}${formatDateTime(task.reminderAt!)}',
                    color: task.isOverdue
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF15803D),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // أزرار تغيير الحالة
            Row(
              children: [
                for (final s in TaskStatus.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: OutlinedButton(
                        onPressed: task.status == s ? null : () => onStatus(s),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          s.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: task.status == s ? null : s.color,
                            fontSize: 11,
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
        style:
            TextStyle(color: status.color, fontWeight: FontWeight.w900),
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
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

// ─────────────────────────────── Empty State ─────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.hasSearch});

  final VoidCallback onAdd;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.task_alt_rounded,
              size: 52,
              color: const Color(0xFF15803D),
            ),
            const SizedBox(height: 10),
            Text(
              hasSearch ? 'لا توجد نتائج للبحث' : 'لا توجد مهام هنا',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(hasSearch
                ? 'جرب كلمة بحث مختلفة أو غير الفلتر'
                : 'أضف مهمة جديدة وحدد حالتها وتذكيرها.'),
            if (!hasSearch) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة مهمة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Task Sheet ──────────────────────────────────
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
  late int priority;
  DateTime? reminderAt;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.task?.title ?? '');
    noteController = TextEditingController(text: widget.task?.note ?? '');
    status = widget.task?.status ?? TaskStatus.requiredTask;
    priority = widget.task?.priority ?? 0;
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
          ? TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30)))
          : TimeOfDay.fromDateTime(reminderAt!),
    );
    if (time == null) return;
    setState(() {
      reminderAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
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
      priority: priority,
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
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'اسم المهمة *',
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

            // ── الحالة ──
            const Text('الحالة:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
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

            // ── الأولوية ──
            const Text('الأولوية:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  selected: priority == 0,
                  label: const Text('عادي'),
                  onSelected: (_) => setState(() => priority = 0),
                ),
                ChoiceChip(
                  selected: priority == 1,
                  label: const Text('🟡 مهم'),
                  onSelected: (_) => setState(() => priority = 1),
                ),
                ChoiceChip(
                  selected: priority == 2,
                  label: const Text('🔴 عاجل'),
                  onSelected: (_) => setState(() => priority = 2),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── التذكير ──
            OutlinedButton.icon(
              onPressed: pickReminder,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                reminderAt == null
                    ? 'اختيار تاريخ ووقت التذكير'
                    : '🔔 التذكير: ${formatDateTime(reminderAt!)}',
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

// ─────────────────────────────── Developer Page ──────────────────────────────
class _DeveloperPage extends StatefulWidget {
  const _DeveloperPage({required this.onExport, required this.onImport});

  final VoidCallback onExport;
  final ValueChanged<String> onImport;

  @override
  State<_DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<_DeveloperPage> {
  final msgController = TextEditingController();
  final importController = TextEditingController();
  bool showImport = false;

  @override
  void dispose() {
    msgController.dispose();
    importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // ── النسخ الاحتياطي ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💾 النسخ الاحتياطي',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text(
                  'صدِّر بياناتك لحفظها أو نقلها إلى جهاز آخر، ثم استوردها لاحقاً.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onExport,
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('تصدير (نسخ JSON)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => showImport = !showImport),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('استيراد JSON'),
                      ),
                    ),
                  ],
                ),
                if (showImport) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: importController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'الصق هنا نص JSON المُصدَّر',
                      prefixIcon: Icon(Icons.data_object_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      widget.onImport(importController.text.trim());
                      importController.clear();
                      setState(() => showImport = false);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('تأكيد الاستيراد'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── مراسلة المطور ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✉️ مراسلة المطور',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const SelectableText(
                  developerEmail,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: msgController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'اكتب ملاحظتك أو اقتراحك',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          final note = msgController.text.trim().isEmpty
                              ? 'ملاحظة على تطبيق مهامي الملوّنة'
                              : msgController.text.trim();
                          final uri = Uri(
                            scheme: 'mailto',
                            path: developerEmail,
                            query:
                                'subject=ملاحظة على مهامي الملوّنة&body=$note',
                          );
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            await Clipboard.setData(
                              ClipboardData(
                                  text:
                                      'إلى: $developerEmail\n\n$note'),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'تم نسخ الرسالة (لا يوجد تطبيق بريد)')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('إرسال بريد'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final note = msgController.text.trim().isEmpty
                            ? 'ملاحظة على مهامي الملوّنة'
                            : msgController.text.trim();
                        await Clipboard.setData(ClipboardData(
                            text: 'إلى: $developerEmail\n\n$note'));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم نسخ الرسالة')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('نسخ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ── معلومات التطبيق ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('ℹ️ عن التطبيق',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('مهامي الملوّنة — الإصدار 1.1.0'),
                SizedBox(height: 4),
                Text(
                  'تطبيق مفتوح المصدر لإدارة المهام باللغة العربية مع تذكيرات ذكية.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────── Helpers ─────────────────────────────────────
String formatDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} - $hour:$minute';
}
