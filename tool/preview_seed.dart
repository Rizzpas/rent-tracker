import 'package:upa_renta/data/models.dart';
import 'package:upa_renta/data/repository.dart';

/// Demonstration records for the isolated browser preview only.
/// This is never imported by the Android application entry point.
Future<void> seedPreviewData(RentalRepository repository) async {
  final now = manilaNow();
  final period = billingPeriod(now);
  final priorStart = DateTime.utc(now.year, now.month - 1, 1);
  final previousPeriod = billingPeriod(priorStart);
  final previousPaymentDate = isoDate(DateTime.utc(now.year, now.month, 0));
  final today = isoDate(now);

  await repository.saveSettings({
    'property_name': 'Sampaguita Residences',
    'property_address': 'Quezon City, Metro Manila',
    'owner_name': 'Aling Rosa Santos',
    'dark_mode': 'false',
    'reminders': 'false',
  });

  const rents = [650000, 700000, 650000, 550000, 550000, 500000];
  const names = [
    'Maria Santos',
    'Jose Dela Cruz',
    'Ana Reyes',
    'Carlo Mendoza',
  ];
  // Showcase common Philippine due schedules: 5th, 15th, 30th, and End of month.
  const dueDays = [5, 15, 30, 31];

  for (var index = 0; index < rents.length; index++) {
    final sharedWater = index == 3;
    final roomId = await repository.saveRoom({
      'name': 'Room ${101 + index}',
      'rent_cents': rents[index],
      'electricity_mode': index == 5 ? 'fixed' : 'metered',
      'electricity_rate': index == 5 ? 75000 : 1250,
      'water_mode': sharedWater ? 'shared' : 'fixed',
      'water_rate': sharedWater ? 0 : 25000,
      'notes': index == 4 ? 'Ground floor. Ready for a new tenant.' : '',
      'archived': 0,
    });
    if (index >= names.length) continue;

    final dueDay = dueDays[index];
    final tenancyId = await repository.assignTenant(
      roomId: roomId,
      name: names[index],
      phone: '0917123456$index',
      moveIn: '$previousPeriod-01',
      rentCents: rents[index],
      depositCents: rents[index],
      dueDay: dueDay,
      notes: index == 0
          ? 'Prefers GCash. Receipt provided after each payment.'
          : '',
    );

    final baseline = 1200000 + index * 650000;
    final previousCurrent = baseline + 83000 + index * 11000;
    final priorInvoice = await repository.saveDraft(
      tenancyId: tenancyId,
      period: previousPeriod,
      dueDate: dueDateForPeriod(previousPeriod, dueDay),
      electricityPrevious: baseline,
      electricityCurrent: previousCurrent,
      waterSharedCents: sharedWater ? 20000 : null,
    );
    await repository.finalizeInvoice(priorInvoice);
    var data = await repository.load();
    await repository.recordPayment(
      invoiceId: priorInvoice,
      // Ana's earlier unpaid balance stays on its original bill.
      amountCents: data.balance(priorInvoice) - (index == 2 ? 150000 : 0),
      // Jose pays last month's bill this month: the dashboard distinguishes
      // cash received this month from charges billed for this month.
      date: index == 1 ? today : previousPaymentDate,
      method: index == 1 ? 'Bank transfer' : 'Cash',
      reference: index == 1 ? 'BPI-86420' : '',
      notes: index == 2
          ? 'Partial payment; remaining balance carried on this bill.'
          : 'Monthly rental payment',
      requestId: 'live-preview-prior-$index',
    );

    final invoice = await repository.saveDraft(
      tenancyId: tenancyId,
      period: period,
      dueDate: dueDateForPeriod(period, dueDay),
      electricityCurrent: previousCurrent + 97400 + index * 13000,
      waterSharedCents: sharedWater ? 18000 : null,
      adjustmentCents: index == 3 ? -25000 : 0,
      adjustmentNote: index == 3 ? 'Agreed monthly discount' : '',
    );

    // Carlo's current bill remains a draft for reviewing the billing workflow.
    if (index == 3) continue;
    await repository.finalizeInvoice(invoice);
    if (index > 1) continue;

    data = await repository.load();
    await repository.recordPayment(
      invoiceId: invoice,
      amountCents: index == 0 ? data.balance(invoice) : 350000,
      date: today,
      method: index == 0 ? 'GCash' : 'Cash',
      reference: index == 0 ? 'GCASH-1072356' : '',
      notes: index == 0
          ? 'Paid in full. Thank you!'
          : 'First installment for this month.',
      requestId: 'live-preview-current-$index',
    );
  }
}
