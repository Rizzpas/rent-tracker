import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

/// Platform adapter for local notifications so reminder scheduling, permission
/// checks, and test notifications can be verified deterministically in tests.
abstract class ReminderPlatform {
  bool get isSupported;
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<bool> areNotificationsEnabled();
  Future<void> cancelAll();
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
  });
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  });
}

class AndroidReminderPlatform implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationChannel(
    'upa_renta_reminders',
    'Upa Renta reminders',
    description:
        'Due dates, Collections Day check-ins, meter readings, and draft bills stored on this phone.',
    importance: Importance.high,
  );

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'upa_renta_reminders',
      'Upa Renta reminders',
      channelDescription:
          'Due dates, Collections Day check-ins, meter readings, and draft bills stored on this phone.',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      icon: 'ic_notification',
    ),
  );

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_channel);
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    if (granted != null) return granted;
    return await android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    if (!isSupported) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<void> cancelAll() async {
    if (!isSupported) return;
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
  }) async {
    if (!isSupported) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      date,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    await _plugin.show(id, title, body, _details);
  }
}

class ReminderService {
  static ReminderPlatform platform = AndroidReminderPlatform();
  static Future<void>? _initialization;
  static Future<void> _pending = Future<void>.value();
  static String? _lastScheduleSignature;

  /// Maximum number of upcoming notices registered in Android AlarmManager at
  /// once. Keeps Binder IPC fast on low-end phones while covering a full month.
  static const int maxScheduledNotices = 32;

  @visibleForTesting
  static void resetForTesting([ReminderPlatform? customPlatform]) {
    if (customPlatform != null) platform = customPlatform;
    _initialization = null;
    _pending = Future<void>.value();
    _lastScheduleSignature = null;
  }

  static Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object error) {
        _initialization = null;
        throw error;
      });

  static Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    if (!platform.isSupported) return;
    await platform.initialize();
  }

  static Future<bool> requestPermission() async {
    await initialize();
    if (!platform.isSupported) return false;
    return platform.requestPermission();
  }

  static Future<bool> areNotificationsEnabled() async {
    await initialize();
    if (!platform.isSupported) return false;
    return platform.areNotificationsEnabled();
  }

  /// Sends an immediate local notification so the landlady can verify on her
  /// phone that notification permissions, channel, and alerts are working.
  static Future<void> sendTestNotification(
    AppData data, {
    DateTime? clock,
  }) async {
    await initialize();
    if (!platform.isSupported) return;
    final permitted = await platform.requestPermission();
    if (!permitted) {
      throw const FormatException(
        'Notifications are blocked. Enable Upa Renta notifications in your phone settings first.',
      );
    }
    final todayIso = manilaToday(clock);
    final dueThisWeek = data.invoices
        .where(
          (b) =>
              b['status'] == 'final' &&
              data.balance(b['id'] as int) > 0 &&
              isDueThisWeek(b['due_date'] as String, clock: clock),
        )
        .length;
    final overdue = data.invoices
        .where(
          (b) =>
              b['status'] == 'final' &&
              data.balance(b['id'] as int) > 0 &&
              (b['due_date'] as String).compareTo(todayIso) < 0,
        )
        .length;
    final summary = <String>[
      if (overdue > 0) '$overdue overdue',
      if (dueThisWeek > 0) '$dueThisWeek due this week',
      if (overdue == 0 && dueThisWeek == 0) 'All finalized bills are up to date',
    ].join(' · ');
    await platform.showNow(
      id: 999,
      title: 'Upa Renta notifications are active',
      body: '$summary · Asia/Manila ($todayIso).',
    );
  }

  static Future<void> reschedule(AppData data, {bool force = false}) {
    _pending = _pending
        .catchError((_) {})
        .then((_) => _reschedule(data, force: force));
    return _pending;
  }

  static Future<void> _reschedule(AppData data, {required bool force}) async {
    if (!platform.isSupported) return;
    await initialize();
    if (data.settings['reminders'] != 'true') {
      if (_lastScheduleSignature != 'disabled' || force) {
        await platform.cancelAll();
        _lastScheduleSignature = 'disabled';
      }
      return;
    }
    if (!await platform.areNotificationsEnabled()) {
      return;
    }
    final now = tz.TZDateTime.now(tz.local);
    final notices = plan(
      data,
      DateTime.utc(now.year, now.month, now.day),
    ).take(maxScheduledNotices).toList();
    final signature =
        '${isoDate(now)}|${notices.map((n) => '${isoDate(n.date)}:${n.title}:${n.body}').join('|')}';
    if (!force && signature == _lastScheduleSignature) {
      return;
    }
    await platform.cancelAll();
    var id = 1;
    for (final notice in notices) {
      var date = tz.TZDateTime(
        tz.local,
        notice.date.year,
        notice.date.month,
        notice.date.day,
        9,
      );
      if (!date.isAfter(now)) {
        if (isoDate(notice.date) != isoDate(now)) continue;
        date = now.add(const Duration(minutes: 1));
      }
      await platform.schedule(
        id: id++,
        title: notice.title,
        body: notice.body,
        date: date,
      );
    }
    _lastScheduleSignature = signature;
  }

  /// Planning uses calendar dates in `Asia/Manila`. Refreshed after saved changes.
  /// Supports due dates and meter days from 1st to 31st (end-of-month, including February).
  @visibleForTesting
  static List<ReminderNotice> plan(AppData data, DateTime today) {
    final result = <ReminderNotice>[];
    final outstanding = data.invoices
        .where(
          (bill) =>
              bill['status'] == 'final' && data.balance(bill['id'] as int) > 0,
        )
        .toList();
    final drafts = data.invoices
        .where((bill) => bill['status'] == 'draft')
        .length;
    for (var day = 0; day < 90; day++) {
      final date = DateTime(today.year, today.month, today.day + day);
      final dateString = isoDate(date);
      final soon = isoDate(date.add(const Duration(days: 3)));
      final overdue = outstanding
          .where((b) => (b['due_date'] as String).compareTo(dateString) < 0)
          .length;
      final upcoming = outstanding
          .where(
            (b) =>
                (b['due_date'] as String).compareTo(dateString) >= 0 &&
                (b['due_date'] as String).compareTo(soon) <= 0,
          )
          .length;
      final parts = <String>[
        if (overdue > 0) '$overdue bill${overdue == 1 ? '' : 's'} overdue',
        if (upcoming > 0) '$upcoming due within 3 days',
        if (drafts > 0)
          '$drafts draft${drafts == 1 ? '' : 's'} awaiting finalization',
      ];
      if (parts.isNotEmpty) {
        result.add(
          ReminderNotice(
            date,
            'Your rental check-in',
            '${parts.join(' · ')}. Open Upa Renta to review.',
          ),
        );
      }
    }
    final configuredMeterDay =
        (int.tryParse(data.settings['meter_day'] ?? '') ?? 25).clamp(1, 31);
    final baseToday = DateTime(today.year, today.month, today.day);
    for (var monthOffset = 0; monthOffset < 12; monthOffset++) {
      final targetMonth = DateTime(today.year, today.month + monthOffset, 1);
      final actualDay = clampDayToMonth(
        targetMonth.year,
        targetMonth.month,
        configuredMeterDay,
      );
      final date = DateTime(targetMonth.year, targetMonth.month, actualDay);
      if (date.isBefore(baseToday)) continue;
      result.add(
        ReminderNotice(
          date,
          'Time to read the meters',
          'Record this month’s electricity and water readings in Monthly Billing.',
        ),
      );
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }
}

class ReminderNotice {
  final DateTime date;
  final String title, body;
  const ReminderNotice(this.date, this.title, this.body);
}
