import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initialization;
  static Future<void> _pending = Future<void>.value();
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rental_reminders',
      'Rental reminders',
      channelDescription:
          'Due dates, meter readings, and draft bills stored on this phone.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
    ),
  );

  static Future<void> initialize() => _initialization ??= _initialize();
  static Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
  }

  static Future<bool> requestPermission() async {
    await initialize();
    if (!Platform.isAndroid) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> reschedule(AppData data) {
    _pending = _pending.catchError((_) {}).then((_) => _reschedule(data));
    return _pending;
  }

  static Future<void> _reschedule(AppData data) async {
    if (!Platform.isAndroid) return;
    await initialize();
    await _plugin.cancelAll();
    if (data.settings['reminders'] != 'true') return;
    final now = tz.TZDateTime.now(tz.local);
    final notices = plan(data, DateTime(now.year, now.month, now.day));
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
      await _plugin.zonedSchedule(
        id++,
        notice.title,
        notice.body,
        date,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Planning uses calendar dates in Manila. Refreshed after every saved change.
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
            '${parts.join(' · ')}. Open Bahay Rent to review.',
          ),
        );
      }
    }
    final meterDay = (int.tryParse(data.settings['meter_day'] ?? '') ?? 25)
        .clamp(1, 28);
    for (var month = 0; month < 12; month++) {
      final date = DateTime(today.year, today.month + month, meterDay);
      if (date.isBefore(today)) continue;
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
