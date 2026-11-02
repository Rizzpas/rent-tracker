import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/data/models.dart';
import 'package:upa_renta/services/documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('peso formats centavos with comma separators and negative signs', () {
    expect(peso(0), '₱0.00');
    expect(peso(5), '₱0.05');
    expect(peso(99), '₱0.99');
    expect(peso(100), '₱1.00');
    expect(peso(99999), '₱999.99');
    expect(peso(100000), '₱1,000.00');
    expect(peso(123456789), '₱1,234,567.89');
    expect(peso(-50025), '-₱500.25');
  });

  test('PDF statement and receipt embed Upa Renta offline footer', () async {
    final data = AppData(
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
      readings: [
        {
          'id': 1,
          'room_id': 1,
          'kind': 'electricity',
          'period': '2026-02',
          'previous_value': 10000,
          'current_value': 25000,
          'invoice_id': 1,
        },
      ],
      invoices: [
        {
          'id': 1,
          'tenancy_id': 1,
          'room_id': 1,
          'period': '2026-02',
          'due_date': '2026-02-28',
          'status': 'final',
          'total_cents': 500000,
          'reference': 'BILL-000001',
        },
      ],
      lines: [
        {
          'id': 1,
          'invoice_id': 1,
          'kind': 'rent',
          'description': 'Monthly rent',
          'quantity': 1000,
          'rate_cents': 500000,
          'amount_cents': 500000,
        },
      ],
      payments: [
        {
          'id': 1,
          'date': '2026-02-28',
          'amount_cents': 500000,
          'method': 'Cash',
          'reference': '',
          'notes': 'Paid via Collections Day',
          'reversed_at': null,
        },
      ],
      allocations: [
        {'id': 1, 'payment_id': 1, 'invoice_id': 1, 'amount_cents': 500000},
      ],
      deposits: [],
      audit: [],
      settings: const {
        'property_name': 'Sampaguita Residences',
        'property_address': 'Quezon City',
        'owner_name': 'Aling Rosa',
      },
    );

    final statement = await DocumentService.statementBytes(data, 1);
    final receipt = await DocumentService.receiptBytes(data, 1);
    expect(ascii.decode(statement.take(5).toList()), '%PDF-');
    expect(ascii.decode(receipt.take(5).toList()), '%PDF-');
    expect(statement.length, greaterThan(4000));
    expect(receipt.length, greaterThan(4000));
  });
}
