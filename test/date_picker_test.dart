import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/services/local_time.dart';
import 'package:upa_renta/ui/date_picker.dart';

void main() {
  testWidgets(
    'UpaDatePickerSheet supports 5th, 15th, 30th, and End of month in common & leap February',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? picked;
      final controller = TextEditingController(text: '2026-02-10');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  DateInput(controller: controller, label: 'Payment due date'),
                  ElevatedButton(
                    onPressed: () async {
                      picked = await showUpaDatePicker(
                        context,
                        initialDate: DateTime.utc(2028, 2, 10),
                        title: 'Leap February check',
                        manilaClock: DateTime.utc(2028, 2, 1, 1, 0),
                      );
                    },
                    child: const Text('Open leap picker'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Tap DateInput card to open custom sheet for Feb 2026 (common year -> 28 days).
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(find.text('Asia/Manila'), findsOneWidget);
      expect(find.text('End of month (28)'), findsOneWidget);

      await tester.tap(find.text('15th'));
      await tester.pumpAndSettle();
      expect(find.text('Use 15 Feb 2026'), findsOneWidget);

      await tester.tap(find.text('End of month (28)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 28 Feb 2026'));
      await tester.pumpAndSettle();
      expect(controller.text, '2026-02-28');

      // Open Leap February 2028 picker -> End of month must be 29!
      await tester.tap(find.text('Open leap picker'));
      await tester.pumpAndSettle();
      expect(find.text('End of month (29)'), findsOneWidget);
      await tester.tap(find.text('End of month (29)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use 29 Feb 2028'));
      await tester.pumpAndSettle();
      expect(isoDate(picked!), '2028-02-29');
    },
  );

  testWidgets('showUpaMonthPicker selects billing period in 1 tap', (
    tester,
  ) async {
    String? period;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                period = await showUpaMonthPicker(
                  context,
                  initialPeriod: '2026-11',
                  manilaClock: DateTime.utc(2026, 11, 3, 1, 0),
                );
              },
              child: const Text('Pick month'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pick month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apr'));
    await tester.pumpAndSettle();
    expect(period, '2026-04');
  });

  testWidgets(
    'DueDaySelector chips set 5th, 15th, 30th, and End of month (31)',
    (tester) async {
      final controller = TextEditingController(text: '5');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DueDaySelector(controller: controller)),
        ),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '15th'));
      await tester.pump();
      expect(controller.text, '15');

      await tester.tap(find.widgetWithText(ChoiceChip, '30th'));
      await tester.pump();
      expect(controller.text, '30');
      expect(find.textContaining('Feb 28'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'End of month'));
      await tester.pump();
      expect(controller.text, '31');
      expect(find.textContaining('28th/29th in February'), findsOneWidget);
    },
  );
}

