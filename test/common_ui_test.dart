import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/data/models.dart' hide Row;
import 'package:upa_renta/ui/common.dart';

void main() {
  test('formatting and validation helpers produce exact strings', () {
    expect(money(450050), '₱4,500.50');
    expect(decimalOf(12345, 2), '123.45');
    expect(decimalOf(12345, 3), '12.345');
    expect(decimalOf(-50, 2), '-0.50');
    expect(monthLabel('2026-02'), 'February 2026');
    expect(dateLabel('2026-02-28'), '28 Feb 2026');
    expect(
      friendlyError(const FormatException('Choose a 6-digit PIN.')),
      'Choose a 6-digit PIN.',
    );

    final controller = TextEditingController(text: '  Room 101  ');
    expect(requiredText(controller, 'a room'), 'Room 101');
    controller.text = '   ';
    expect(() => requiredText(controller, 'a room'), throwsFormatException);
    controller.dispose();
  });

  test('invoiceStatus classifies draft, paid, partial, unpaid, and overdue', () {
    final futureDue = '2099-12-31';
    final pastDue = '2020-01-05';
    final data = AppData(
      rooms: [],
      tenants: [],
      tenancies: [],
      readings: [],
      invoices: [
        {
          'id': 1,
          'status': 'draft',
          'due_date': futureDue,
          'total_cents': 10000,
        },
        {
          'id': 2,
          'status': 'final',
          'due_date': futureDue,
          'total_cents': 10000,
        },
        {
          'id': 3,
          'status': 'final',
          'due_date': futureDue,
          'total_cents': 10000,
        },
        {
          'id': 4,
          'status': 'final',
          'due_date': futureDue,
          'total_cents': 10000,
        },
        {
          'id': 5,
          'status': 'final',
          'due_date': pastDue,
          'total_cents': 10000,
        },
        {
          'id': 6,
          'status': 'final',
          'due_date': pastDue,
          'total_cents': 10000,
        },
      ],
      lines: [],
      payments: [
        {'id': 1, 'date': '2026-01-01', 'amount_cents': 10000, 'reversed_at': null},
        {'id': 2, 'date': '2026-01-01', 'amount_cents': 4000, 'reversed_at': null},
        {'id': 3, 'date': '2026-01-01', 'amount_cents': 3000, 'reversed_at': null},
      ],
      allocations: [
        {'id': 1, 'payment_id': 1, 'invoice_id': 2, 'amount_cents': 10000},
        {'id': 2, 'payment_id': 2, 'invoice_id': 3, 'amount_cents': 4000},
        {'id': 3, 'payment_id': 3, 'invoice_id': 6, 'amount_cents': 3000},
      ],
      deposits: [],
      audit: [],
      settings: const {},
    );

    expect(invoiceStatus(data, data.invoice(1)!), 'Draft');
    expect(invoiceStatus(data, data.invoice(2)!), 'Paid');
    expect(invoiceStatus(data, data.invoice(3)!), 'Partial');
    expect(invoiceStatus(data, data.invoice(4)!), 'Unpaid');
    expect(invoiceStatus(data, data.invoice(5)!), 'Overdue');
    expect(invoiceStatus(data, data.invoice(6)!), 'Partial · overdue');
  });

  testWidgets(
    'UpaRentaLogo, SectionCard, StatusPill, EmptyState render with zero BackdropFilter',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                UpaRentaLogo(size: 48),
                SectionCard(
                  child: Column(
                    children: [
                      StatusPill('Paid'),
                      StatusPill('Overdue'),
                      DetailRow('Rent', '₱5,000.00', strong: true),
                    ],
                  ),
                ),
                EmptyState(
                  icon: Icons.home_outlined,
                  title: 'Empty',
                  description: 'Nothing yet',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(UpaRentaLogo), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('₱5,000.00'), findsOneWidget);
    },
  );
}

