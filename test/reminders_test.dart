import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:upa_renta/data/models.dart';
import 'package:upa_renta/services/reminders.dart';

class FakeReminderPlatform implements ReminderPlatform {
  @override
  bool isSupported = true;
  bool permissionResult = true;
  bool notificationsEnabled = true;
  bool failNextInit = false;
  int initCalls = 0;
  int cancelCalls = 0;
  final List<({int id, String title, String body, tz.TZDateTime date})>
  scheduled = [];
  final List<({int id, String title, String body})> shownNow = [];

  @override
  Future<void> initialize() async {
    initCalls++;
    if (failNextInit) {
      failNextInit = false;
      throw StateError('Transient notification init failure');
    }
  }

  @override
  Future<bool> requestPermission() async => permissionResult;

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    scheduled.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
  }) async {
    scheduled.add((id: id, title: title, body: body, date: date));
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    shownNow.add((id: id, title: title, body: body));
  }
}

void main() {
  late FakeReminderPlatform fake;

  setUp(() {
    fake = FakeReminderPlatform();
    ReminderService.resetForTesting(fake);
  });

  tearDown(() {
    ReminderService.resetForTesting(AndroidReminderPlatform());
  });

  AppData buildData({
    String reminders = 'true',
    String meterDay = '31',
    String dueDate = '2026-02-28',
  }) => AppData(
    rooms: [
      {'id': 1, 'name': 'Room 101', 'archived': 0},
    ],
    tenants: [
      {'id': 1, 'name': 'Maria Santos'},
    ],
    tenancies: [
      {
        'id': 1,
        'room_id': 1,
        'tenant_id': 1,
        'move_in': '2026-01-01',
        'move_out': null,
      },
    ],
    readings: [],
    invoices: [
      {
        'id': 1,
        'tenancy_id': 1,
        'room_id': 1,
        'period': '2026-02',
        'due_date': dueDate,
        'status': 'final',
        'total_cents': 500000,
        'reference': 'BILL-000001',
      },
    ],
    lines: [],
    payments: [],
    allocations: [],
    deposits: [],
    audit: [],
    settings: {'reminders': reminders, 'meter_day': meterDay},
  );

  test('recovers cleanly if initial platform initialization fails once', () async {
    fake.failNextInit = true;
    await expectLater(ReminderService.initialize(), throwsStateError);
    await ReminderService.initialize();
    expect(fake.initCalls, 2);
  });

  test('sendTestNotification verifies permission and displays Manila status', () async {
    final clock = DateTime.utc(2026, 2, 25, 1, 0); // Feb 25, 9:00 AM Manila
    await ReminderService.sendTestNotification(
      buildData(dueDate: '2026-02-28'),
      clock: clock,
    );
    expect(fake.shownNow, hasLength(1));
    expect(fake.shownNow.single.title, 'Upa Renta notifications are active');
    expect(fake.shownNow.single.body, contains('1 due this week'));
    expect(fake.shownNow.single.body, contains('2026-02-25'));

    fake.permissionResult = false;
    await expectLater(
      ReminderService.sendTestNotification(buildData(), clock: clock),
      throwsFormatException,
    );
  });

  test(
    'reschedule deduplicates unchanged plans, caps IPC batch size, and cancels when disabled',
    () async {
      final data = buildData(reminders: 'true', dueDate: '2020-01-05');
      await ReminderService.reschedule(data);
      expect(fake.cancelCalls, 1);
      expect(fake.scheduled, isNotEmpty);
      expect(
        fake.scheduled.length,
        lessThanOrEqualTo(ReminderService.maxScheduledNotices),
      );
      expect(
        fake.scheduled.first.date.location.name,
        'Asia/Manila',
      );

      // Calling reschedule again with identical ledger skips redundant IPC.
      await ReminderService.reschedule(data);
      expect(fake.cancelCalls, 1);

      // Disabling reminders cancels all scheduled alarms.
      await ReminderService.reschedule(buildData(reminders: 'false'));
      expect(fake.cancelCalls, 2);
      expect(fake.scheduled, isEmpty);
    },
  );

  test('plan clamps meter_day 31 to Feb 28 (common) and Feb 29 (leap)', () {
    final commonFeb = ReminderService.plan(
      buildData(meterDay: '31'),
      DateTime(2026, 2, 1),
    );
    expect(
      commonFeb.any(
        (n) =>
            n.date == DateTime(2026, 2, 28) &&
            n.title == 'Time to read the meters',
      ),
      isTrue,
    );

    final leapFeb = ReminderService.plan(
      buildData(meterDay: '31'),
      DateTime(2028, 2, 1),
    );
    expect(
      leapFeb.any(
        (n) =>
            n.date == DateTime(2028, 2, 29) &&
            n.title == 'Time to read the meters',
      ),
      isTrue,
    );
  });
}

