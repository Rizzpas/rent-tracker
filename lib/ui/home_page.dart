import 'package:flutter/material.dart';
import '../data/models.dart' hide Row;
import '../data/repository.dart';
import 'billing_page.dart';
import 'collections_page.dart';
import 'common.dart';
import 'payments_page.dart';

class HomePage extends StatelessWidget {
  final AppData data;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final String period;
  final ValueChanged<int> onNavigate;
  const HomePage({
    super.key,
    required this.data,
    required this.repository,
    required this.onChanged,
    required this.period,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final today = manilaToday();
    final rooms = data.rooms.where((r) => r['archived'] == 0).toList();
    final occupied = rooms
        .where((r) => data.activeTenancy(r['id'] as int) != null)
        .length;
    final periodInvoices = data.invoicesForPeriod(period);
    final bills = periodInvoices.where((i) => i['status'] == 'final').toList();
    final drafts = periodInvoices.where((i) => i['status'] == 'draft').length;
    final billed = bills.fold<int>(0, (n, i) => n + (i['total_cents'] as int));
    final collected = data.payments
        .where(
          (p) =>
              (p['date'] as String).startsWith(period) &&
              p['reversed_at'] == null,
        )
        .fold<int>(0, (n, p) => n + (p['amount_cents'] as int));
    final outstanding = data.invoices
        .where((i) => i['status'] == 'final')
        .fold<int>(0, (n, i) => n + data.balance(i['id'] as int));
    final previousBalance = data.invoices
        .where(
          (i) =>
              i['status'] == 'final' &&
              (i['period'] as String).compareTo(period) < 0,
        )
        .fold<int>(0, (n, i) => n + data.balance(i['id'] as int));
    final overdue = data.invoices
        .where(
          (i) =>
              i['status'] == 'final' &&
              (i['due_date'] as String).compareTo(today) < 0 &&
              data.balance(i['id'] as int) > 0,
        )
        .toList();
    final overdueAmount = overdue.fold<int>(
      0,
      (n, i) => n + data.balance(i['id'] as int),
    );
    final paid = bills.where((i) => data.balance(i['id'] as int) == 0).length;
    final partial = bills
        .where(
          (i) =>
              data.balance(i['id'] as int) > 0 && data.paid(i['id'] as int) > 0,
        )
        .length;
    final unpaid = bills
        .where(
          (i) =>
              data.balance(i['id'] as int) > 0 &&
              data.paid(i['id'] as int) == 0,
        )
        .length;
    final expectedByRoom = <int, int>{};
    for (final invoice in periodInvoices) {
      expectedByRoom[invoice['room_id'] as int] = invoice['total_cents'] as int;
    }
    final monthlyStays =
        data.tenancies
            .where(
              (t) =>
                  (t['move_in'] as String).substring(0, 7).compareTo(period) <=
                      0 &&
                  (t['move_out'] == null ||
                      (t['move_out'] as String).compareTo('$period-01') > 0),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b['move_in'] as String).compareTo(a['move_in'] as String),
          );
    for (final stay in monthlyStays) {
      expectedByRoom.putIfAbsent(
        stay['room_id'] as int,
        () => stay['rent_cents'] as int,
      );
    }
    final expected = expectedByRoom.values.fold<int>(
      0,
      (n, amount) => n + amount,
    );
    final upcoming =
        data.invoices
            .where(
              (i) =>
                  i['status'] == 'final' &&
                  data.balance(i['id'] as int) > 0 &&
                  (i['due_date'] as String).compareTo(today) >= 0,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['due_date'] as String).compareTo(b['due_date'] as String),
          );
    final schedule = CollectionsSchedule.from(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          eyebrow: 'Your property, at a glance',
          title: 'A little peace of mind.',
          subtitle: 'Your rooms, bills, and collections — all in one place.',
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F6253), Color(0xFF133B33), Color(0xFF0C241F)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.savings_outlined,
                          color: Color(0xFFD4EBD0),
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'PAYMENTS RECEIVED · ${monthLabel(period).toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD8E9D6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    money(collected),
                    style: const TextStyle(
                      fontSize: 38,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Money received this month, including older bills.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFCAD8CA),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Billed this month',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFCAD8CA),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  money(billed),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Unpaid balances',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFCAD8CA),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  money(outstanding),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFF5D88B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C2E26)
              : const Color(0xFFEAF3EC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: amber, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collections Day · Asia/Manila',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                schedule.actionableCount == 0
                    ? 'No unpaid bills due this week. Tap to review today’s receipts.'
                    : '${schedule.dueThisWeek.length} due this week (${money(schedule.dueThisWeekCents)})'
                          '${schedule.overdue.isEmpty ? '' : ' · ${schedule.overdue.length} overdue'}. One tap to pay & print receipt.',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('home-collections-day'),
                onPressed: () => openCollectionsDay(
                  context,
                  data: data,
                  repository: repository,
                  onChanged: onChanged,
                ),
                icon: const Icon(Icons.bolt_rounded, size: 19),
                label: const Text('Open Collections Day'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _smallStat(
                context,
                constraints.maxWidth,
                Icons.door_front_door_outlined,
                '$occupied / ${rooms.length}',
                'Rooms occupied',
                '${rooms.length - occupied} vacant',
              ),
              _smallStat(
                context,
                constraints.maxWidth,
                Icons.receipt_long_outlined,
                '${bills.length}',
                'Finalized bills',
                '$drafts awaiting review',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Quick actions',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed:
              data.invoices.any(
                (i) =>
                    i['status'] == 'final' && data.balance(i['id'] as int) > 0,
              )
              ? () => recordPaymentDialog(
                  context,
                  data: data,
                  repository: repository,
                  onChanged: onChanged,
                )
              : () => onNavigate(3),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Record custom payment'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => onNavigate(2),
          icon: const Icon(Icons.electric_meter_outlined),
          label: const Text('Enter readings & prepare bills'),
        ),
        const SizedBox(height: 24),
        if (rooms.isEmpty)
          EmptyState(
            icon: Icons.cottage_outlined,
            title: 'Welcome to Upa Renta',
            description:
                'Start with your first room, then add a tenant. Your records stay safely on this device.',
            action: FilledButton.icon(
              onPressed: () => onNavigate(1),
              icon: const Icon(Icons.add),
              label: const Text('Add your first room'),
            ),
          )
        else ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This month’s billing',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                DetailRow('Expected charges', money(expected), strong: true),
                const Text(
                  'Includes agreed rent for rooms without a bill. Utilities are added when readings are entered.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill('$paid paid'),
                    StatusPill('$partial partial'),
                    StatusPill('$unpaid unpaid'),
                  ],
                ),
                const SizedBox(height: 10),
                DetailRow('Unpaid from earlier months', money(previousBalance)),
                const Text(
                  'Earlier balances stay on their original bills and are never added to new charges.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Room-by-room',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => onNavigate(2),
                child: const Text('View bills'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rooms.map((room) {
            final roomBills = periodInvoices
                .where((i) => i['room_id'] == room['id'])
                .toList();
            final active = data.activeTenancy(room['id'] as int);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: sage.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.meeting_room_outlined,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                active == null
                                    ? 'Available for a new tenant'
                                    : '${data.tenantName(active['id'] as int)} · ${dueDayLabel(active['due_day'] as int)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (roomBills.isEmpty)
                          StatusPill(active == null ? 'Vacant' : 'No bill'),
                      ],
                    ),
                    ...roomBills.map(
                      (invoice) => Padding(
                        padding: const EdgeInsets.only(top: 13),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              showInvoiceDetails(context, data, invoice),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data.tenantName(
                                        invoice['tenancy_id'] as int,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      invoice['status'] == 'draft'
                                          ? '${money(invoice['total_cents'] as int)} draft'
                                          : '${money(data.balance(invoice['id'] as int))} remaining',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: StatusPill(invoiceStatus(data, invoice)),
                              ),
                              const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFFCF0E9)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_outlined, color: danger, size: 21),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Needs a little follow-up',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${money(overdueAmount)} overdue across ${overdue.length} bill${overdue.length == 1 ? '' : 's'}.',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 10),
                ...overdue
                    .take(4)
                    .map(
                      (i) => DetailRow(
                        '${data.room(i['room_id'] as int)?['name']} · ${data.tenantName(i['tenancy_id'] as int)}',
                        money(data.balance(i['id'] as int)),
                      ),
                    ),
              ],
            ),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Coming up',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: upcoming
                  .take(5)
                  .map(
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            size: 20,
                            color: muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${data.room(i['room_id'] as int)?['name']} · ${data.tenantName(i['tenancy_id'] as int)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Due ${dateLabel(i['due_date'] as String)}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            money(data.balance(i['id'] as int)),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: muted),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Upa Renta · Private by design, stored offline on your device.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _smallStat(
    BuildContext context,
    double width,
    IconData icon,
    String value,
    String label,
    String detail,
  ) => SizedBox(
    width: (width - 12) / 2,
    child: SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: sage.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: ink, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(fontSize: 10.5, color: muted)),
        ],
      ),
    ),
  );
}
