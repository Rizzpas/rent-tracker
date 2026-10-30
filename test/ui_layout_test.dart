import 'package:bahay_rent/data/models.dart' hide Row;
import 'package:bahay_rent/data/repository.dart';
import 'package:bahay_rent/ui/home_page.dart';
import 'package:bahay_rent/ui/rooms_page.dart';
import 'package:bahay_rent/ui/billing_page.dart';
import 'package:bahay_rent/ui/payments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late RentalRepository repository;
  final now = manilaNow();
  final period = billingPeriod(now);
  final date = isoDate(now);
  final populated = AppData(
    rooms: [
      {
        'id': 1,
        'name': 'Room 101',
        'rent_cents': 650000,
        'electricity_mode': 'metered',
        'electricity_rate': 1200,
        'water_mode': 'fixed',
        'water_rate': 25000,
        'notes': '',
        'archived': 0,
      },
    ],
    tenants: [
      {'id': 1, 'name': 'Maria Dela Cruz', 'phone': '09171234567', 'notes': ''},
    ],
    tenancies: [
      {
        'id': 1,
        'room_id': 1,
        'tenant_id': 1,
        'move_in': '$period-01',
        'move_out': null,
        'rent_cents': 650000,
        'due_day': 5,
      },
    ],
    readings: [
      {
        'id': 1,
        'room_id': 1,
        'kind': 'electricity',
        'period': period,
        'previous_value': 100000,
        'current_value': 125000,
        'invoice_id': 1,
      },
    ],
    invoices: [
      {
        'id': 1,
        'tenancy_id': 1,
        'room_id': 1,
        'period': period,
        'due_date': '$period-05',
        'status': 'final',
        'total_cents': 705000,
        'reference': 'BILL-000001',
        'created_at': date,
        'finalized_at': date,
      },
    ],
    lines: [
      {
        'id': 1,
        'invoice_id': 1,
        'kind': 'rent',
        'description': 'Agreed monthly rent',
        'quantity': 1000,
        'rate_cents': 650000,
        'amount_cents': 650000,
      },
      {
        'id': 2,
        'invoice_id': 1,
        'kind': 'electricity',
        'description': '25 kWh at the agreed rate',
        'quantity': 25000,
        'rate_cents': 1200,
        'amount_cents': 30000,
      },
      {
        'id': 3,
        'invoice_id': 1,
        'kind': 'water',
        'description': 'Fixed water charge',
        'quantity': 1000,
        'rate_cents': 25000,
        'amount_cents': 25000,
      },
    ],
    payments: [
      {
        'id': 1,
        'date': date,
        'amount_cents': 150000,
        'method': 'GCash',
        'reference': 'GC12345',
        'notes': '',
        'request_id': 'layout-test',
        'reversed_at': null,
        'reversal_reason': null,
      },
    ],
    allocations: [
      {'id': 1, 'payment_id': 1, 'invoice_id': 1, 'amount_cents': 150000},
    ],
    deposits: [
      {
        'id': 1,
        'tenancy_id': 1,
        'kind': 'received',
        'amount_cents': 650000,
        'date': date,
        'notes': '',
      },
    ],
    audit: [],
    settings: RentalRepository.defaults,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    repository = await RentalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDownAll(() => repository.close());

  for (final pageName in ['Home', 'Rooms', 'Billing', 'Payments']) {
    testWidgets('$pageName fits a 360px phone with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      void changed() {}
      final page = switch (pageName) {
        'Home' => HomePage(
          data: populated,
          repository: repository,
          onChanged: changed,
          period: period,
          onNavigate: (_) {},
        ),
        'Rooms' => RoomsPage(
          data: populated,
          repository: repository,
          onChanged: changed,
          period: period,
        ),
        'Billing' => BillingPage(
          data: populated,
          repository: repository,
          onChanged: changed,
          period: period,
        ),
        _ => PaymentsPage(
          data: populated,
          repository: repository,
          onChanged: changed,
          period: period,
        ),
      };
      final previousHandler = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        previousHandler(details);
      };
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = previousHandler;
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Maria Dela Cruz'), findsWidgets);
    });
  }
}
