import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/data/models.dart';

void main() {
  group('parseFixed', () {
    test('parses centavos and meter thousandths without float drift', () {
      expect(parseFixed('0'), 0);
      expect(parseFixed('0.00'), 0);
      expect(parseFixed('4500'), 450000);
      expect(parseFixed('4,500.75'), 450075);
      expect(parseFixed('  12.5 '), 1250);
      expect(parseFixed('123.456', decimals: 3), 123456);
      expect(parseFixed('-250.50', allowNegative: true), -25050);
    });

    test('rejects invalid formats, disallowed negatives, and int64 overflow', () {
      expect(() => parseFixed(''), throwsFormatException);
      expect(() => parseFixed('abc'), throwsFormatException);
      expect(() => parseFixed('12.345', decimals: 2), throwsFormatException);
      expect(() => parseFixed('-1.00'), throwsFormatException);
      expect(
        () => parseFixed('99999999999999999999.00'),
        throwsFormatException,
      );
    });
  });

  group('AppData O(1) index & derived balances', () {
    AppData sampleData() => AppData(
      rooms: [
        {'id': 1, 'name': 'Room A', 'archived': 0},
        {'id': 2, 'name': 'Room B', 'archived': 0},
      ],
      tenants: [
        {'id': 10, 'name': 'Maria Santos'},
        {'id': 11, 'name': 'Jose Cruz'},
      ],
      tenancies: [
        {
          'id': 100,
          'room_id': 1,
          'tenant_id': 10,
          'move_in': '2026-01-01',
          'move_out': '2026-06-01',
          'rent_cents': 500000,
          'due_day': 5,
        },
        {
          'id': 101,
          'room_id': 1,
          'tenant_id': 11,
          'move_in': '2026-06-01',
          'move_out': null,
          'rent_cents': 550000,
          'due_day': 31,
        },
      ],
      readings: [
        {'id': 1, 'invoice_id': 500, 'room_id': 1, 'kind': 'electricity'},
      ],
      invoices: [
        {
          'id': 500,
          'tenancy_id': 101,
          'room_id': 1,
          'period': '2026-06',
          'due_date': '2026-06-30',
          'status': 'final',
          'total_cents': 600000,
          'reference': 'BILL-000500',
        },
      ],
      lines: [
        {'id': 1, 'invoice_id': 500, 'kind': 'rent', 'amount_cents': 550000},
        {
          'id': 2,
          'invoice_id': 500,
          'kind': 'electricity',
          'amount_cents': 50000,
        },
      ],
      payments: [
        {
          'id': 900,
          'date': '2026-06-10',
          'amount_cents': 200000,
          'method': 'Cash',
          'reversed_at': null,
        },
        {
          'id': 901,
          'date': '2026-06-12',
          'amount_cents': 150000,
          'method': 'GCash',
          'reversed_at': '2026-06-13',
        },
      ],
      allocations: [
        {'id': 1, 'payment_id': 900, 'invoice_id': 500, 'amount_cents': 200000},
        {'id': 2, 'payment_id': 901, 'invoice_id': 500, 'amount_cents': 150000},
      ],
      deposits: [
        {'id': 1, 'tenancy_id': 100, 'kind': 'received', 'amount_cents': 500000},
        {'id': 2, 'tenancy_id': 100, 'kind': 'deduction', 'amount_cents': 120000},
        {'id': 3, 'tenancy_id': 100, 'kind': 'refund', 'amount_cents': 380000},
        {'id': 4, 'tenancy_id': 101, 'kind': 'received', 'amount_cents': 550000},
      ],
      audit: [],
      settings: const {'property_name': 'Upa Renta Test'},
    );

    test('resolves primary entities and grouped relations in O(1)', () {
      final data = sampleData();
      expect(data.room(1)!['name'], 'Room A');
      expect(data.room(999), isNull);
      expect(data.tenant(10)!['name'], 'Maria Santos');
      expect(data.tenancy(101)!['due_day'], 31);
      expect(data.invoice(500)!['reference'], 'BILL-000500');
      expect(data.payment(900)!['method'], 'Cash');
      expect(data.linesForInvoice(500), hasLength(2));
      expect(data.readingsForInvoice(500), hasLength(1));
      expect(data.allocationsForInvoice(500), hasLength(2));
      expect(data.allocationsForPayment(900), hasLength(1));
      expect(data.depositsForTenancy(100), hasLength(3));
      expect(data.tenanciesForRoom(1), hasLength(2));
      expect(data.invoicesForPeriod('2026-06'), hasLength(1));
      expect(data.invoicesForPeriod('2026-07'), isEmpty);
      expect(data.activeTenancy(1)!['id'], 101);
      expect(data.activeTenancy(2), isNull);
      expect(data.tenantName(101), 'Jose Cruz');
      expect(data.tenantName(999), 'Former tenant');
    });

    test('computes paid, balance, and depositBalance and reacts to mutations', () {
      final data = sampleData();
      expect(data.paid(500), 200000);
      expect(data.balance(500), 400000);
      expect(data.depositBalance(100), 0);
      expect(data.depositBalance(101), 550000);

      // Mutate list & row in place and verify index auto-rebuilds cleanly.
      data.payments.add({
        'id': 902,
        'date': '2026-06-20',
        'amount_cents': 400000,
        'method': 'Cash',
        'reversed_at': null,
      });
      data.allocations.add({
        'id': 3,
        'payment_id': 902,
        'invoice_id': 500,
        'amount_cents': 400000,
      });
      expect(data.paid(500), 600000);
      expect(data.balance(500), 0);

      data.tenancies[1]['move_out'] = '2026-07-01';
      expect(data.activeTenancy(1), isNull);
    });
  });
}

