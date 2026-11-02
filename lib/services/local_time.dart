/// Asia/Manila (UTC+08:00, no DST) calendar, due-date, and timestamp utilities.
///
/// All financial dates in Upa Renta are stored as ISO `YYYY-MM-DD` strings in
/// the `Asia/Manila` timezone, and billing periods as `YYYY-MM`.
library;

const Duration manilaOffset = Duration(hours: 8);

const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _fullMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _shortWeekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Converts [clock] (or the current instant) to wall-clock time in `Asia/Manila`.
DateTime manilaNow([DateTime? clock]) =>
    (clock ?? DateTime.now()).toUtc().add(manilaOffset);

/// Formats [date] as `YYYY-MM-DD` using its calendar components.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Today's `YYYY-MM-DD` date in `Asia/Manila`.
String manilaToday([DateTime? clock]) => isoDate(manilaNow(clock));

/// Formats [date] as billing period `YYYY-MM`.
String billingPeriod(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

/// Exact number of calendar days in [month] (`1..12`) of [year], including
/// February in leap years (29) and common years (28).
int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Clamps a target due [day] (`1..31`) to the valid range for [year]-[month].
///
/// - `5` -> 5th of every month
/// - `15` -> 15th of every month
/// - `30` -> 30th (or 28th/29th in February)
/// - `31` -> End of month (31st, 30th, 29th in leap Feb, 28th in common Feb)
int clampDayToMonth(int year, int month, int day) {
  final clamped = day.clamp(1, 31);
  final maxDay = daysInMonth(year, month);
  return clamped > maxDay ? maxDay : clamped;
}

/// Computes the exact `YYYY-MM-DD` due date in `Asia/Manila` for [period]
/// (`YYYY-MM`) and agreed [dueDay] (`1..31`, where `31` represents end-of-month).
String dueDateForPeriod(String period, int dueDay) {
  final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(period);
  if (match == null) {
    throw FormatException('Invalid billing period: $period');
  }
  if (dueDay < 1 || dueDay > 31) {
    throw RangeError.range(dueDay, 1, 31, 'dueDay');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = clampDayToMonth(year, month, dueDay);
  return isoDate(DateTime.utc(year, month, day));
}

/// Last calendar day `YYYY-MM-DD` of [period] (`YYYY-MM`).
String endOfMonthForPeriod(String period) => dueDateForPeriod(period, 31);

/// Whether [dueDay] represents the end-of-month schedule (`31`).
bool isEndOfMonthDueDay(int dueDay) => dueDay >= 31;

/// English ordinal label for a day number (`1` -> `'1st'`, `15` -> `'15th'`).
String ordinalDay(int day) {
  final mod100 = day.abs() % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${day}th';
  return switch (day.abs() % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// Human-friendly label for a tenancy's [dueDay].
String dueDayLabel(int dueDay, {bool short = false}) {
  if (dueDay >= 31) {
    return short ? 'End of month' : 'End of month (last day)';
  }
  return short ? ordinalDay(dueDay) : 'Every ${ordinalDay(dueDay)}';
}

/// Fast, allocation-free formatting of `YYYY-MM` -> `'MMMM yyyy'`.
String formatPeriodLabel(String period) {
  final parts = period.split('-');
  if (parts.length == 2) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year != null && month != null && month >= 1 && month <= 12) {
      return '${_fullMonths[month - 1]} $year';
    }
  }
  return period;
}

/// Fast, allocation-free formatting of `YYYY-MM-DD` -> `'d MMM yyyy'`.
String formatIsoDateLabel(String value, {bool includeWeekday = false}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return value;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return value;
  final base = '$day ${_shortMonths[month - 1]} $year';
  if (!includeWeekday) return base;
  final utc = DateTime.utc(year, month, day);
  return '${_shortWeekdays[utc.weekday - 1]}, $base';
}

/// Returns the inclusive 7-day Manila collection window `(start, end)` as ISO
/// dates starting at Manila today (`[today, today + 6 days]`).
({String start, String end}) manilaCollectionWeek([DateTime? clock]) {
  final now = manilaNow(clock);
  final today = DateTime.utc(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 6));
  return (start: isoDate(today), end: isoDate(end));
}

/// Returns `true` when [dueDate] falls within the 7-day Manila collection window
/// `[today, today + 6 days]`.
bool isDueThisWeek(String dueDate, {DateTime? clock}) {
  final window = manilaCollectionWeek(clock);
  return dueDate.compareTo(window.start) >= 0 &&
      dueDate.compareTo(window.end) <= 0;
}

/// Returns `true` when [dueDate] is strictly before Manila today.
bool isOverdueDate(String dueDate, {DateTime? clock}) =>
    dueDate.compareTo(manilaToday(clock)) < 0;

/// Audit timestamps are UTC; billing dates are already Manila calendar dates.
String formatManilaTimestamp(String input) {
  final parsed = DateTime.tryParse(input);
  if (parsed == null) return input;
  final value = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(input)
      ? parsed.toUtc().add(manilaOffset)
      : parsed;
  final month = _shortMonths[value.month - 1];
  final hour24 = value.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day} $month ${value.year}, $hour12:$minute $period (Manila)';
}
