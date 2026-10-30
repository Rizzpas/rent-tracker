import 'dart:convert';
import 'dart:typed_data';

import 'package:bahay_rent/data/models.dart';
import 'package:bahay_rent/services/app_lock.dart';
import 'package:bahay_rent/services/backup.dart';
import 'package:bahay_rent/services/documents.dart';
import 'package:bahay_rent/services/local_time.dart';
import 'package:bahay_rent/services/reminders.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'timestamps render in Manila even when UTC date is the previous day',
    () {
      expect(
        formatManilaTimestamp('2026-10-30T18:05:00Z'),
        '31 Oct 2026, 2:05 AM (Manila)',
      );
      expect(
        formatManilaTimestamp('2026-10-31T02:05:00+08:00'),
        '31 Oct 2026, 2:05 AM (Manila)',
      );
    },
  );

  test('plain backup detects changed records before restore', () async {
    final payload = <String, dynamic>{
      'format': 'bahay-rent-backup',
      'version': 1,
      'tables': {
        'rooms': [
          {'id': 1, 'name': 'Room 1'},
        ],
      },
    };
    final bytes = await BackupService.encode(payload);
    expect(await BackupService.decode(bytes), payload);
    final damaged = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    damaged['payload']['tables']['rooms'][0]['name'] = 'Altered room';
    await expectLater(
      BackupService.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(damaged))),
      ),
      throwsFormatException,
    );
    await expectLater(
      BackupService.decode(Uint8List.fromList(utf8.encode('{invalid'))),
      throwsFormatException,
    );
  });

  test(
    'encrypted backup round-trip rejects wrong passwords and modified ciphertext',
    () async {
      final payload = <String, dynamic>{
        'format': 'bahay-rent-backup',
        'version': 1,
        'tables': {
          'payments': [
            {'amount_cents': 10001},
          ],
        },
      };
      final bytes = await BackupService.encode(
        payload,
        password: 'Private backup 42!',
      );
      expect(utf8.decode(bytes), isNot(contains('amount_cents')));
      expect(
        await BackupService.decode(bytes, password: 'Private backup 42!'),
        payload,
      );
      await expectLater(
        BackupService.decode(bytes, password: 'Wrong password'),
        throwsFormatException,
      );
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final cipher = base64Decode(envelope['ciphertext'] as String);
      cipher[0] ^= 1;
      envelope['ciphertext'] = base64Encode(cipher);
      await expectLater(
        BackupService.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          password: 'Private backup 42!',
        ),
        throwsFormatException,
      );
      await expectLater(
        BackupService.encode(payload, password: 'short'),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'report separates billing month and cash received and excludes drafts/reversals',
    () {
      final data = fixture();
      final august = DocumentService.select(data, period: '2026-08');
      expect(august.billed, 120000);
      expect(august.collected, 30000); // Received in August for July's bill.
      expect(august.outstanding, 120000);
      expect(august.billedByKind['rent'], 100000);
      expect(august.billedByKind['electricity'], 15000);
      expect(august.billedByKind['water'], 5000);
      expect(DocumentService.select(data, year: 2026).billed, 220000);
      expect(
        DocumentService.select(data, period: '2026-08', roomId: 99).collected,
        0,
      );
      expect(
        DocumentService.select(data, period: '2026-08', tenantId: 1).collected,
        30000,
      );
    },
  );

  test('CSV quotes notes and neutralizes spreadsheet formulas', () {
    final text = DocumentService.csv(fixture(), year: 2026);
    expect(text, contains('"\'=2+2"'));
    expect(text, contains('"ref line 1, ""quoted""\nline 2"'));
    expect(text, contains('"300.00"'));
    expect(text, contains('"Occupancy"'));
  });

  test('filtered exports show allocated amounts for multi-bill payments', () {
    final data = fixture();
    data.rooms.add({'id': 2, 'name': 'Room 2', 'archived': 0});
    data.tenants.add({'id': 2, 'name': 'Juan Reyes'});
    data.tenancies.add({
      'id': 2,
      'room_id': 2,
      'tenant_id': 2,
      'move_in': '2026-07-01',
      'move_out': null,
    });
    data.invoices.add({
      'id': 4,
      'tenancy_id': 2,
      'room_id': 2,
      'period': '2026-07',
      'due_date': '2026-07-05',
      'status': 'final',
      'total_cents': 100000,
      'reference': 'BILL-4',
    });
    data.payments.add({
      'id': 3,
      'date': '2026-08-03',
      'amount_cents': 50000,
      'method': 'Cash',
      'reference': '',
      'notes': '',
      'reversed_at': null,
    });
    data.allocations.addAll([
      {'id': 3, 'payment_id': 3, 'invoice_id': 1, 'amount_cents': 10000},
      {'id': 4, 'payment_id': 3, 'invoice_id': 4, 'amount_cents': 40000},
    ]);
    final report = DocumentService.select(data, period: '2026-08', roomId: 1);
    expect(report.collected, 40000);
    expect(
      report.payments.singleWhere((p) => p['id'] == 3)['amount_cents'],
      10000,
    );
    final csv = DocumentService.csv(data, period: '2026-08', roomId: 1);
    expect(csv, contains('"100.00"'));
    expect(csv, isNot(contains('"500.00"')));
    expect(csv, isNot(contains('Juan Reyes')));
  });

  test('move-out date is exclusive in occupancy reports', () {
    final data = fixture();
    data.tenancies[0]['move_out'] = '2026-08-01';
    expect(DocumentService.select(data, period: '2026-08').tenancies, isEmpty);
    expect(
      DocumentService.select(data, period: '2026-07').tenancies,
      hasLength(1),
    );
  });

  test(
    'local reminders include overdue partial bills and drafts in Manila calendar',
    () {
      final plan = ReminderService.plan(fixture(), DateTime(2026, 8, 10));
      final today = plan.where((n) => n.date == DateTime(2026, 8, 10)).toList();
      expect(today.any((n) => n.body.contains('2 bills overdue')), isTrue);
      expect(
        today.any((n) => n.body.contains('1 draft awaiting finalization')),
        isTrue,
      );
      expect(
        plan.any(
          (n) => n.date == DateTime(2026, 8, 25) && n.title.contains('meters'),
        ),
        isTrue,
      );
      expect(plan.where((n) => n.title == 'Your rental check-in').length, 90);
    },
  );

  test(
    'PDF statement and payment receipt build from bundled fonts without a network',
    () async {
      final statement = await DocumentService.statementBytes(fixture(), 1);
      final receipt = await DocumentService.receiptBytes(fixture(), 1);
      final reversed = await DocumentService.receiptBytes(fixture(), 2);
      for (final bytes in [statement, receipt, reversed]) {
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(4000));
      }
    },
  );

  test(
    'PIN remains hashed in secure storage and failed attempts are throttled',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(await LockService.isEnabled(), isFalse);
      await LockService.setPin('123456');
      expect(await LockService.isEnabled(), isTrue);
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values, isNot(contains('123456')));
      expect(await LockService.verifyPin('123456'), isTrue);
      for (var attempt = 0; attempt < 5; attempt++) {
        expect(await LockService.verifyPin('000000'), isFalse);
      }
      await expectLater(LockService.verifyPin('123456'), throwsFormatException);
      await LockService.disable();
      expect(await LockService.isEnabled(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

AppData fixture() => AppData(
  rooms: [
    {'id': 1, 'name': '=2+2', 'archived': 0},
  ],
  tenants: [
    {'id': 1, 'name': 'Maria Santos'},
  ],
  tenancies: [
    {
      'id': 1,
      'room_id': 1,
      'tenant_id': 1,
      'move_in': '2026-07-01',
      'move_out': null,
    },
  ],
  readings: [
    {
      'id': 1,
      'room_id': 1,
      'kind': 'electricity',
      'period': '2026-07',
      'previous_value': 0,
      'current_value': 10000,
      'invoice_id': 1,
    },
  ],
  invoices: [
    {
      'id': 1,
      'tenancy_id': 1,
      'room_id': 1,
      'period': '2026-07',
      'due_date': '2026-07-05',
      'status': 'final',
      'total_cents': 100000,
      'reference': 'BILL-1',
    },
    {
      'id': 2,
      'tenancy_id': 1,
      'room_id': 1,
      'period': '2026-08',
      'due_date': '2026-08-05',
      'status': 'final',
      'total_cents': 120000,
      'reference': 'BILL-2',
    },
    {
      'id': 3,
      'tenancy_id': 1,
      'room_id': 1,
      'period': '2026-09',
      'due_date': '2026-09-05',
      'status': 'draft',
      'total_cents': 200000,
      'reference': 'BILL-3',
    },
  ],
  lines: [
    {
      'id': 1,
      'invoice_id': 1,
      'kind': 'rent',
      'description': 'Monthly rent',
      'quantity': 1000,
      'rate_cents': 100000,
      'amount_cents': 100000,
    },
    {
      'id': 2,
      'invoice_id': 2,
      'kind': 'rent',
      'description': 'Monthly rent',
      'quantity': 1000,
      'rate_cents': 100000,
      'amount_cents': 100000,
    },
    {
      'id': 3,
      'invoice_id': 2,
      'kind': 'electricity',
      'description': 'Electricity',
      'quantity': 10000,
      'rate_cents': 1500,
      'amount_cents': 15000,
    },
    {
      'id': 4,
      'invoice_id': 2,
      'kind': 'water',
      'description': 'Water',
      'quantity': 1000,
      'rate_cents': 5000,
      'amount_cents': 5000,
    },
  ],
  payments: [
    {
      'id': 1,
      'date': '2026-08-01',
      'amount_cents': 30000,
      'method': 'Cash',
      'reference': 'ref',
      'notes': 'line 1, "quoted"\nline 2',
      'reversed_at': null,
    },
    {
      'id': 2,
      'date': '2026-08-02',
      'amount_cents': 20000,
      'method': 'Cash',
      'reference': '',
      'notes': '',
      'reversed_at': '2026-08-03',
      'reversal_reason': 'Wrong amount',
    },
  ],
  allocations: [
    {'id': 1, 'payment_id': 1, 'invoice_id': 1, 'amount_cents': 30000},
    {'id': 2, 'payment_id': 2, 'invoice_id': 1, 'amount_cents': 20000},
  ],
  deposits: [
    {
      'id': 1,
      'tenancy_id': 1,
      'kind': 'received',
      'amount_cents': 100000,
      'date': '2026-07-01',
      'notes': 'Security deposit',
    },
  ],
  audit: [],
  settings: {
    'property_name': 'Bahay Test',
    'property_address': 'Manila',
    'owner_name': 'Aling Maria',
    'meter_day': '25',
  },
);
