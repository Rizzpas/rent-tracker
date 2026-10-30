import 'dart:convert';
import 'dart:io';

import 'package:bahay_rent/data/models.dart';
import 'package:bahay_rent/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late RentalRepository repository;

  Future<int> room({
    String name = 'Room 1',
    String electricityMode = 'metered',
    int electricityRate = 1250,
    String waterMode = 'metered',
    int waterRate = 4000,
  }) => repository.saveRoom({
    'name': name,
    'rent_cents': 500000,
    'electricity_mode': electricityMode,
    'electricity_rate': electricityRate,
    'water_mode': waterMode,
    'water_rate': waterRate,
    'notes': '',
  });

  Future<int> tenant(
    int roomId, {
    String moveIn = '2026-01-01',
    int deposit = 500000,
  }) => repository.assignTenant(
    roomId: roomId,
    name: 'Maria Santos',
    phone: '09171234567',
    moveIn: moveIn,
    rentCents: 500000,
    depositCents: deposit,
    dueDay: 5,
  );

  Future<int> bill(
    int tenancyId, {
    String period = '2026-01',
    int? electricity = 100000,
    int? water = 10000,
    int? electricityPrevious,
    int? waterPrevious,
    int adjustment = 0,
    String adjustmentNote = '',
  }) => repository.saveDraft(
    tenancyId: tenancyId,
    period: period,
    dueDate: '$period-05',
    electricityCurrent: electricity,
    waterCurrent: water,
    electricityPrevious: electricityPrevious,
    waterPrevious: waterPrevious,
    adjustmentCents: adjustment,
    adjustmentNote: adjustmentNote,
  );

  Future<int> payment(
    int invoiceId,
    int amount, {
    String key = 'payment-1',
    String date = '2026-01-06',
  }) => repository.recordPayment(
    invoiceId: invoiceId,
    amountCents: amount,
    date: date,
    method: 'Cash',
    requestId: key,
  );

  Map<String, dynamic> clone(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  setUp(() async {
    repository = await RentalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async {
    await repository.close();
  });

  test('fresh installation contains no example financial data', () async {
    final data = await repository.load();
    expect(data.rooms, isEmpty);
    expect(data.invoices, isEmpty);
    expect(data.payments, isEmpty);
    expect(data.settings['property_name'], 'My rental property');
  });

  test('exact decimal parsing avoids rounding monetary input', () {
    expect(parseFixed('1,234.56'), 123456);
    expect(parseFixed('0.01'), 1);
    expect(parseFixed('-100.25', allowNegative: true), -10025);
    expect(parseFixed('123.456', decimals: 3), 123456);
    expect(() => parseFixed('1.999'), throwsFormatException);
    expect(() => parseFixed('-1'), throwsFormatException);
    // Values that wrap int64 during multiplication must never become small fees.
    expect(() => parseFixed('184467440737095517.00'), throwsFormatException);
    expect(
      () => parseFixed('-92233720368547758.08', allowNegative: true),
      throwsFormatException,
    );
    expect(
      () => parseFixed('99999999999999999999999999999999999'),
      throwsFormatException,
    );
  });

  test(
    'case-insensitive duplicate room names rejected without extra audit writes',
    () async {
      await room();
      await expectLater(room(name: 'room 1'), throwsStateError);
      final data = await repository.load();
      expect(data.rooms, hasLength(1));
      expect(data.audit, hasLength(1));
    },
  );

  test('active and historical assignments cannot overlap', () async {
    final roomId = await room();
    final first = await tenant(roomId);
    await expectLater(tenant(roomId, moveIn: '2026-02-01'), throwsStateError);
    await repository.moveOut(first, '2026-02-15');
    await expectLater(tenant(roomId, moveIn: '2026-02-14'), throwsStateError);
    await tenant(roomId, moveIn: '2026-02-15');
    final data = await repository.load();
    expect(data.tenancies, hasLength(2));
    expect(data.tenants, hasLength(2));
    expect(data.tenancies.first['move_out'], '2026-02-15');
  });

  test('invalid dates and impossible due days rejected', () async {
    final roomId = await room();
    await expectLater(tenant(roomId, moveIn: '2026-02-30'), throwsStateError);
    await expectLater(
      repository.assignTenant(
        roomId: roomId,
        name: 'Tenant',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 100,
        depositCents: 0,
        dueDay: 32,
      ),
      throwsStateError,
    );
    expect((await repository.load()).tenants, isEmpty);
  });

  test(
    'utility product beyond int64 is rejected without overflow or writes',
    () async {
      final tenancyId = await tenant(await room(electricityRate: 900000000000));
      await expectLater(
        bill(tenancyId, electricity: 900000000000),
        throwsStateError,
      );
      final data = await repository.load();
      expect(data.invoices, isEmpty);
      expect(data.lines, isEmpty);
      expect(data.readings, isEmpty);
    },
  );

  test(
    'room meter baseline continues correctly after tenant reassignment',
    () async {
      final roomId = await room();
      final original = await tenant(roomId);
      final january = await bill(
        original,
        electricityPrevious: 10000000,
        electricity: 10100000,
        waterPrevious: 500000,
        water: 510000,
      );
      await repository.finalizeInvoice(january);
      await repository.moveOut(original, '2026-02-01');
      final incoming = await tenant(roomId, moveIn: '2026-02-01');
      final february = await bill(
        incoming,
        period: '2026-02',
        electricity: 10200000,
        water: 520000,
      );
      await repository.finalizeInvoice(february);
      final data = await repository.load();
      final baseline = data.readings.singleWhere(
        (r) => r['invoice_id'] == february && r['kind'] == 'electricity',
      );
      expect(baseline['previous_value'], 10100000);
      expect(data.invoice(january)!['tenancy_id'], original);
      expect(data.invoice(february)!['tenancy_id'], incoming);
      expect(data.invoice(february)!['total_cents'], 665000);
      await repository.validateBackup(await repository.exportData());
    },
  );

  test(
    'archiving occupied rooms is refused; history survives archival',
    () async {
      final roomId = await room();
      final tenancyId = await tenant(roomId);
      await expectLater(repository.archiveRoom(roomId), throwsStateError);
      await repository.moveOut(tenancyId, '2026-03-01');
      await repository.archiveRoom(roomId);
      final data = await repository.load();
      expect(data.room(roomId)!['archived'], 1);
      expect(data.tenancies, hasLength(1));
      await expectLater(tenant(roomId, moveIn: '2026-03-02'), throwsStateError);
    },
  );

  test('meter charges are rounded once to the nearest centavo', () async {
    final tenancyId = await tenant(await room(electricityRate: 1355));
    final id = await bill(tenancyId, electricity: 12345, water: 2000);
    final data = await repository.load();
    // 12.345 kWh * 13.55 pesos = 167.27475 pesos -> 167.27.
    expect(
      data.lines.singleWhere((l) => l['kind'] == 'electricity')['amount_cents'],
      16727,
    );
    expect(data.invoice(id)!['total_cents'], 524727);
  });

  test(
    'first installed reading baseline is explicit and next month is automatic',
    () async {
      final tenancyId = await tenant(await room());
      final first = await bill(
        tenancyId,
        electricityPrevious: 12000000,
        electricity: 12100000,
        waterPrevious: 550000,
        water: 560000,
      );
      await repository.finalizeInvoice(first);
      final second = await bill(
        tenancyId,
        period: '2026-02',
        electricity: 12200000,
        water: 570000,
      );
      final data = await repository.load();
      expect(
        data.readings.singleWhere(
          (r) => r['invoice_id'] == second && r['kind'] == 'electricity',
        )['previous_value'],
        12100000,
      );
      expect(
        data.invoice(second)!['total_cents'],
        data.invoice(first)!['total_cents'],
      );
      await expectLater(
        bill(
          tenancyId,
          period: '2026-02',
          electricityPrevious: 0,
          electricity: 12200000,
          water: 570000,
        ),
        throwsStateError,
      );
    },
  );

  test('invalid meter entry rolls back a draft completely', () async {
    final tenancyId = await tenant(await room());
    final first = await bill(tenancyId);
    await repository.finalizeInvoice(first);
    await expectLater(
      bill(tenancyId, period: '2026-02', electricity: 99999, water: 11000),
      throwsStateError,
    );
    final data = await repository.load();
    expect(data.invoices, hasLength(1));
    expect(data.readings, hasLength(2));
  });

  test(
    'editing a draft replaces line items instead of creating duplicates',
    () async {
      final tenancyId = await tenant(await room());
      final first = await bill(tenancyId);
      final second = await bill(tenancyId, electricity: 150000, water: 12000);
      expect(second, first);
      final data = await repository.load();
      expect(data.invoices, hasLength(1));
      expect(data.lines, hasLength(3));
      expect(data.readings, hasLength(2));
    },
  );

  test('incomplete drafts cannot be finalized or paid', () async {
    final tenancyId = await tenant(await room());
    final id = await bill(tenancyId, electricity: null);
    await expectLater(repository.finalizeInvoice(id), throwsStateError);
    await expectLater(payment(id, 100), throwsStateError);
    expect((await repository.load()).payments, isEmpty);
  });

  test(
    'finalization locks charges despite later room and tenant rate changes',
    () async {
      final roomId = await room();
      final tenancyId = await tenant(roomId);
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      final before = (await repository.load()).invoice(id)!['total_cents'];
      await repository.saveRoom({
        'id': roomId,
        'name': 'Room 1',
        'rent_cents': 900000,
        'electricity_mode': 'fixed',
        'electricity_rate': 999999,
        'water_mode': 'shared',
        'water_rate': 888888,
      });
      await repository.updateTenant(
        tenancyId: tenancyId,
        name: 'Maria Santos',
        phone: '',
        rentCents: 950000,
        dueDay: 10,
      );
      await expectLater(bill(tenancyId), throwsStateError);
      expect((await repository.load()).invoice(id)!['total_cents'], before);
      await repository.finalizeInvoice(id); // Repeated finalize is idempotent.
    },
  );

  test(
    'fixed and shared utility allocations do not require meter readings',
    () async {
      final tenancyId = await tenant(
        await room(
          electricityMode: 'fixed',
          electricityRate: 50000,
          waterMode: 'shared',
          waterRate: 20000,
        ),
      );
      final id = await repository.saveDraft(
        tenancyId: tenancyId,
        period: '2026-01',
        dueDate: '2026-01-05',
        waterSharedCents: 12345,
      );
      await repository.finalizeInvoice(id);
      final data = await repository.load();
      expect(data.readings, isEmpty);
      expect(data.invoice(id)!['total_cents'], 562345);
    },
  );

  test(
    'adjustments require explanation and cannot make a bill negative',
    () async {
      final tenancyId = await tenant(await room());
      await expectLater(bill(tenancyId, adjustment: -10000), throwsStateError);
      await expectLater(
        bill(tenancyId, adjustment: -999999, adjustmentNote: 'Discount'),
        throwsStateError,
      );
      final id = await bill(
        tenancyId,
        adjustment: -10000,
        adjustmentNote: 'Loyalty discount',
      );
      final data = await repository.load();
      expect(
        data.lines.singleWhere(
          (l) => l['kind'] == 'adjustment',
        )['amount_cents'],
        -10000,
      );
      expect(data.invoice(id)!['total_cents'], 655000);
    },
  );

  test(
    'out of order final meter billing cannot corrupt reading history',
    () async {
      final tenancyId = await tenant(await room());
      final jan = await bill(tenancyId);
      final feb = await bill(
        tenancyId,
        period: '2026-02',
        electricity: 200000,
        water: 20000,
      );
      await expectLater(repository.finalizeInvoice(feb), throwsStateError);
      await repository.finalizeInvoice(jan);
      await expectLater(repository.finalizeInvoice(feb), throwsStateError);
      await bill(
        tenancyId,
        period: '2026-02',
        electricity: 200000,
        water: 20000,
      );
      await repository.finalizeInvoice(feb);
      await expectLater(
        bill(tenancyId, period: '2025-12', electricity: 0, water: 0),
        throwsStateError,
      );
    },
  );

  test(
    'a finalized later reading prevents inserting retroactive meter bills',
    () async {
      final tenancyId = await tenant(await room(), moveIn: '2025-01-01');
      final feb = await bill(
        tenancyId,
        period: '2026-02',
        electricity: 200000,
        water: 20000,
      );
      await repository.finalizeInvoice(feb);
      await expectLater(bill(tenancyId), throwsStateError);
      expect((await repository.load()).invoices, hasLength(1));
    },
  );

  test(
    'partial and multiple payments reduce only their allocated invoice',
    () async {
      final tenancyId = await tenant(await room());
      final jan = await bill(tenancyId);
      await repository.finalizeInvoice(jan);
      final feb = await bill(
        tenancyId,
        period: '2026-02',
        electricity: 200000,
        water: 20000,
      );
      await repository.finalizeInvoice(feb);
      await payment(jan, 100000);
      await payment(jan, 200000, key: 'payment-2');
      final data = await repository.load();
      expect(data.paid(jan), 300000);
      expect(data.balance(jan), 365000);
      expect(data.balance(feb), 665000);
      // Carry-forward stays derived: February new charges do not include January balance.
      expect(
        data.invoices.fold<int>(0, (n, i) => n + data.balance(i['id'] as int)),
        1030000,
      );
    },
  );

  test(
    'payment request IDs prevent repeated taps and detect conflicting requests',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      final results = await Future.wait([
        payment(id, 100000),
        payment(id, 100000),
      ]);
      expect(results[0], results[1]);
      await expectLater(payment(id, 100001), throwsStateError);
      final data = await repository.load();
      expect(data.payments, hasLength(1));
      expect(data.allocations, hasLength(1));
      expect(data.paid(id), 100000);
    },
  );

  test(
    'overpayments, negative payments, and zero payments do not change balances',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      await expectLater(payment(id, 665001), throwsStateError);
      await expectLater(payment(id, -1), throwsStateError);
      await expectLater(payment(id, 0), throwsStateError);
      expect((await repository.load()).payments, isEmpty);
      await payment(id, 665000);
      expect((await repository.load()).balance(id), 0);
    },
  );

  test(
    'payment reversal preserves original transaction, reason, and audit trail',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      final paymentId = await payment(id, 100000);
      await expectLater(
        repository.reversePayment(paymentId, ' '),
        throwsStateError,
      );
      await repository.reversePayment(paymentId, 'Entered for the wrong bill');
      await expectLater(
        repository.reversePayment(paymentId, 'Again'),
        throwsStateError,
      );
      final data = await repository.load();
      expect(data.payments, hasLength(1));
      expect(data.allocations, hasLength(1));
      expect(data.balance(id), 665000);
      expect(
        data.payments.first['reversal_reason'],
        'Entered for the wrong bill',
      );
      expect(data.audit.where((a) => a['action'] == 'reversed'), hasLength(1));
    },
  );

  test(
    'payment received in another month retains its actual collection date',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      await payment(id, 100000, date: '2026-03-02');
      final data = await repository.load();
      expect(data.invoices.first['period'], '2026-01');
      expect(data.payments.first['date'], '2026-03-02');
      expect(data.paid(id), 100000);
    },
  );

  test(
    'deposits are separate from rent and settle without overdrawing',
    () async {
      final tenancyId = await tenant(await room());
      final before = await repository.load();
      expect(before.depositBalance(tenancyId), 500000);
      expect(before.payments, isEmpty);
      await expectLater(
        repository.settleDeposit(
          tenancyId: tenancyId,
          kind: 'refund',
          amountCents: 100000,
          date: '2026-03-01',
          notes: 'Refund',
        ),
        throwsStateError,
      );
      await repository.moveOut(tenancyId, '2026-03-01');
      await repository.settleDeposit(
        tenancyId: tenancyId,
        kind: 'deduction',
        amountCents: 100000,
        date: '2026-03-01',
        notes: 'Authorized repair deduction',
      );
      await repository.settleDeposit(
        tenancyId: tenancyId,
        kind: 'refund',
        amountCents: 400000,
        date: '2026-03-01',
        notes: 'Returned remainder',
      );
      await expectLater(
        repository.settleDeposit(
          tenancyId: tenancyId,
          kind: 'refund',
          amountCents: 1,
          date: '2026-03-01',
          notes: 'Extra',
        ),
        throwsStateError,
      );
      final data = await repository.load();
      expect(data.depositBalance(tenancyId), 0);
      expect(data.deposits, hasLength(3));
      expect(data.payments, isEmpty);
    },
  );

  test(
    'move-out and reassignment preserve former tenant invoice and debt',
    () async {
      final roomId = await room();
      final firstTenant = await tenant(roomId);
      final invoiceId = await bill(firstTenant);
      await repository.finalizeInvoice(invoiceId);
      await repository.moveOut(firstTenant, '2026-02-01');
      final secondTenant = await tenant(roomId, moveIn: '2026-02-01');
      final data = await repository.load();
      expect(data.invoice(invoiceId)!['tenancy_id'], firstTenant);
      expect(data.activeTenancy(roomId)!['id'], secondTenant);
      expect(data.balance(invoiceId), 665000);
      expect(data.tenants, hasLength(2));
    },
  );

  test('invalid move-out cannot orphan invoices outside occupancy', () async {
    final tenancyId = await tenant(await room());
    await bill(tenancyId);
    await expectLater(
      repository.moveOut(tenancyId, '2026-01-01'),
      throwsStateError,
    );
    await expectLater(
      repository.moveOut(tenancyId, '2025-12-31'),
      throwsStateError,
    );
    expect((await repository.load()).tenancy(tenancyId)!['move_out'], isNull);
  });

  test(
    'backup round trip reproduces all financial totals and history',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      await payment(id, 123456);
      final reversed = await payment(id, 10000, key: 'reversed');
      await repository.reversePayment(reversed, 'Duplicate cash entry');
      await repository.saveSettings({
        'property_name': 'Santos Apartments',
        'meter_day': '24',
      });
      final backup = await repository.exportData();
      await repository.validateBackup(backup);
      final secondRoom = await room(name: 'Temporary');
      expect((await repository.load()).room(secondRoom), isNotNull);
      await repository.restoreData(backup);
      final restored = await repository.load();
      expect(restored.rooms, hasLength(1));
      expect(restored.balance(id), 541544);
      expect(restored.paid(id), 123456);
      expect(restored.depositBalance(tenancyId), 500000);
      expect(restored.payments, hasLength(2));
      expect(restored.settings['property_name'], 'Santos Apartments');
      expect(restored.audit.last['action'], 'restored');
    },
  );

  test(
    'backup rejects broken references and leaves existing data intact',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      final backup = clone(await repository.exportData());
      (backup['tables']['invoices'] as List).first['tenancy_id'] = 999;
      await expectLater(repository.restoreData(backup), throwsStateError);
      expect((await repository.load()).invoice(id), isNotNull);
    },
  );

  test(
    'backup rejects mismatched invoice total and leaves existing balance intact',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      final backup = clone(await repository.exportData());
      (backup['tables']['invoices'] as List).first['total_cents'] = 1;
      await expectLater(repository.restoreData(backup), throwsStateError);
      expect((await repository.load()).invoice(id)!['total_cents'], 665000);
    },
  );

  test(
    'backup rejects overallocated payment and broken reading chronology',
    () async {
      final tenancyId = await tenant(await room());
      final id = await bill(tenancyId);
      await repository.finalizeInvoice(id);
      await payment(id, 100000);
      final backup = clone(await repository.exportData());
      (backup['tables']['allocations'] as List).first['amount_cents'] = 1;
      await expectLater(repository.validateBackup(backup), throwsStateError);
      final feb = await bill(
        tenancyId,
        period: '2026-02',
        electricity: 200000,
        water: 20000,
      );
      await repository.finalizeInvoice(feb);
      final broken = clone(await repository.exportData());
      final reading = (broken['tables']['readings'] as List).last;
      reading['previous_value'] = 9000;
      reading['current_value'] =
          19000; // Same consumption; breaks cross-period chain.
      await expectLater(repository.validateBackup(broken), throwsStateError);
    },
  );

  test(
    'backup rejects missing tables, noninteger money, and unsupported files',
    () async {
      await room();
      await expectLater(
        repository.restoreData({'foo': 'bar'}),
        throwsStateError,
      );
      final missing = clone(await repository.exportData());
      (missing['tables'] as Map).remove('payments');
      await expectLater(repository.restoreData(missing), throwsStateError);
      final fractional = clone(await repository.exportData());
      (fractional['tables']['rooms'] as List).first['rent_cents'] = 1.5;
      await expectLater(repository.restoreData(fractional), throwsStateError);
      expect((await repository.load()).rooms, hasLength(1));
    },
  );

  test('persistent SQLite ledger survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('bahay-rent-test-');
    final path = '${directory.path}${Platform.pathSeparator}persistent.db';
    var persistent = await RentalRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    try {
      final roomId = await persistent.saveRoom({
        'name': 'Persistent room',
        'rent_cents': 400000,
        'electricity_mode': 'fixed',
        'electricity_rate': 10000,
        'water_mode': 'fixed',
        'water_rate': 5000,
      });
      final tenancyId = await persistent.assignTenant(
        roomId: roomId,
        name: 'Ana',
        phone: '',
        moveIn: '2026-01-01',
        rentCents: 400000,
        depositCents: 400000,
        dueDay: 5,
      );
      final invoiceId = await persistent.saveDraft(
        tenancyId: tenancyId,
        period: '2026-01',
        dueDate: '2026-01-05',
      );
      await persistent.finalizeInvoice(invoiceId);
      await persistent.recordPayment(
        invoiceId: invoiceId,
        amountCents: 12345,
        date: '2026-01-05',
        method: 'GCash',
        requestId: 'persist',
      );
      await persistent.close();
      persistent = await RentalRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final data = await persistent.load();
      expect(data.balance(invoiceId), 402655);
      expect(data.depositBalance(tenancyId), 400000);
      expect(data.payments.single['method'], 'GCash');
    } finally {
      await persistent.close();
      await directory.delete(recursive: true);
    }
  });
}
