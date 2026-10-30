import 'package:bahay_rent/app.dart';
import 'package:bahay_rent/data/models.dart' hide Row;
import 'package:bahay_rent/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    // Closing a form completes its route animation before it reloads SQLite.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openApp(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      BahayApp(repository: repository, enablePlatformServices: false),
    );
    await settle(tester);
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(NavigationDestination, label));
    await settle(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: '$label should fit a small Android screen',
    );
  }

  Finder field(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(TextFormField))
      .first;

  testWidgets(
    'first offline launch and all five destinations fit a small screen',
    (tester) async {
      await openApp(tester, textScale: 1.3);
      expect(find.text('bahay'), findsOneWidget);
      expect(find.text('Offline ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['Rooms', 'Billing', 'Payments', 'More', 'Home']) {
        await tab(tester, label);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final data = await tester.runAsync(repository.load);
      expect(data!.rooms, isEmpty);
      expect(data.payments, isEmpty);
    },
  );

  testWidgets('room form writes persistent room configuration', (tester) async {
    await openApp(tester);
    await tab(tester, 'Rooms');
    await tester.tap(find.textContaining(RegExp(r'^Add (a )?room$')).first);
    await tester.pumpAndSettle();
    await tester.enterText(field('Room name or number'), 'Sampaguita 1');
    await tester.enterText(field('Monthly rent'), '4500.00');
    final save = find.text('Add room').last;
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await settle(tester);
    final data = await tester.runAsync(repository.load);
    expect(data!.rooms.single['name'], 'Sampaguita 1');
    expect(data.rooms.single['rent_cents'], 450000);
    expect(find.text('Sampaguita 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'partial payment through the form updates the ledger and outstanding balance',
    (tester) async {
      late int invoiceId;
      await tester.runAsync(() async {
        final roomId = await repository.saveRoom({
          'name': 'Sampaguita 1',
          'rent_cents': 450000,
          'electricity_mode': 'fixed',
          'electricity_rate': 30000,
          'water_mode': 'fixed',
          'water_rate': 10000,
          'notes': '',
        });
        final tenancyId = await repository.assignTenant(
          roomId: roomId,
          name: 'Maria Santos',
          phone: '09171234567',
          moveIn: '2026-01-01',
          rentCents: 450000,
          depositCents: 450000,
          dueDay: 5,
        );
        final period = billingPeriod(manilaNow());
        invoiceId = await repository.saveDraft(
          tenancyId: tenancyId,
          period: period,
          dueDate: '$period-05',
        );
        await repository.finalizeInvoice(invoiceId);
      });
      await openApp(tester);
      await tab(tester, 'Payments');
      final record = find.text('Record a payment');
      await tester.ensureVisible(record);
      await tester.pumpAndSettle();
      await tester.tap(record);
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount received'), '2000.00');
      final save = find.text('Save payment');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await settle(tester);
      final data = await tester.runAsync(repository.load);
      expect(data!.payments, hasLength(1));
      expect(data.paid(invoiceId), 200000);
      expect(data.balance(invoiceId), 290000);
      expect(data.depositBalance(data.tenancies.single['id']), 450000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant assignment and meter worksheet finalize exact monthly charges',
    (tester) async {
      await tester.runAsync(
        () => repository.saveRoom({
          'name': 'Sampaguita 2',
          'rent_cents': 450000,
          'electricity_mode': 'metered',
          'electricity_rate': 1250,
          'water_mode': 'metered',
          'water_rate': 3500,
          'notes': '',
        }),
      );
      await openApp(tester);
      await tab(tester, 'Rooms');
      final assign = find.text('Assign a tenant');
      await tester.ensureVisible(assign);
      await tester.pumpAndSettle();
      await tester.tap(assign);
      await tester.pumpAndSettle();
      await tester.enterText(field('Full name'), 'Luz Reyes');
      await tester.enterText(field('Contact number (optional)'), '09181234567');
      await tester.enterText(field('Security deposit received'), '4500.00');
      final assignSave = find.text('Assign tenant');
      await tester.ensureVisible(assignSave);
      await tester.pumpAndSettle();
      await tester.tap(assignSave);
      await settle(tester);
      var data = (await tester.runAsync(repository.load))!;
      expect(data.tenants.single['name'], 'Luz Reyes');
      expect(data.depositBalance(data.tenancies.single['id']), 450000);
      expect(tester.takeException(), isNull);

      await tab(tester, 'Billing');
      final prepare = find.text('Enter readings & prepare');
      await tester.ensureVisible(prepare);
      await tester.pumpAndSettle();
      await tester.tap(prepare);
      await tester.pumpAndSettle();
      for (final entry in {
        'Initial previous reading (kWh)': '1200.000',
        'Current reading (kWh)': '1234.567',
        'Initial previous reading (m³)': '75.000',
        'Current reading (m³)': '79.125',
        'Adjustment or discount': '-50.00',
        'Adjustment reason (if any)': 'Agreed first-month discount',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.pumpAndSettle();
        await tester.enterText(field(entry.key), entry.value);
      }
      final draftSave = find.text('Save draft');
      await tester.ensureVisible(draftSave);
      await tester.pumpAndSettle();
      await tester.tap(draftSave);
      await settle(tester);
      data = (await tester.runAsync(repository.load))!;
      final invoiceId = data.invoices.single['id'] as int;
      expect(data.invoices.single['status'], 'draft');
      final electric = data.lines.singleWhere(
        (line) => line['kind'] == 'electricity',
      );
      final water = data.lines.singleWhere((line) => line['kind'] == 'water');
      expect(electric['quantity'], 34567);
      expect(electric['amount_cents'], 43209);
      expect(water['quantity'], 4125);
      expect(water['amount_cents'], 14438);
      expect(data.invoices.single['total_cents'], 502647);
      expect(tester.takeException(), isNull);

      final finalize = find.text('Finalize bill');
      await tester.ensureVisible(finalize);
      await tester.pumpAndSettle();
      await tester.tap(finalize);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Finalize bill'),
        ),
      );
      await settle(tester);
      data = (await tester.runAsync(repository.load))!;
      expect(data.invoices.single['status'], 'final');
      expect(data.balance(invoiceId), 502647);
      expect(data.depositBalance(data.tenancies.single['id']), 450000);
      expect(data.payments, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
