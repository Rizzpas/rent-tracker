import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/services/local_time.dart';

void main() {
  group('Asia/Manila clock & calendar rollovers', () {
    test('converts UTC instants accurately across Manila midnight (UTC+08:00)', () {
      // 15:59:59 UTC is 23:59:59 Manila on the same UTC date.
      final beforeMidnight = DateTime.utc(2026, 2, 28, 15, 59, 59);
      expect(manilaToday(beforeMidnight), '2026-02-28');

      // 16:00:00 UTC is 00:00:00 Manila on the NEXT calendar day!
      final atMidnight = DateTime.utc(2026, 2, 28, 16, 0, 0);
      expect(manilaToday(atMidnight), '2026-03-01');
      expect(billingPeriod(manilaNow(atMidnight)), '2026-03');
    });
  });

  group('Due dates: 5th, 15th, 30th, and end-of-month (including February)', () {
    test('daysInMonth handles leap years, century years, and 30/31-day months', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 2), 28); // Common year
      expect(daysInMonth(2028, 2), 29); // Leap year
      expect(daysInMonth(2000, 2), 29); // 400-year leap
      expect(daysInMonth(2100, 2), 28); // 100-year non-leap
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 11), 30);
      expect(daysInMonth(2026, 12), 31);
    });

    test('dueDateForPeriod supports 5th, 15th, 30th, and 31st end-of-month', () {
      // 5th schedule
      expect(dueDateForPeriod('2026-01', 5), '2026-01-05');
      expect(dueDateForPeriod('2026-02', 5), '2026-02-05');
      expect(dueDateForPeriod('2028-02', 5), '2028-02-05');

      // 15th schedule
      expect(dueDateForPeriod('2026-01', 15), '2026-01-15');
      expect(dueDateForPeriod('2026-02', 15), '2026-02-15');
      expect(dueDateForPeriod('2028-02', 15), '2028-02-15');

      // 30th schedule (clamps in February, stays 30th on 31-day months!)
      expect(dueDateForPeriod('2026-01', 30), '2026-01-30');
      expect(dueDateForPeriod('2026-04', 30), '2026-04-30');
      expect(dueDateForPeriod('2026-02', 30), '2026-02-28');
      expect(dueDateForPeriod('2028-02', 30), '2028-02-29');

      // End-of-month schedule (dueDay == 31)
      expect(dueDateForPeriod('2026-01', 31), '2026-01-31');
      expect(dueDateForPeriod('2026-04', 31), '2026-04-30');
      expect(dueDateForPeriod('2026-02', 31), '2026-02-28');
      expect(dueDateForPeriod('2028-02', 31), '2028-02-29');
      expect(endOfMonthForPeriod('2026-02'), '2026-02-28');
      expect(endOfMonthForPeriod('2028-02'), '2028-02-29');
    });

    test('rejects malformed periods and out-of-range due days', () {
      expect(() => dueDateForPeriod('2026-13', 5), throwsFormatException);
      expect(() => dueDateForPeriod('2026-2', 5), throwsFormatException);
      expect(() => dueDateForPeriod('2026-02', 0), throwsRangeError);
      expect(() => dueDateForPeriod('2026-02', 32), throwsRangeError);
    });

    test('ordinalDay and dueDayLabel produce readable schedule strings', () {
      expect(ordinalDay(1), '1st');
      expect(ordinalDay(2), '2nd');
      expect(ordinalDay(3), '3rd');
      expect(ordinalDay(5), '5th');
      expect(ordinalDay(11), '11th');
      expect(ordinalDay(12), '12th');
      expect(ordinalDay(13), '13th');
      expect(ordinalDay(15), '15th');
      expect(ordinalDay(21), '21st');
      expect(ordinalDay(30), '30th');
      expect(dueDayLabel(5), 'Every 5th');
      expect(dueDayLabel(15, short: true), '15th');
      expect(dueDayLabel(31), 'End of month (last day)');
      expect(dueDayLabel(31, short: true), 'End of month');
      expect(isEndOfMonthDueDay(31), isTrue);
      expect(isEndOfMonthDueDay(30), isFalse);
    });
  });

  group('Collection week & display formatters', () {
    test('manilaCollectionWeek spans 7 inclusive days across month boundaries', () {
      // 2026-02-25 10:00 Manila (02:00 UTC) -> Feb 25 .. Mar 03 (non-leap Feb)
      final clock = DateTime.utc(2026, 2, 25, 2, 0);
      final week = manilaCollectionWeek(clock);
      expect(week.start, '2026-02-25');
      expect(week.end, '2026-03-03');
      expect(isDueThisWeek('2026-02-25', clock: clock), isTrue);
      expect(isDueThisWeek('2026-02-28', clock: clock), isTrue);
      expect(isDueThisWeek('2026-03-03', clock: clock), isTrue);
      expect(isDueThisWeek('2026-02-24', clock: clock), isFalse);
      expect(isDueThisWeek('2026-03-04', clock: clock), isFalse);
      expect(isOverdueDate('2026-02-24', clock: clock), isTrue);
      expect(isOverdueDate('2026-02-25', clock: clock), isFalse);
    });

    test('allocation-free formatters format periods, dates, and timestamps', () {
      expect(formatPeriodLabel('2026-11'), 'November 2026');
      expect(formatPeriodLabel('invalid'), 'invalid');
      expect(formatIsoDateLabel('2026-11-05'), '5 Nov 2026');
      expect(
        formatIsoDateLabel('2026-11-05', includeWeekday: true),
        'Thu, 5 Nov 2026',
      );
      expect(
        formatManilaTimestamp('2026-02-28T16:30:00Z'),
        '1 Mar 2026, 12:30 AM (Manila)',
      );
      expect(formatManilaTimestamp('not-a-timestamp'), 'not-a-timestamp');
    });
  });
}

