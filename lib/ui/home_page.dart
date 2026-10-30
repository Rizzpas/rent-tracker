import 'package:flutter/material.dart';
import '../data/models.dart' hide Row;
import '../data/repository.dart';
import 'common.dart';
import 'billing_page.dart';
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
    final rooms = data.rooms.where((r) => r['archived'] == 0).toList();
    final occupied = rooms
        .where((r) => data.activeTenancy(r['id']) != null)
        .length;
    final bills = data.invoices
        .where((i) => i['period'] == period && i['status'] == 'final')
        .toList();
    final drafts = data.invoices
        .where((i) => i['period'] == period && i['status'] == 'draft')
        .length;
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
        .fold<int>(0, (n, i) => n + data.balance(i['id']));
    final previousBalance = data.invoices
        .where(
          (i) =>
              i['status'] == 'final' &&
              (i['period'] as String).compareTo(period) < 0,
        )
        .fold<int>(0, (n, i) => n + data.balance(i['id']));
    final overdue = data.invoices
        .where(
          (i) =>
              i['status'] == 'final' &&
              (i['due_date'] as String).compareTo(isoDate(manilaNow())) < 0 &&
              data.balance(i['id']) > 0,
        )
        .toList();
    final overdueAmount = overdue.fold<int>(
      0,
      (n, i) => n + data.balance(i['id']),
    );
    final paid = bills.where((i) => data.balance(i['id']) == 0).length;
    final partial = bills
        .where((i) => data.balance(i['id']) > 0 && data.paid(i['id']) > 0)
        .length;
    final unpaid = bills
        .where((i) => data.balance(i['id']) > 0 && data.paid(i['id']) == 0)
        .length;
    final expectedByRoom = <int, int>{};
    for (final invoice in data.invoices.where((i) => i['period'] == period)) {
      expectedByRoom[invoice['room_id']] = invoice['total_cents'];
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
          ..sort((a, b) => (b['move_in'] as String).compareTo(a['move_in']));
    for (final stay in monthlyStays) {
      expectedByRoom.putIfAbsent(
        stay['room_id'],
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
                  data.balance(i['id']) > 0 &&
                  (i['due_date'] as String).compareTo(isoDate(manilaNow())) >=
                      0,
            )
            .toList()
          ..sort((a, b) => (a['due_date'] as String).compareTo(b['due_date']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          eyebrow: 'Your property, at a glance',
          title: 'A little peace of mind.',
          subtitle: 'Your rooms, bills, and collections — all in one place.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.savings_outlined,
                    color: Color(0xFFBCD3AB),
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'PAYMENTS RECEIVED · ${monthLabel(period).toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFCEE0CB),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(collected),
                  style: const TextStyle(
                    fontSize: 38,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.4,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Money received this month, including older bills.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFCAD8CA),
                  height: 1.5,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 17),
                child: Divider(color: Color(0xFF426155), height: 1),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Billed for this month',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFCAD8CA),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            money(billed),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All unpaid balances',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFFCAD8CA),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            money(outstanding),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE5D4A6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
          'A few quick actions',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              data.invoices.any(
                (i) => i['status'] == 'final' && data.balance(i['id']) > 0,
              )
              ? () => recordPaymentDialog(
                  context,
                  data: data,
                  repository: repository,
                  onChanged: onChanged,
                )
              : () => onNavigate(3),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Record a payment'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => onNavigate(2),
          icon: const Icon(Icons.electric_meter_outlined),
          label: const Text('Enter readings & prepare bills'),
        ),
        const SizedBox(height: 26),
        if (rooms.isEmpty)
          EmptyState(
            icon: Icons.cottage_outlined,
            title: 'Welcome to your new ledger',
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
            final roomBills = data.invoices
                .where(
                  (i) => i['room_id'] == room['id'] && i['period'] == period,
                )
                .toList();
            final active = data.activeTenancy(room['id']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: sage.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.meeting_room_outlined,
                            color: ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                active == null
                                    ? 'Available for a new tenant'
                                    : data.tenantName(active['id']),
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
                                      data.tenantName(invoice['tenancy_id']),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      invoice['status'] == 'draft'
                                          ? '${money(invoice['total_cents'])} draft'
                                          : '${money(data.balance(invoice['id']))} remaining',
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
                        '${data.room(i['room_id'])?['name']} · ${data.tenantName(i['tenancy_id'])}',
                        money(data.balance(i['id'])),
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
                                  '${data.room(i['room_id'])?['name']} · ${data.tenantName(i['tenancy_id'])}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Due ${dateLabel(i['due_date'])}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            money(data.balance(i['id'])),
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
                'Private by design. Stored on your device.',
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
          Icon(icon, color: muted, size: 22),
          const SizedBox(height: 14),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(detail, style: const TextStyle(fontSize: 10, color: muted)),
        ],
      ),
    ),
  );
}
