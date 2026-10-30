// Optional visual review harness. Seed data exists only in this test.
// flutter test test/preview_test.dart --dart-define=EXPORT_PREVIEWS=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bahay_rent/app.dart';
import 'package:bahay_rent/data/models.dart' hide Row;
import 'package:bahay_rent/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('export actual app screens for visual review', (tester) async {
    sqfliteFfiInit();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await fonts.load();
    // Button styles without an explicit family use Flutter test's default Ahem;
    // substitute the same bundled face for that test-only fallback as well.
    final fallback = FontLoader('Ahem')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    await fallback.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final repository = await tester.runAsync(() async {
      final repository = await RentalRepository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await _seed(repository);
      return repository;
    });
    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: repaintKey,
        child: BahayApp(repository: repository!, enablePlatformServices: false),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();

    Future<void> capture(String name) async {
      expect(
        tester.takeException(),
        isNull,
        reason: '$name must have no layout errors',
      );
      await tester.pumpAndSettle();
      // Material button styles can intentionally omit their font family. The
      // tester engine resolves that null family to its built-in block font,
      // even after registering the app's fonts. Substitute only that test font
      // at existing Text elements; content, app widgets and behavior stay intact.
      tester.binding.buildOwner!.buildScope(
        repaintKey.currentContext! as Element,
        () {
          for (final element in find.byType(Text).evaluate().toList()) {
            final text = element.widget as Text;
            final family =
                text.style?.fontFamily ??
                DefaultTextStyle.of(element).style.fontFamily;
            if (family != null || text.data == null) continue;
            element.update(
              Text(
                text.data!,
                key: text.key,
                style: (text.style ?? const TextStyle()).copyWith(
                  fontFamily: 'Roboto',
                ),
                strutStyle: text.strutStyle,
                textAlign: text.textAlign,
                textDirection: text.textDirection,
                locale: text.locale,
                softWrap: text.softWrap,
                overflow: text.overflow,
                textScaler: text.textScaler,
                maxLines: text.maxLines,
                semanticsLabel: text.semanticsLabel,
                textWidthBasis: text.textWidthBasis,
                textHeightBehavior: text.textHeightBehavior,
                selectionColor: text.selectionColor,
              ),
            );
          }
        },
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            repaintKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('deliverables/screenshots');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        image.dispose();
      });
    }

    await capture('home');
    await tester.drag(find.byType(ListView).first, const Offset(0, -570));
    await tester.pumpAndSettle();
    await capture('home-details');
    for (final tab in ['Rooms', 'Billing', 'Payments']) {
      await tester.tap(find.widgetWithText(NavigationDestination, tab));
      await tester.pumpAndSettle();
      await capture(tab.toLowerCase());
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(repository.close);
  }, skip: !const bool.fromEnvironment('EXPORT_PREVIEWS'));
}

Future<void> _seed(RentalRepository repository) async {
  final now = manilaNow();
  final period = billingPeriod(now);
  final previousPeriod = billingPeriod(DateTime(now.year, now.month - 1));
  await repository.saveSettings({
    'property_name': 'Sampaguita Residences',
    'property_address': 'Quezon City, Metro Manila',
    'owner_name': 'Aling Rosa Santos',
  });
  final rents = [650000, 700000, 650000, 550000, 550000, 500000];
  final names = [
    'Maria Santos',
    'Jose Dela Cruz',
    'Ana Reyes',
    'Carlo Mendoza',
  ];
  for (var index = 0; index < 6; index++) {
    final roomId = await repository.saveRoom({
      'name': 'Room ${101 + index}',
      'rent_cents': rents[index],
      'electricity_mode': 'metered',
      'electricity_rate': 1250,
      'water_mode': 'fixed',
      'water_rate': 25000,
      'notes': '',
      'archived': 0,
    });
    if (index >= 4) continue;
    final tenancyId = await repository.assignTenant(
      roomId: roomId,
      name: names[index],
      phone: '0917123456$index',
      moveIn: '$previousPeriod-01',
      rentCents: rents[index],
      depositCents: rents[index],
      dueDay: 5,
    );
    final invoiceId = await repository.saveDraft(
      tenancyId: tenancyId,
      period: period,
      dueDate: '$period-05',
      electricityCurrent: 100000 + index * 17000,
    );
    if (index < 3) {
      await repository.finalizeInvoice(invoiceId);
      final data = await repository.load();
      if (index < 2) {
        await repository.recordPayment(
          invoiceId: invoiceId,
          amountCents: index == 0 ? data.balance(invoiceId) : 400000,
          date: '$period-03',
          method: index == 0 ? 'GCash' : 'Cash',
          requestId: 'preview-payment-$index',
          reference: index == 0 ? 'GCASH-1072356' : '',
          notes: 'Monthly rental payment',
        );
      }
    }
  }
}
