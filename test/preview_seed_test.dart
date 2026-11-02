import 'package:upa_renta/data/models.dart';
import 'package:upa_renta/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../tool/preview_seed.dart';

void main() {
  test(
    'live preview seeds a consistent ledger with distinct monthly billing states',
    () async {
      sqfliteFfiInit();
      final repository = await RentalRepository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(repository.close);
      await seedPreviewData(repository);
      final data = await repository.load();
      final period = billingPeriod(manilaNow());
      final current = data.invoices
          .where((bill) => bill['period'] == period)
          .toList();
      expect(data.rooms.length, 6);
      expect(data.tenancies.length, 4);
      expect(current.where((bill) => bill['status'] == 'draft').length, 1);
      final finalized = current
          .where((bill) => bill['status'] == 'final')
          .toList();
      expect(
        finalized.where((bill) => data.balance(bill['id']) == 0).length,
        1,
      );
      expect(
        finalized
            .where(
              (bill) =>
                  data.paid(bill['id']) > 0 && data.balance(bill['id']) > 0,
            )
            .length,
        1,
      );
      expect(
        finalized
            .where(
              (bill) =>
                  data.paid(bill['id']) == 0 && data.balance(bill['id']) > 0,
            )
            .length,
        1,
      );
      final earlierBalance = data.invoices
          .where((bill) => (bill['period'] as String).compareTo(period) < 0)
          .fold<int>(0, (total, bill) => total + data.balance(bill['id']));
      expect(earlierBalance, 150000);
      expect(
        data.payments.every(
          (payment) =>
              (payment['date'] as String).compareTo(isoDate(manilaNow())) <= 0,
        ),
        isTrue,
      );
      // The demonstration backup must pass the same financial integrity checks
      // used for a real user's restore, including finalized meter continuity.
      await repository.validateBackup(await repository.exportData());
    },
  );
}
