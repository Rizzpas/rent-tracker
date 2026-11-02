import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:upa_renta/data/repository.dart';
import 'package:upa_renta/services/reminders.dart';
import 'package:upa_renta/ui/more_page.dart';
import 'package:upa_renta/ui/payments_page.dart';
import 'package:upa_renta/ui/rooms_page.dart';

class _TestReminderPlatform implements ReminderPlatform {
  @override
  bool isSupported = true;
  int shownCount = 0;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime date,
  }) async {}
  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    shownCount++;
  }
}

void main() {
  sqfliteFfiInit();
  late RentalRepository repository;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    repository = await RentalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    ReminderService.resetForTesting(AndroidReminderPlatform());
    await repository.close();
  });

  Future<void> settleEditor(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 180)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MorePage triggers test notification, updates meter day to End of month, and opens lazy history pages',
    (tester) async {
      final fakeReminders = _TestReminderPlatform();
      ReminderService.resetForTesting(fakeReminders);

      await tester.runAsync(() async {
        final r = await repository.saveRoom({
          'name': 'Room 101',
          'rent_cents': 500000,
          'electricity_mode': 'fixed',
          'electricity_rate': 10000,
          'water_mode': 'fixed',
          'water_rate': 5000,
        });
        final t = await repository.assignTenant(
          roomId: r,
          name: 'Elena Gomez',
          phone: '09170001111',
          moveIn: '2026-01-01',
          rentCents: 500000,
          depositCents: 500000,
          dueDay: 30,
        );
        final inv = await repository.saveDraft(tenancyId: t, period: '2026-02');
        await repository.finalizeInvoice(inv);
        await repository.recordPayment(
          invoiceId: inv,
          amountCents: 515000,
          date: '2026-02-28',
          method: 'Cash',
          requestId: 'pages-test-1',
        );
      });

      var data = (await tester.runAsync(repository.load))!;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MorePage(
                  data: data,
                  repository: repository,
                  onChanged: () async {
                    final fresh = await repository.load();
                    setState(() => data = fresh);
                  },
                  period: '2026-02',
                  enablePlatformServices: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      // Verify Send test notification works end-to-end.
      final testNotif = find.text('Send test notification');
      await tester.ensureVisible(testNotif);
      await tester.pumpAndSettle();
      await tester.tap(testNotif);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(fakeReminders.shownCount, 1);
      expect(
        find.textContaining('Test notification sent!'),
        findsOneWidget,
      );

      // Update meter reading day to End of month (31).
      final meterTile = find.text('Meter reading day');
      await tester.ensureVisible(meterTile);
      await tester.pumpAndSettle();
      await tester.tap(meterTile);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'End of month'));
      await tester.pumpAndSettle();
      final saveBtn = find.text('Save');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await settleEditor(tester);
      final savedSettings = (await tester.runAsync(repository.load))!.settings;
      expect(savedSettings['meter_day'], '31');

      // Open lazy Bills & payment history page and toggle Payments chip.
      final historyTile = find.text('Bills & payment history');
      await tester.ensureVisible(historyTile);
      await tester.pumpAndSettle();
      await tester.tap(historyTile);
      await tester.pumpAndSettle();
      expect(find.text('Elena Gomez'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Payments'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RCP-'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Open lazy Tenancy & deposit history page.
      final tenancyTile = find.text('Tenancy & deposit history');
      await tester.ensureVisible(tenancyTile);
      await tester.pumpAndSettle();
      await tester.tap(tenancyTile);
      await tester.pumpAndSettle();
      expect(find.text('Every 30th'), findsOneWidget);
    },
  );

  testWidgets('RoomsPage displays readable due schedule and settles deposit after move-out', (
    tester,
  ) async {
    late int tenancyId;
    await tester.runAsync(() async {
      final r = await repository.saveRoom({
        'name': 'Narra 1',
        'rent_cents': 400000,
        'electricity_mode': 'fixed',
        'electricity_rate': 0,
        'water_mode': 'fixed',
        'water_rate': 0,
      });
      tenancyId = await repository.assignTenant(
        roomId: r,
        name: 'Paolo Lim',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 400000,
        depositCents: 400000,
        dueDay: 31,
      );
    });

    var data = (await tester.runAsync(repository.load))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomsPage(
              data: data,
              repository: repository,
              onChanged: () {},
              period: '2026-02',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('End of month'), findsOneWidget);
    expect(data.tenancy(tenancyId)!['due_day'], 31);
  });

  testWidgets('PaymentsPage reverses a payment with audit reason', (
    tester,
  ) async {
    late int invoiceId;
    await tester.runAsync(() async {
      final r = await repository.saveRoom({
        'name': 'Acacia 1',
        'rent_cents': 350000,
        'electricity_mode': 'fixed',
        'electricity_rate': 0,
        'water_mode': 'fixed',
        'water_rate': 0,
      });
      final t = await repository.assignTenant(
        roomId: r,
        name: 'Rosa Tan',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 350000,
        depositCents: 0,
        dueDay: 5,
      );
      invoiceId = await repository.saveDraft(tenancyId: t, period: '2026-02');
      await repository.finalizeInvoice(invoiceId);
      await repository.recordPayment(
        invoiceId: invoiceId,
        amountCents: 350000,
        date: '2026-02-05',
        method: 'Cash',
        requestId: 'rev-test',
      );
    });

    var data = (await tester.runAsync(repository.load))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PaymentsPage(
              data: data,
              repository: repository,
              onChanged: () {},
              period: '2026-02',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rosa Tan'));
    await tester.pumpAndSettle();
    final correctBtn = find.text('Correct this payment');
    await tester.ensureVisible(correctBtn);
    await tester.pumpAndSettle();
    await tester.tap(correctBtn);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField),
      'Posted to wrong room',
    );
    await tester.tap(find.text('Reverse payment'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    final reloaded = (await tester.runAsync(repository.load))!;
    expect(reloaded.balance(invoiceId), 350000);
    expect(reloaded.payments.single['reversal_reason'], 'Posted to wrong room');
  });
}
