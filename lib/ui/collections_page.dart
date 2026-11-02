import 'package:flutter/material.dart';

import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;
import '../data/repository.dart';
import '../services/documents.dart';
import '../services/local_time.dart';
import 'billing_page.dart';
import 'common.dart';
import 'payments_page.dart';

/// Immutable, `Asia/Manila` snapshot of bills due this week, overdue follow-ups,
/// unbilled/draft stays due this week, and payments already collected today.
class CollectionsSchedule {
  final String today;
  final String weekEnd;
  final List<model.Row> dueThisWeek;
  final List<model.Row> overdue;
  final List<({model.Row tenancy, String period, String dueDate, model.Row? draft})>
  needsBilling;
  final List<model.Row> collectedToday;
  final int dueThisWeekCents;
  final int overdueCents;
  final int collectedTodayCents;

  const CollectionsSchedule({
    required this.today,
    required this.weekEnd,
    required this.dueThisWeek,
    required this.overdue,
    required this.needsBilling,
    required this.collectedToday,
    required this.dueThisWeekCents,
    required this.overdueCents,
    required this.collectedTodayCents,
  });

  int get actionableCount => dueThisWeek.length + overdue.length;

  factory CollectionsSchedule.from(AppData data, {DateTime? clock}) {
    final week = manilaCollectionWeek(clock);
    final today = week.start;
    final weekEnd = week.end;

    int compareInvoices(model.Row a, model.Row b) {
      final byDate = (a['due_date'] as String).compareTo(
        b['due_date'] as String,
      );
      if (byDate != 0) return byDate;
      final roomA = (data.room(a['room_id'] as int)?['name'] as String?) ?? '';
      final roomB = (data.room(b['room_id'] as int)?['name'] as String?) ?? '';
      return roomA.compareTo(roomB);
    }

    final dueThisWeek = <model.Row>[];
    final overdue = <model.Row>[];
    var dueThisWeekCents = 0;
    var overdueCents = 0;

    for (final invoice in data.invoices) {
      if (invoice['status'] != 'final') continue;
      final balance = data.balance(invoice['id'] as int);
      if (balance <= 0) continue;
      final dueDate = invoice['due_date'] as String;
      if (dueDate.compareTo(today) < 0) {
        overdue.add(invoice);
        overdueCents += balance;
      } else if (dueDate.compareTo(weekEnd) <= 0) {
        dueThisWeek.add(invoice);
        dueThisWeekCents += balance;
      }
    }
    dueThisWeek.sort(compareInvoices);
    overdue.sort(compareInvoices);

    // Check active tenancies whose due date falls in the 7-day window (including
    // month rollovers, e.g., Feb 27 -> Mar 5) that still lack a finalized bill.
    final candidatePeriods = <String>{
      today.substring(0, 7),
      weekEnd.substring(0, 7),
    };
    final needsBilling =
        <({model.Row tenancy, String period, String dueDate, model.Row? draft})>[];
    for (final tenancy in data.tenancies) {
      if (tenancy['move_out'] != null) continue;
      final room = data.room(tenancy['room_id'] as int);
      if (room == null || room['archived'] == 1) continue;
      final tenancyId = tenancy['id'] as int;
      final moveInMonth = (tenancy['move_in'] as String).substring(0, 7);
      for (final period in candidatePeriods) {
        if (moveInMonth.compareTo(period) > 0) continue;
        final existing = data
            .invoicesForPeriod(period)
            .where((inv) => inv['tenancy_id'] == tenancyId)
            .firstOrNull;
        if (existing != null && existing['status'] == 'final') continue;
        final resolvedDue =
            (existing?['due_date'] as String?) ??
            dueDateForPeriod(period, tenancy['due_day'] as int);
        if (resolvedDue.compareTo(today) >= 0 &&
            resolvedDue.compareTo(weekEnd) <= 0) {
          needsBilling.add((
            tenancy: tenancy,
            period: period,
            dueDate: resolvedDue,
            draft: existing,
          ));
        }
      }
    }
    needsBilling.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final collectedToday = <model.Row>[];
    var collectedTodayCents = 0;
    for (final payment in data.payments) {
      if (payment['reversed_at'] != null) continue;
      if (payment['date'] == today) {
        collectedToday.add(payment);
        collectedTodayCents += payment['amount_cents'] as int;
      }
    }
    collectedToday.sort(
      (a, b) => (b['id'] as int).compareTo(a['id'] as int),
    );

    return CollectionsSchedule(
      today: today,
      weekEnd: weekEnd,
      dueThisWeek: dueThisWeek,
      overdue: overdue,
      needsBilling: needsBilling,
      collectedToday: collectedToday,
      dueThisWeekCents: dueThisWeekCents,
      overdueCents: overdueCents,
      collectedTodayCents: collectedTodayCents,
    );
  }
}

/// Pushes the full-screen Collections Day route (1st tap from top bar or cards).
Future<void> openCollectionsDay(
  BuildContext context, {
  required AppData data,
  required RentalRepository repository,
  required VoidCallback onChanged,
  DateTime? manilaClock,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => CollectionsScreen(
      initialData: data,
      repository: repository,
      onChanged: onChanged,
      manilaClock: manilaClock,
    ),
  ),
);

/// Full-screen Collections Day route that refreshes its own ledger snapshot
/// immediately after 1-tap payments so landlords never leave the screen.
class CollectionsScreen extends StatefulWidget {
  final AppData initialData;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final DateTime? manilaClock;
  final Future<void> Function(AppData data, int paymentId)? onOpenReceipt;

  const CollectionsScreen({
    super.key,
    required this.initialData,
    required this.repository,
    required this.onChanged,
    this.manilaClock,
    this.onOpenReceipt,
  });

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late AppData _data = widget.initialData;

  Future<AppData> _reload() async {
    final fresh = await widget.repository.load();
    if (mounted) {
      setState(() => _data = fresh);
    }
    widget.onChanged();
    return fresh;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Collections Day',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sage.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  'Asia/Manila',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CollectionsView(
                data: _data,
                repository: widget.repository,
                onReload: _reload,
                manilaClock: widget.manilaClock,
                onOpenReceipt: widget.onOpenReceipt,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Core Collections Day content widget. Optimized for <3 taps:
/// 1 tap to record full payment (`Record paid`) + 1 tap to open receipt (`Receipt`),
/// or a single `Pay & receipt` tap that records payment and opens the PDF receipt.
class CollectionsView extends StatefulWidget {
  final AppData data;
  final RentalRepository repository;
  final Future<AppData> Function() onReload;
  final DateTime? manilaClock;
  final Future<void> Function(AppData data, int paymentId)? onOpenReceipt;

  const CollectionsView({
    super.key,
    required this.data,
    required this.repository,
    required this.onReload,
    this.manilaClock,
    this.onOpenReceipt,
  });

  @override
  State<CollectionsView> createState() => _CollectionsViewState();
}

class _CollectionsViewState extends State<CollectionsView> {
  static const List<String> _methods = [
    'Cash',
    'GCash',
    'Bank transfer',
    'Other',
  ];

  String _method = 'Cash';
  int? _busyInvoiceId;

  Future<void> _openReceipt(AppData data, int paymentId) async {
    final handler = widget.onOpenReceipt ?? DocumentService.receipt;
    await handler(data, paymentId);
  }

  Future<void> _oneTapCollect(
    model.Row invoice, {
    required bool openReceiptImmediately,
  }) async {
    if (_busyInvoiceId != null) return;
    final invoiceId = invoice['id'] as int;
    final remaining = widget.data.balance(invoiceId);
    if (remaining <= 0) return;

    final today = manilaToday(widget.manilaClock);
    // Deterministic idempotency key per invoice + current paid state prevents
    // accidental double-taps from recording duplicate payments.
    final requestId = 'collect-$invoiceId-${widget.data.paid(invoiceId)}';

    setState(() => _busyInvoiceId = invoiceId);
    try {
      final paymentId = await widget.repository.recordPayment(
        invoiceId: invoiceId,
        amountCents: remaining,
        date: today,
        method: _method,
        requestId: requestId,
        notes: 'Recorded via Collections Day',
      );
      final fresh = await widget.onReload();
      if (!mounted) return;
      if (openReceiptImmediately) {
        await _openReceipt(fresh, paymentId);
      } else {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Paid ${money(remaining)} ($_method) · ${fresh.tenantName(invoice['tenancy_id'] as int)}',
            ),
            action: SnackBarAction(
              label: 'Receipt',
              onPressed: () {
                perform(context, () => _openReceipt(fresh, paymentId));
              },
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(friendlyError(error)),
            backgroundColor: danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyInvoiceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = CollectionsSchedule.from(
      widget.data,
      clock: widget.manilaClock,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${dateLabel(schedule.today)} – ${dateLabel(schedule.weekEnd)}'
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Who is due this week',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F6253), Color(0xFF133D34), Color(0xFF0C2620)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 10,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DUE IN NEXT 7 DAYS (${schedule.dueThisWeek.length})',
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFCDE5D3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        money(schedule.dueThisWeekCents),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _heroStat(
                      'Collected today',
                      money(schedule.collectedTodayCents),
                      const Color(0xFFAAD7B9),
                    ),
                    if (schedule.overdueCents > 0)
                      _heroStat(
                        'Overdue (${schedule.overdue.length})',
                        money(schedule.overdueCents),
                        const Color(0xFFF7D488),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text(
                  'Method:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
              ..._methods.map(
                (m) => ChoiceChip(
                  key: ValueKey('collect-method-$m'),
                  visualDensity: VisualDensity.compact,
                  label: Text(m),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (schedule.dueThisWeek.isEmpty &&
            schedule.overdue.isEmpty &&
            schedule.needsBilling.isEmpty)
          const EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'All caught up for this week',
            description:
                'No unpaid finalized bills are due in the next 7 days. Collected payments for today remain below for quick receipts.',
          ),
        if (schedule.dueThisWeek.isNotEmpty) ...[
          _sectionTitle(
            context,
            'Due this week (${schedule.dueThisWeek.length})',
          ),
          const SizedBox(height: 10),
          ...schedule.dueThisWeek.map(
            (invoice) => _buildCollectCard(
              context,
              invoice: invoice,
              today: schedule.today,
              isOverdue: false,
              isDark: isDark,
            ),
          ),
        ],
        if (schedule.overdue.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle(
            context,
            'Overdue follow-up (${schedule.overdue.length})',
          ),
          const SizedBox(height: 10),
          ...schedule.overdue.map(
            (invoice) => _buildCollectCard(
              context,
              invoice: invoice,
              today: schedule.today,
              isOverdue: true,
              isDark: isDark,
            ),
          ),
        ],
        if (schedule.needsBilling.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle(
            context,
            'Prepare bill first (${schedule.needsBilling.length})',
          ),
          const SizedBox(height: 10),
          ...schedule.needsBilling.map((item) {
            final room = widget.data.room(item.tenancy['room_id'] as int);
            final hasDraft = item.draft != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          '${room?['name'] ?? 'Room'} · ${widget.data.tenantName(item.tenancy['id'] as int)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        StatusPill(hasDraft ? 'Draft bill' : 'Needs readings'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Due ${dateLabel(item.dueDate)} (${dueDayLabel(item.tenancy['due_day'] as int)}) · Agreed rent ${money(item.tenancy['rent_cents'] as int)}',
                      style: const TextStyle(fontSize: 12.5, color: muted),
                    ),
                    if (hasDraft) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await confirmAction(
                            context,
                            title: 'Finalize this draft bill?',
                            message:
                                '${room?['name']} · ${widget.data.tenantName(item.tenancy['id'] as int)}\nTotal: ${money(item.draft!['total_cents'] as int)}',
                            confirmLabel: 'Finalize bill',
                          );
                          if (confirmed && context.mounted) {
                            await perform(
                              context,
                              () async {
                                await widget.repository.finalizeInvoice(
                                  item.draft!['id'] as int,
                                );
                                await widget.onReload();
                              },
                              success: 'Bill finalized and ready to collect.',
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(
                          'Finalize ${money(item.draft!['total_cents'] as int)} draft',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
        if (schedule.collectedToday.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle(
            context,
            'Collected today (${schedule.collectedToday.length})',
          ),
          const SizedBox(height: 10),
          ...schedule.collectedToday.map((payment) {
            final paymentId = payment['id'] as int;
            final allocation = widget.data
                .allocationsForPayment(paymentId)
                .firstOrNull;
            final invoice = allocation == null
                ? null
                : widget.data.invoice(allocation['invoice_id'] as int);
            final roomName = invoice == null
                ? ''
                : (widget.data.room(invoice['room_id'] as int)?['name']
                          as String? ??
                      '');
            final tenantName = invoice == null
                ? 'Payment'
                : widget.data.tenantName(invoice['tenancy_id'] as int);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: ink,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                roomName.isEmpty
                                    ? tenantName
                                    : '$roomName · $tenantName',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${payment['method']} · RCP-${paymentId.toString().padLeft(6, '0')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          money(payment['amount_cents'] as int),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: ValueKey('receipt-today-$paymentId'),
                      onPressed: () => perform(
                        context,
                        () => _openReceipt(widget.data, paymentId),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Receipt'),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _heroStat(String label, String value, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFFCAD8CA)),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    ],
  );

  Widget _sectionTitle(BuildContext context, String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );

  Widget _buildCollectCard(
    BuildContext context, {
    required model.Row invoice,
    required String today,
    required bool isOverdue,
    required bool isDark,
  }) {
    final invoiceId = invoice['id'] as int;
    final room = widget.data.room(invoice['room_id'] as int);
    final tenancy = widget.data.tenancy(invoice['tenancy_id'] as int);
    final tenantName = widget.data.tenantName(invoice['tenancy_id'] as int);
    final remaining = widget.data.balance(invoiceId);
    final dueIso = invoice['due_date'] as String;
    final dueToday = dueIso == today;
    final busy = _busyInvoiceId == invoiceId;
    final scheduleHint = tenancy == null
        ? ''
        : ' · ${dueDayLabel(tenancy['due_day'] as int)}';

    final dueCaption = dueToday
        ? 'Due today · ${dateLabel(dueIso)}$scheduleHint'
        : isOverdue
        ? 'Overdue since ${dateLabel(dueIso)}$scheduleHint'
        : 'Due ${formatIsoDateLabel(dueIso, includeWeekday: true)}$scheduleHint';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        key: ValueKey('collect-card-$invoiceId'),
        padding: const EdgeInsets.all(16),
        color: isOverdue && !isDark ? const Color(0xFFFCF2EC) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  '${room?['name'] ?? 'Room'} · $tenantName',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                StatusPill(
                  dueToday
                      ? 'Due today'
                      : invoiceStatus(widget.data, invoice),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              dueCaption,
              style: TextStyle(
                fontSize: 12.5,
                color: isOverdue ? danger : muted,
                fontWeight: isOverdue || dueToday
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Amount due',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(remaining),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'View bill details',
                  onPressed: () =>
                      showInvoiceDetails(context, widget.data, invoice),
                  icon: const Icon(Icons.description_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: ValueKey('pay-receipt-$invoiceId'),
              onPressed: busy
                  ? null
                  : () => _oneTapCollect(
                      invoice,
                      openReceiptImmediately: true,
                    ),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded, size: 20),
              label: Text('Pay & receipt ($_method)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('record-paid-$invoiceId'),
                  onPressed: busy
                      ? null
                      : () => _oneTapCollect(
                          invoice,
                          openReceiptImmediately: false,
                        ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Record paid'),
                ),
                TextButton(
                  key: ValueKey('partial-pay-$invoiceId'),
                  onPressed: busy
                      ? null
                      : () => recordPaymentDialog(
                          context,
                          data: widget.data,
                          repository: widget.repository,
                          onChanged: () {
                            widget.onReload();
                          },
                          invoiceId: invoiceId,
                        ),
                  child: const Text('Partial / custom'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
