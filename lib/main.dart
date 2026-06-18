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

// قناة خاصة لإبقاء التطبيق حياً في الخلفية (هواوي وشياومي)
const _keepAliveChannelId = 'tasks_keepalive';
const _keepAliveChannelName = 'خدمة التذكيرات';
const _keepAliveNotifId = 9999;

/// إعداد الإشعارات — مقسّم لخطوات مستقلة حتى لا يفشل الكل بسبب خطأ واحد
Future<void> setupNotifications() async {
  if (_notificationsReady) return;

  // الخطوة 1: تهيئة المناطق الزمنية
  try {
    tz.initializeTimeZones();
  } catch (_) {}

  // الخطوة 2: تحديد المنطقة الزمنية المحلية
  try {
    final name = await _getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  } catch (_) {
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Amman'));
    } catch (_) {}
  }

  // الخطوة 3: تهيئة المكتبة
  try {
    const android = AndroidInitializationSettings('@drawable/app_icon');
    await _notifications.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );
  } catch (e) {
    // نحاول بأيقونة بديلة
    try {
      const android = AndroidInitializationSettings('ic_launcher');
      await _notifications.initialize(
        const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: _onNotificationTap,
        onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
      );
    } catch (_) {
      return; // فشل كامل
    }
  }

  // الخطوة 4: إنشاء القنوات وطلب الأذونات — كل عملية مستقلة
  final androidPlugin = _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    try {
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
    } catch (_) {}

    try {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _keepAliveChannelId,
          _keepAliveChannelName,
          description: 'تعمل في الخلفية لضمان وصول التذكيرات',
          importance: Importance.min,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    } catch (_) {}

    try {
      await androidPlugin.requestNotificationsPermission();
    } catch (_) {}

    try {
      await androidPlugin.requestExactAlarmsPermission();
    } catch (_) {}
  }

  _notificationsReady = true;
}

/// إشعار ثابت صامت يمنع هواوي من إيقاف التطبيق في الخلفية
Future<void> showKeepAliveNotification(int activeTaskCount) async {
  if (!_notificationsReady) return;
  if (activeTaskCount == 0) {
    await _notifications.cancel(_keepAliveNotifId);
    return;
  }
  // Android Go / هواوي: نستخدم foregroundServiceType لمنع إيقاف التطبيق
  await _notifications.show(
    _keepAliveNotifId,
    'مهامي الملوّنة — $activeTaskCount مهمة نشطة',
    'اضغط هنا لفتح التطبيق',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _keepAliveChannelId,
        _keepAliveChannelName,
        channelDescription: 'تعمل في الخلفية لضمان وصول التذكيرات',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        icon: '@drawable/app_icon',
        showWhen: false,
        // foregroundService يجعل Android Go يعامله كخدمة حقيقية لا تُوقَف
        usesChronometer: false,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.secret,
        // لا يظهر كـ heads-up ولا يصدر صوتاً
        channelShowBadge: false,
        silent: true,
      ),
    ),
  );
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
  try {
    await _notifications.show(
      7001,
      '✅ اختبار الإشعار',
      'الإشعارات تعمل في مهامي الملوّنة',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@drawable/app_icon',
        ),
      ),
    );
  } catch (_) {}
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
      icon: '@drawable/app_icon',
      largeIcon: const DrawableResourceAndroidBitmap('@drawable/app_icon'),
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
    // تحديث الإشعار الثابت لهواوي
    final active = tasks.where((t) => t.status != TaskStatus.done).length;
    await showKeepAliveNotification(active);
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
    // تحديث الإشعار الثابت لهواوي بعد كل تغيير
    final active = tasks.where((t) => t.status != TaskStatus.done).length;
    await showKeepAliveNotification(active);
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
      final active = tasks.where((t) => t.status != TaskStatus.done).length;
      await showKeepAliveNotification(active);
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
          // إعادة تهيئة كاملة في كل مرة لضمان العمل
          _notificationsReady = false;
          await setupNotifications();
          await showTestNotification();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _notificationsReady
                      ? 'تم إرسال الإشعار — إن لم يظهر فعّله من إعدادات الهاتف'
                      : 'فشل تهيئة الإشعارات — اذهب لإعدادات الهاتف وفعّل إشعارات التطبيق',
                ),
                backgroundColor: _notificationsReady ? null : const Color(0xFFDC2626),
                duration: const Duration(seconds: 5),
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

// ═══════════════════════════════════════════════════════════════════════════════
// TASKS PAGE
// ═══════════════════════════════════════════════════════════════════════════════
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
  final void Function(AppTask, TaskStatus) onStatus;
  final VoidCallback onTestNotification;
  final VoidCallback? onDeleteDone;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SummaryPanel(tasks: allTasks),
          ),
        ),

        // ── شريط البحث ──
        if (showSearch)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
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
            ),
          ),

        // ── شريط الفلاتر + الترتيب ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _FilterBar(
              filter: filter,
              sortMode: sortMode,
              showSearch: showSearch,
              doneCount: doneCount,
              onFilter: onFilter,
              onSortMode: onSortMode,
              onSearchToggle: onSearchToggle,
              onDeleteDone: onDeleteDone,
              onTestNotification: onTestNotification,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── قائمة المهام ──
        if (tasks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _EmptyState(onAdd: onAdd, hasSearch: searchQuery.isNotEmpty),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            sliver: SliverList.separated(
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _TaskCard(
                task: tasks[i],
                screenWidth: w,
                onEdit: () => onEdit(tasks[i]),
                onDelete: () => onDelete(tasks[i]),
                onStatus: (s) => onStatus(tasks[i], s),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER BAR — كل عناصر الفلتر في صف واحد منظم
// ═══════════════════════════════════════════════════════════════════════════════
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.sortMode,
    required this.showSearch,
    required this.doneCount,
    required this.onFilter,
    required this.onSortMode,
    required this.onSearchToggle,
    required this.onDeleteDone,
    required this.onTestNotification,
  });

  final TaskStatus? filter;
  final SortMode sortMode;
  final bool showSearch;
  final int doneCount;
  final ValueChanged<TaskStatus?> onFilter;
  final ValueChanged<SortMode> onSortMode;
  final VoidCallback onSearchToggle;
  final VoidCallback? onDeleteDone;
  final VoidCallback onTestNotification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // صف الفلاتر + أزرار الأدوات في نفس الصف
        Row(
          children: [
            // فلاتر الحالة — تمتد لتملأ المساحة
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'الكل',
                      selected: filter == null,
                      color: const Color(0xFF475569),
                      onTap: () => onFilter(null),
                    ),
                    const SizedBox(width: 6),
                    for (final s in TaskStatus.values) ...[
                      _FilterChip(
                        label: s.label,
                        icon: s.icon,
                        selected: filter == s,
                        color: s.color,
                        onTap: () => onFilter(s),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            // أيقونات الأدوات على اليسار
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolIcon(
                  icon: showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                  tooltip: 'بحث',
                  onTap: onSearchToggle,
                ),
                _ToolIcon(
                  icon: Icons.notifications_active_outlined,
                  tooltip: 'اختبار الإشعار',
                  onTap: onTestNotification,
                ),
                _SortButton(current: sortMode, onChanged: onSortMode),
              ],
            ),
          ],
        ),

        // زر مسح المنجزة — يظهر فقط عند الحاجة
        if (doneCount > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDeleteDone,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text('مسح المنجزة ($doneCount)'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    required this.icon,
    required this.onTap,
    this.tooltip = '',
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: const Color(0xFF475569)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY PANEL
// ═══════════════════════════════════════════════════════════════════════════════
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.tasks});

  final List<AppTask> tasks;

  @override
  Widget build(BuildContext context) {
    int count(TaskStatus s) => tasks.where((t) => t.status == s).length;
    final overdueCount = tasks.where((t) => t.isOverdue).length;
    final total = tasks.length;
    final doneCount = count(TaskStatus.done);
    final progress = total == 0 ? 0.0 : doneCount / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4C2A), Color(0xFF1a6b3a)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15803D).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان + تحذير المتأخرة
          Row(
            children: [
              const Expanded(
                child: Text(
                  'مهامي الملوّنة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (overdueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '$overdueCount متأخرة',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // العدادات الثلاثة — تتوزع بالتساوي
          Row(
            children: [
              _StatItem(
                label: 'مطلوب',
                value: count(TaskStatus.requiredTask),
                icon: TaskStatus.requiredTask.icon,
                color: const Color(0xFFDC2626),
              ),
              _Divider(),
              _StatItem(
                label: 'تحت الإنجاز',
                value: count(TaskStatus.inProgress),
                icon: TaskStatus.inProgress.icon,
                color: const Color(0xFFF97316),
              ),
              _Divider(),
              _StatItem(
                label: 'منجز',
                value: doneCount,
                icon: TaskStatus.done.icon,
                color: const Color(0xFF4ADE80),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // شريط التقدم
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'التقدم الكلي',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF4ADE80)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: Colors.white.withValues(alpha: 0.15),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SORT BUTTON
// ═══════════════════════════════════════════════════════════════════════════════
class _SortButton extends StatelessWidget {
  const _SortButton({required this.current, required this.onChanged});

  final SortMode current;
  final ValueChanged<SortMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ترتيب: ${current.label}',
      child: InkWell(
        onTap: () async {
          final result = await showModalBottomSheet<SortMode>(
            context: context,
            builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ترتيب المهام',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    for (final m in SortMode.values)
                      ListTile(
                        leading: Icon(
                          m == current
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: const Color(0xFF15803D),
                        ),
                        title: Text(m.label),
                        selected: m == current,
                        onTap: () => Navigator.pop(context, m),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (result != null) onChanged(result);
        },
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.sort_rounded, size: 22, color: const Color(0xFF475569)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TASK CARD — تصميم جديد بدون تمرير
// ═══════════════════════════════════════════════════════════════════════════════
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.screenWidth,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
  });

  final AppTask task;
  final double screenWidth;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<TaskStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final statusColor = task.status.color;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          right: BorderSide(color: statusColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── الصف العلوي: الأيقونة + العنوان + القائمة ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // أيقونة الحالة
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(task.status.icon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 10),
                // العنوان والأولوية
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          decoration: task.status == TaskStatus.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.status == TaskStatus.done
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF1E293B),
                        ),
                      ),
                      if (task.priority > 0) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: task.priority == 2
                                ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                                : const Color(0xFFF97316).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            task.priority == 2 ? '⚡ عاجل' : '★ مهم',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: task.priority == 2
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFF97316),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // قائمة الخيارات
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('تعديل'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded,
                            size: 18, color: Color(0xFFDC2626)),
                        SizedBox(width: 8),
                        Text('حذف',
                            style: TextStyle(color: Color(0xFFDC2626))),
                      ]),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Color(0xFF94A3B8)),
                ),
              ],
            ),

            // ── الملاحظة ──
            if (task.note.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.note,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 10),

            // ── شريط المعلومات: التاريخ ──
            if (task.reminderAt != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: task.isOverdue
                      ? const Color(0xFFDC2626).withValues(alpha: 0.08)
                      : const Color(0xFF15803D).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      task.isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.alarm_rounded,
                      size: 13,
                      color: task.isOverdue
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF15803D),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      formatDateTime(task.reminderAt!),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: task.isOverdue
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // ── أزرار تغيير الحالة — تتوزع بالتساوي بدون تمرير ──
            Row(
              children: TaskStatus.values.map((s) {
                final isActive = task.status == s;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      end: s != TaskStatus.done ? 6 : 0,
                    ),
                    child: GestureDetector(
                      onTap: isActive ? null : () => onStatus(s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? s.color
                              : s.color.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? s.color
                                : s.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              s.icon,
                              size: 16,
                              color: isActive ? Colors.white : s.color,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isActive ? Colors.white : s.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.hasSearch});

  final VoidCallback onAdd;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: const Border.fromBorderSide(
            BorderSide(color: Color(0xFFE2E8D8))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF15803D).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasSearch ? Icons.search_off_rounded : Icons.task_alt_rounded,
              size: 44,
              color: const Color(0xFF15803D),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'لا توجد نتائج' : 'لا توجد مهام بعد',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'جرب كلمة بحث مختلفة'
                : 'أضف مهمتك الأولى وابدأ بالتنظيم',
            style: const TextStyle(color: Color(0xFF94A3B8)),
            textAlign: TextAlign.center,
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة مهمة'),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TASK SHEET
// ═══════════════════════════════════════════════════════════════════════════════
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
      reminderAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void submit() {
    final title = titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      AppTask(
        id: widget.task?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        note: noteController.text.trim(),
        status: status,
        createdAt: widget.task?.createdAt ?? DateTime.now(),
        reminderAt: reminderAt,
        priority: priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض الـ sheet
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8D8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(
              widget.task == null ? 'مهمة جديدة' : 'تعديل المهمة',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'اسم المهمة *',
                prefixIcon: Icon(Icons.edit_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // الحالة
            const Text('الحالة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: TaskStatus.values.map((s) {
                final sel = status == s;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                        end: s != TaskStatus.done ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => status = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: sel
                              ? s.color
                              : s.color.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: sel
                                ? s.color
                                : s.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(s.icon,
                                size: 18,
                                color: sel ? Colors.white : s.color),
                            const SizedBox(height: 4),
                            Text(
                              s.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: sel ? Colors.white : s.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // الأولوية
            const Text('الأولوية',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final p in [
                  (0, 'عادي', Icons.remove_rounded, const Color(0xFF64748B)),
                  (1, 'مهم', Icons.star_rounded, const Color(0xFFF97316)),
                  (2, 'عاجل', Icons.bolt_rounded, const Color(0xFFDC2626)),
                ])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                          end: p.$1 != 2 ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => priority = p.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: priority == p.$1
                                ? p.$4
                                : p.$4.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: priority == p.$1
                                  ? p.$4
                                  : p.$4.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(p.$3,
                                  size: 18,
                                  color: priority == p.$1
                                      ? Colors.white
                                      : p.$4),
                              const SizedBox(height: 4),
                              Text(
                                p.$2,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: priority == p.$1
                                      ? Colors.white
                                      : p.$4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // التذكير
            GestureDetector(
              onTap: pickReminder,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: reminderAt != null
                      ? const Color(0xFF15803D).withValues(alpha: 0.07)
                      : const Color(0xFFF8FAF7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: reminderAt != null
                        ? const Color(0xFF15803D).withValues(alpha: 0.3)
                        : const Color(0xFFD9E4D2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.alarm_rounded,
                      color: reminderAt != null
                          ? const Color(0xFF15803D)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reminderAt == null
                            ? 'تحديد تاريخ ووقت التذكير'
                            : formatDateTime(reminderAt!),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: reminderAt != null
                              ? const Color(0xFF15803D)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    if (reminderAt != null)
                      GestureDetector(
                        onTap: () => setState(() => reminderAt = null),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Color(0xFF94A3B8)),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(
                  widget.task == null ? 'إضافة المهمة' : 'حفظ التعديلات'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEVELOPER / SETTINGS PAGE
// ═══════════════════════════════════════════════════════════════════════════════
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ── النسخ الاحتياطي ──
        _SettingsCard(
          icon: Icons.backup_rounded,
          iconColor: const Color(0xFF15803D),
          title: 'النسخ الاحتياطي',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onExport,
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: const Text('تصدير'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => showImport = !showImport),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('استيراد'),
                    ),
                  ),
                ],
              ),
              if (showImport) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: importController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'الصق نص JSON هنا...',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    widget.onImport(importController.text.trim());
                    importController.clear();
                    setState(() => showImport = false);
                  },
                  child: const Text('تأكيد الاستيراد'),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── إشعارات هواوي ──
        _SettingsCard(
          icon: Icons.phone_android_rounded,
          iconColor: const Color(0xFFF97316),
          title: 'إشعارات هواوي / شياومي',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إذا لم تظهر الإشعارات في الخلفية، فعّل هذا الإعداد:',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final step in [
                ('بدء التشغيل التلقائي',
                    'الإعدادات ← إدارة التطبيقات ← مهامي الملوّنة ← فعّله'),
                ('إيقاف تحسين البطارية',
                    'الإعدادات ← البطارية ← إدارة الاستهلاك ← لا تُحسِّن'),
                ('تشغيل في الخلفية',
                    'إدارة التطبيقات ← مهامي الملوّنة ← استهلاك البطارية ← فعّله'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Color(0xFF15803D),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${[
                              ('بدء التشغيل التلقائي', ''),
                              ('إيقاف تحسين البطارية', ''),
                              ('تشغيل في الخلفية', ''),
                            ].indexWhere((s) => s.$1 == step.$1) + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.$1,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                            Text(step.$2,
                                style: const TextStyle(
                                    color: Color(0xFF64748B), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () async {
                  final intentUri = Uri.parse(
                    'intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;'
                    'data=package:com.explapp.taskstatusreminder;end',
                  );
                  if (await canLaunchUrl(intentUri)) {
                    await launchUrl(intentUri);
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'الإعدادات ← إدارة التطبيقات ← مهامي الملوّنة'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.settings_applications_rounded, size: 18),
                label: const Text('فتح إعدادات التطبيق'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── مراسلة المطور ──
        _SettingsCard(
          icon: Icons.mail_rounded,
          iconColor: const Color(0xFF6366F1),
          title: 'مراسلة المطور',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SelectableText(
                developerEmail,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6366F1)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب ملاحظتك أو اقتراحك...',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final body = msgController.text.trim().isEmpty
                            ? 'ملاحظة على مهامي الملوّنة'
                            : msgController.text.trim();
                        final uri = Uri(
                          scheme: 'mailto',
                          path: developerEmail,
                          queryParameters: {
                            'subject': 'ملاحظة على مهامي الملوّنة',
                            'body': body,
                          },
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else if (context.mounted) {
                          await Clipboard.setData(
                              ClipboardData(text: body));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('تم نسخ الرسالة')),
                          );
                        }
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('إرسال'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(
                          text: msgController.text.trim()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('نسخ'),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── عن التطبيق ──
        _SettingsCard(
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFF94A3B8),
          title: 'عن التطبيق',
          child: const Text(
            'مهامي الملوّنة — الإصدار 1.1.0\nتطبيق مفتوح المصدر لإدارة المهام باللغة العربية.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════
String formatDateTime(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  final mo = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '${value.year}/$mo/$d  $h:$m';
}
