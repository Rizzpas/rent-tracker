import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:upa_renta/app.dart';
import 'package:upa_renta/data/repository.dart';
import 'package:upa_renta/ui/collections_page.dart';

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
    await repository.close();
  });

  test(
    'CollectionsSchedule groups due-this-week, overdue, needs-billing, and collected-today in Manila time',
    () async {
      // Fix clock to 2026-02-25 10:00 Manila (02:00 UTC).
      // 7-day window: 2026-02-25 .. 2026-03-03 (crosses end of February!).
      final clock = DateTime.utc(2026, 2, 25, 2, 0);

      final r1 = await repository.saveRoom({
        'name': 'Room 101',
        'rent_cents': 500000,
        'electricity_mode': 'fixed',
        'electricity_rate': 20000,
        'water_mode': 'fixed',
        'water_rate': 10000,
      });
      final r2 = await repository.saveRoom({
        'name': 'Room 102',
        'rent_cents': 600000,
        'electricity_mode': 'fixed',
        'electricity_rate': 20000,
        'water_mode': 'fixed',
        'water_rate': 10000,
      });
      final r3 = await repository.saveRoom({
        'name': 'Room 103',
        'rent_cents': 450000,
        'electricity_mode': 'fixed',
        'electricity_rate': 15000,
        'water_mode': 'fixed',
        'water_rate': 10000,
      });

      // Tenant 1: End-of-month (31 -> 2026-02-28), finalized -> due this week!
      final t1 = await repository.assignTenant(
        roomId: r1,
        name: 'Maria EOM',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 500000,
        depositCents: 0,
        dueDay: 31,
      );
      final invDueThisWeek = await repository.saveDraft(
        tenancyId: t1,
        period: '2026-02',
      );
      await repository.finalizeInvoice(invDueThisWeek);

      // Tenant 2: 15th (2026-02-15), finalized -> overdue!
      final t2 = await repository.assignTenant(
        roomId: r2,
        name: 'Jose Overdue',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 600000,
        depositCents: 0,
        dueDay: 15,
      );
      final invOverdue = await repository.saveDraft(
        tenancyId: t2,
        period: '2026-02',
      );
      await repository.finalizeInvoice(invOverdue);

      // Tenant 3: End-of-month (31 -> 2026-02-28), still unbilled -> needsBilling!
      await repository.assignTenant(
        roomId: r3,
        name: 'Ana Unbilled',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 450000,
        depositCents: 0,
        dueDay: 31,
      );

      final data = await repository.load();
      final schedule = CollectionsSchedule.from(data, clock: clock);
      expect(schedule.today, '2026-02-25');
      expect(schedule.weekEnd, '2026-03-03');
      expect(schedule.dueThisWeek.single['id'], invDueThisWeek);
      expect(schedule.dueThisWeek.single['due_date'], '2026-02-28');
      expect(schedule.overdue.single['id'], invOverdue);
      expect(schedule.needsBilling, hasLength(1));
      expect(schedule.needsBilling.single.dueDate, '2026-02-28');
    },
  );

  testWidgets(
    'Collections Day records full payment and triggers receipt in 2 taps (<3 taps)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = DateTime.utc(2026, 11, 3, 1, 0); // 2026-11-03 Manila
      late int invoiceId;
      await tester.runAsync(() async {
        final roomId = await repository.saveRoom({
          'name': 'Room 101',
          'rent_cents': 500000,
          'electricity_mode': 'fixed',
          'electricity_rate': 25000,
          'water_mode': 'fixed',
          'water_rate': 15000,
        });
        final tenancyId = await repository.assignTenant(
          roomId: roomId,
          name: 'Maria Santos',
          phone: '09171234567',
          moveIn: '2026-10-01',
          rentCents: 500000,
          depositCents: 0,
          dueDay: 5,
        );
        invoiceId = await repository.saveDraft(
          tenancyId: tenancyId,
          period: '2026-11',
        );
        await repository.finalizeInvoice(invoiceId);
      });

      int? receiptOpenedForPayment;
      final initialData = (await tester.runAsync(repository.load))!;

      await tester.pumpWidget(
        MaterialApp(
          home: CollectionsScreen(
            initialData: initialData,
            repository: repository,
            onChanged: () {},
            manilaClock: clock,
            onOpenReceipt: (data, paymentId) async {
              receiptOpenedForPayment = paymentId;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Maria Santos'), findsOneWidget);
      expect(find.text('₱5,400.00'), findsWidgets);

      // SINGLE TAP on Collections Day records payment AND generates receipt!
      await tester.tap(find.byKey(ValueKey('pay-receipt-$invoiceId')));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();

      final updated = (await tester.runAsync(repository.load))!;
      expect(updated.balance(invoiceId), 0);
      expect(updated.payments, hasLength(1));
      expect(updated.payments.single['date'], '2026-11-03');
      expect(receiptOpenedForPayment, updated.payments.single['id']);
      expect(find.text('Collected today (1)'), findsOneWidget);
    },
  );

  testWidgets(
    'Record paid + Receipt button completes in 2 taps and supports GCash chip',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = DateTime.utc(2026, 11, 13, 1, 0); // Nov 13 -> Nov 15 due this week
      late int invoiceId;
      await tester.runAsync(() async {
        final roomId = await repository.saveRoom({
          'name': 'Room 202',
          'rent_cents': 480000,
          'electricity_mode': 'fixed',
          'electricity_rate': 0,
          'water_mode': 'fixed',
          'water_rate': 0,
        });
        final tenancyId = await repository.assignTenant(
          roomId: roomId,
          name: 'Carlo Reyes',
          phone: '',
          moveIn: '2026-01-01',
          rentCents: 480000,
          depositCents: 0,
          dueDay: 15,
        );
        invoiceId = await repository.saveDraft(
          tenancyId: tenancyId,
          period: '2026-11',
        );
        await repository.finalizeInvoice(invoiceId);
      });

      int? openedReceiptId;
      final initialData = (await tester.runAsync(repository.load))!;

      await tester.pumpWidget(
        MaterialApp(
          home: CollectionsScreen(
            initialData: initialData,
            repository: repository,
            onChanged: () {},
            manilaClock: clock,
            onOpenReceipt: (_, id) async => openedReceiptId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('collect-method-GCash')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('record-paid-$invoiceId')));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();

      final updated = (await tester.runAsync(repository.load))!;
      final paymentId = updated.payments.single['id'] as int;
      expect(updated.payments.single['method'], 'GCash');
      expect(find.textContaining('Paid ₱4,800.00 (GCash)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final receiptBtn = find.byKey(ValueKey('receipt-today-$paymentId'));
      await tester.ensureVisible(receiptBtn);
      await tester.pumpAndSettle();
      await tester.tap(receiptBtn);
      await tester.pumpAndSettle();
      expect(openedReceiptId, paymentId);
    },
  );

  testWidgets('Top Collect button in UpaRentaApp opens Collections Day in 1 tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      UpaRentaApp(repository: repository, enablePlatformServices: false),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('top-collections-day')));
    await tester.pumpAndSettle();
    expect(find.text('Who is due this week'), findsOneWidget);
  });
}
