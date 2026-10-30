import 'package:intl/intl.dart';

/// Audit timestamps are UTC; billing dates are already Manila calendar dates.
String formatManilaTimestamp(String input) {
  final parsed = DateTime.tryParse(input);
  if (parsed == null) return input;
  final value = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(input)
      ? parsed.toUtc().add(const Duration(hours: 8))
      : parsed;
  return '${DateFormat('d MMM yyyy, h:mm a').format(value)} (Manila)';
}
