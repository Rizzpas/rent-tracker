import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/services/app_lock.dart';
import 'package:upa_renta/ui/common.dart' show UpaRentaLogo;

void main() {
  late DateTime fakeNow;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    fakeNow = DateTime.utc(2026, 11, 3, 8, 0);
    LockService.debugClock = () => fakeNow;
    LockService.debugIterations = 1000;
  });

  tearDown(() {
    LockService.debugClock = null;
    LockService.debugAuthFactory = null;
    LockService.debugIterations = 120000;
  });

  test('setPin validates 6 digits and throttles after 5 failed attempts', () async {
    await expectLater(LockService.setPin('12345'), throwsFormatException);
    await expectLater(LockService.setPin('abcdef'), throwsFormatException);

    await LockService.setPin('654321');
    expect(await LockService.isEnabled(), isTrue);
    expect(await LockService.verifyPin('654321'), isTrue);

    for (var i = 0; i < 5; i++) {
      expect(await LockService.verifyPin('000000'), isFalse);
    }
    await expectLater(LockService.verifyPin('654321'), throwsFormatException);

    // Advance past 30-second cooldown and verify valid PIN succeeds again.
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(await LockService.verifyPin('654321'), isTrue);
  });

  testWidgets(
    'AppLock gates child with UpaRentaLogo and relocks after 30s in background',
    (tester) async {
      await tester.runAsync(() => LockService.setPin('246810'));

      await tester.pumpWidget(
        const MaterialApp(
          home: AppLock(child: Scaffold(body: Text('Protected ledger'))),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UpaRentaLogo), findsOneWidget);
      expect(find.text('Upa Renta'), findsOneWidget);
      expect(find.text('Protected ledger'), findsNothing);

      await tester.enterText(find.byType(TextField), '246810');
      await tester.tap(find.text('Unlock'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Protected ledger'), findsOneWidget);

      // Brief background (<30s) keeps session unlocked.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fakeNow = fakeNow.add(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Protected ledger'), findsOneWidget);

      // Background >= 30s relocks automatically.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      fakeNow = fakeNow.add(const Duration(seconds: 35));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Protected ledger'), findsNothing);
      expect(find.text('Unlock'), findsOneWidget);
    },
  );
}

