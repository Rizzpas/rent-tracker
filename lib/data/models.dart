typedef Row = Map<String, dynamic>;

/// All monetary values are integer centavos; meter values are integer thousandths.
class AppData {
  final List<Row> rooms,
      tenants,
      tenancies,
      readings,
      invoices,
      lines,
      payments,
      allocations,
      deposits,
      audit;
  final Map<String, String> settings;
  const AppData({
    required this.rooms,
    required this.tenants,
    required this.tenancies,
    required this.readings,
    required this.invoices,
    required this.lines,
    required this.payments,
    required this.allocations,
    required this.deposits,
    required this.audit,
    required this.settings,
  });
  Row? room(int id) => _find(rooms, id);
  Row? tenant(int id) => _find(tenants, id);
  Row? tenancy(int id) => _find(tenancies, id);
  Row? invoice(int id) => _find(invoices, id);
  Row? activeTenancy(int roomId) {
    for (final t in tenancies) {
      if (t['room_id'] == roomId && t['move_out'] == null) return t;
    }
    return null;
  }

  String tenantName(int tenancyId) {
    final t = tenancy(tenancyId);
    return t == null
        ? 'Former tenant'
        : (tenant(t['tenant_id'])?['name'] as String? ?? 'Tenant');
  }

  int paid(int invoiceId) {
    final valid = payments
        .where((p) => p['reversed_at'] == null)
        .map((p) => p['id'])
        .toSet();
    return allocations
        .where(
          (a) =>
              a['invoice_id'] == invoiceId && valid.contains(a['payment_id']),
        )
        .fold<int>(0, (n, a) => n + (a['amount_cents'] as int));
  }

  int balance(int invoiceId) =>
      (invoice(invoiceId)?['total_cents'] as int? ?? 0) - paid(invoiceId);
  int depositBalance(int tenancyId) => deposits
      .where((d) => d['tenancy_id'] == tenancyId)
      .fold<int>(
        0,
        (n, d) =>
            n + (d['kind'] == 'received' ? 1 : -1) * (d['amount_cents'] as int),
      );
  static Row? _find(List<Row> rows, int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}

DateTime manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String billingPeriod(DateTime date) => isoDate(date).substring(0, 7);

/// Parses exact decimal input, without binary floating point conversion.
int parseFixed(String input, {int decimals = 2, bool allowNegative = false}) {
  if (decimals < 1 || decimals > 6) {
    throw ArgumentError.value(
      decimals,
      'decimals',
      'Use 1 to 6 decimal places.',
    );
  }
  final text = input.trim().replaceAll(',', '');
  if (!RegExp(
    '^${allowNegative ? '-?' : ''}\\d+(\\.\\d{1,$decimals})?\$',
  ).hasMatch(text)) {
    throw FormatException(
      'Enter a valid number with up to $decimals decimal places.',
    );
  }
  final negative = text.startsWith('-');
  final parts = text.replaceFirst('-', '').split('.');
  final result =
      BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(decimals, '0'));
  if (result > BigInt.from(900000000000)) {
    throw const FormatException('This number is too large.');
  }
  return negative ? -result.toInt() : result.toInt();
}
