export '../services/local_time.dart'
    show
        billingPeriod,
        clampDayToMonth,
        daysInMonth,
        dueDateForPeriod,
        dueDayLabel,
        endOfMonthForPeriod,
        isDueThisWeek,
        isEndOfMonthDueDay,
        isOverdueDate,
        isoDate,
        manilaCollectionWeek,
        manilaNow,
        manilaToday,
        ordinalDay;

typedef Row = Map<String, dynamic>;

/// All monetary values are integer centavos; meter values are integer thousandths.
///
/// Uses an auto-refreshing O(1) lookup index so scrolling and dashboard
/// summaries stay smooth even on low-end Android phones with years of history.
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

  _DataIndex? _cache;

  AppData({
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

  _DataIndex get _index {
    final current = _cache;
    if (current != null && current.matches(this)) return current;
    final built = _DataIndex.build(this);
    _cache = built;
    return built;
  }

  Row? room(int id) => _index.roomById[id];
  Row? tenant(int id) => _index.tenantById[id];
  Row? tenancy(int id) => _index.tenancyById[id];
  Row? invoice(int id) => _index.invoiceById[id];
  Row? payment(int id) => _index.paymentById[id];

  List<Row> linesForInvoice(int invoiceId) =>
      _index.linesByInvoice[invoiceId] ?? const [];
  List<Row> readingsForInvoice(int invoiceId) =>
      _index.readingsByInvoice[invoiceId] ?? const [];
  List<Row> allocationsForInvoice(int invoiceId) =>
      _index.allocationsByInvoice[invoiceId] ?? const [];
  List<Row> allocationsForPayment(int paymentId) =>
      _index.allocationsByPayment[paymentId] ?? const [];
  List<Row> depositsForTenancy(int tenancyId) =>
      _index.depositsByTenancy[tenancyId] ?? const [];
  List<Row> tenanciesForRoom(int roomId) =>
      _index.tenanciesByRoom[roomId] ?? const [];
  List<Row> invoicesForPeriod(String period) =>
      _index.invoicesByPeriod[period] ?? const [];

  Row? activeTenancy(int roomId) {
    for (final t in tenanciesForRoom(roomId)) {
      if (t['move_out'] == null) return t;
    }
    return null;
  }

  String tenantName(int tenancyId) {
    final t = tenancy(tenancyId);
    return t == null
        ? 'Former tenant'
        : (tenant(t['tenant_id'] as int)?['name'] as String? ?? 'Tenant');
  }

  int paid(int invoiceId) {
    var sum = 0;
    final idx = _index;
    final list = idx.allocationsByInvoice[invoiceId];
    if (list == null) return 0;
    for (final a in list) {
      final p = idx.paymentById[a['payment_id'] as int];
      if (p != null && p['reversed_at'] == null) {
        sum += a['amount_cents'] as int;
      }
    }
    return sum;
  }

  int balance(int invoiceId) =>
      (invoice(invoiceId)?['total_cents'] as int? ?? 0) - paid(invoiceId);

  int depositBalance(int tenancyId) {
    var sum = 0;
    for (final d in depositsForTenancy(tenancyId)) {
      sum +=
          (d['kind'] == 'received' ? 1 : -1) * (d['amount_cents'] as int);
    }
    return sum;
  }
}

class _DataIndex {
  final int roomsLen,
      tenantsLen,
      tenanciesLen,
      readingsLen,
      invoicesLen,
      linesLen,
      paymentsLen,
      allocationsLen,
      depositsLen;

  final Map<int, Row> roomById;
  final Map<int, Row> tenantById;
  final Map<int, Row> tenancyById;
  final Map<int, Row> invoiceById;
  final Map<int, Row> paymentById;
  final Map<int, List<Row>> tenanciesByRoom;
  final Map<int, List<Row>> linesByInvoice;
  final Map<int, List<Row>> readingsByInvoice;
  final Map<int, List<Row>> allocationsByInvoice;
  final Map<int, List<Row>> allocationsByPayment;
  final Map<int, List<Row>> depositsByTenancy;
  final Map<String, List<Row>> invoicesByPeriod;

  const _DataIndex({
    required this.roomsLen,
    required this.tenantsLen,
    required this.tenanciesLen,
    required this.readingsLen,
    required this.invoicesLen,
    required this.linesLen,
    required this.paymentsLen,
    required this.allocationsLen,
    required this.depositsLen,
    required this.roomById,
    required this.tenantById,
    required this.tenancyById,
    required this.invoiceById,
    required this.paymentById,
    required this.tenanciesByRoom,
    required this.linesByInvoice,
    required this.readingsByInvoice,
    required this.allocationsByInvoice,
    required this.allocationsByPayment,
    required this.depositsByTenancy,
    required this.invoicesByPeriod,
  });

  bool matches(AppData data) =>
      roomsLen == data.rooms.length &&
      tenantsLen == data.tenants.length &&
      tenanciesLen == data.tenancies.length &&
      readingsLen == data.readings.length &&
      invoicesLen == data.invoices.length &&
      linesLen == data.lines.length &&
      paymentsLen == data.payments.length &&
      allocationsLen == data.allocations.length &&
      depositsLen == data.deposits.length;

  factory _DataIndex.build(AppData data) {
    final roomById = <int, Row>{
      for (final r in data.rooms) r['id'] as int: r,
    };
    final tenantById = <int, Row>{
      for (final t in data.tenants) t['id'] as int: t,
    };
    final tenancyById = <int, Row>{};
    final tenanciesByRoom = <int, List<Row>>{};
    for (final t in data.tenancies) {
      tenancyById[t['id'] as int] = t;
      (tenanciesByRoom[t['room_id'] as int] ??= <Row>[]).add(t);
    }
    final invoiceById = <int, Row>{};
    final invoicesByPeriod = <String, List<Row>>{};
    for (final i in data.invoices) {
      invoiceById[i['id'] as int] = i;
      final period = i['period'] as String?;
      if (period != null) {
        (invoicesByPeriod[period] ??= <Row>[]).add(i);
      }
    }
    final paymentById = <int, Row>{
      for (final p in data.payments) p['id'] as int: p,
    };
    final linesByInvoice = <int, List<Row>>{};
    for (final l in data.lines) {
      (linesByInvoice[l['invoice_id'] as int] ??= <Row>[]).add(l);
    }
    final readingsByInvoice = <int, List<Row>>{};
    for (final r in data.readings) {
      (readingsByInvoice[r['invoice_id'] as int] ??= <Row>[]).add(r);
    }
    final allocationsByInvoice = <int, List<Row>>{};
    final allocationsByPayment = <int, List<Row>>{};
    for (final a in data.allocations) {
      (allocationsByInvoice[a['invoice_id'] as int] ??= <Row>[]).add(a);
      (allocationsByPayment[a['payment_id'] as int] ??= <Row>[]).add(a);
    }
    final depositsByTenancy = <int, List<Row>>{};
    for (final d in data.deposits) {
      (depositsByTenancy[d['tenancy_id'] as int] ??= <Row>[]).add(d);
    }
    return _DataIndex(
      roomsLen: data.rooms.length,
      tenantsLen: data.tenants.length,
      tenanciesLen: data.tenancies.length,
      readingsLen: data.readings.length,
      invoicesLen: data.invoices.length,
      linesLen: data.lines.length,
      paymentsLen: data.payments.length,
      allocationsLen: data.allocations.length,
      depositsLen: data.deposits.length,
      roomById: roomById,
      tenantById: tenantById,
      tenancyById: tenancyById,
      invoiceById: invoiceById,
      paymentById: paymentById,
      tenanciesByRoom: tenanciesByRoom,
      linesByInvoice: linesByInvoice,
      readingsByInvoice: readingsByInvoice,
      allocationsByInvoice: allocationsByInvoice,
      allocationsByPayment: allocationsByPayment,
      depositsByTenancy: depositsByTenancy,
      invoicesByPeriod: invoicesByPeriod,
    );
  }
}

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
