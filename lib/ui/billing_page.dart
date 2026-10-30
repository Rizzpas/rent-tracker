import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;
import '../data/repository.dart';
import '../services/documents.dart';
import 'common.dart';

class BillingPage extends StatelessWidget {
  final AppData data;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final String period;
  const BillingPage({
    super.key,
    required this.data,
    required this.repository,
    required this.onChanged,
    required this.period,
  });
  @override
  Widget build(BuildContext context) {
    final eligible =
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
            (a, b) => (data.room(a['room_id'])?['name'] as String).compareTo(
              data.room(b['room_id'])?['name'] as String,
            ),
          );
    final bills = data.invoices.where((i) => i['period'] == period).toList();
    final draftCount = bills.where((i) => i['status'] == 'draft').length;
    final total = bills.fold<int>(0, (n, i) => n + (i['total_cents'] as int));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          eyebrow: 'Monthly billing worksheet',
          title: 'Read. Review. Ready.',
          subtitle:
              'Enter each room’s readings, review the charges, then finalize the bill.',
        ),
        if (eligible.isNotEmpty || bills.isNotEmpty) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHARGES PREPARED',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  money(total),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${bills.length} bills · $draftCount drafts awaiting finalization',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Drafts are excluded from collections and outstanding balances.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (eligible.isEmpty && bills.isEmpty)
          const EmptyState(
            icon: Icons.electric_meter_outlined,
            title: 'No tenants to bill this month',
            description:
                'Assign a tenant in Rooms, or choose a month during an existing tenant’s stay. Their room will appear here.',
          ),
        ...eligible.map((tenancy) {
          final room = data.room(tenancy['room_id'])!;
          final matches = bills.where((i) => i['tenancy_id'] == tenancy['id']);
          final invoice = matches.isEmpty ? null : matches.first;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room['name'],
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              data.tenantName(tenancy['id']),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: StatusPill(
                          invoice == null
                              ? 'To prepare'
                              : invoiceStatus(data, invoice),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (invoice == null) ...[
                    DetailRow('Agreed rent', money(tenancy['rent_cents'])),
                    DetailRow(
                      'Electricity',
                      _utilityLabel(room, 'electricity', 'kWh'),
                    ),
                    DetailRow('Water', _utilityLabel(room, 'water', 'm³')),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => editBill(context, tenancy, room),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Enter readings & prepare'),
                    ),
                  ] else ...[
                    ...data.lines
                        .where((l) => l['invoice_id'] == invoice['id'])
                        .map(
                          (l) => DetailRow(
                            _kindLabel(l['kind']),
                            money(l['amount_cents']),
                          ),
                        ),
                    const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 6),
                      child: Divider(height: 1),
                    ),
                    DetailRow(
                      'New charges',
                      money(invoice['total_cents']),
                      strong: true,
                    ),
                    if (invoice['status'] == 'final')
                      DetailRow(
                        'Still to pay',
                        money(data.balance(invoice['id'])),
                        strong: true,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Due ${dateLabel(invoice['due_date'])} · ${invoice['reference']}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 16),
                    if (invoice['status'] == 'draft') ...[
                      FilledButton.icon(
                        onPressed: () async {
                          final confirmed = await confirmAction(
                            context,
                            title: 'Finalize this bill?',
                            message:
                                '${room['name']} · ${data.tenantName(tenancy['id'])}\n\nNew charges: ${money(invoice['total_cents'])}\nDue: ${dateLabel(invoice['due_date'])}\n\nThe readings, rates, and amounts will be locked. Review the breakdown before continuing.',
                            confirmLabel: 'Finalize bill',
                          );
                          if (confirmed && context.mounted) {
                            await perform(
                              context,
                              () => repository.finalizeInvoice(invoice['id']),
                              onChanged: onChanged,
                              success:
                                  'Bill finalized. It is ready for payment.',
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Finalize bill'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () =>
                            editBill(context, tenancy, room, invoice),
                        child: const Text('Edit readings & charges'),
                      ),
                      TextButton(
                        onPressed: () =>
                            showInvoiceDetails(context, data, invoice),
                        child: const Text('Review full breakdown'),
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: () =>
                            showInvoiceDetails(context, data, invoice),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('View bill & statement'),
                      ),
                  ],
                ],
              ),
            ),
          );
        }),
        ...bills
            .where((i) => !eligible.any((t) => t['id'] == i['tenancy_id']))
            .map(
              (invoice) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${data.room(invoice['room_id'])?['name']} · ${data.tenantName(invoice['tenancy_id'])}',
                    ),
                    subtitle: Text(money(invoice['total_cents'])),
                    trailing: StatusPill(invoiceStatus(data, invoice)),
                    onTap: () => showInvoiceDetails(context, data, invoice),
                  ),
                ),
              ),
            ),
        if (eligible.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'One bill per room each month. Rent is not prorated automatically; enter an adjustment for partial months or a change of tenant. Previous balances stay on their original bills.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          ),
      ],
    );
  }

  Future<void> editBill(
    BuildContext context,
    model.Row tenancy,
    model.Row room, [
    model.Row? invoice,
  ]) async {
    final earlierFinalIds = data.invoices
        .where(
          (i) =>
              i['room_id'] == room['id'] &&
              i['status'] == 'final' &&
              (i['period'] as String).compareTo(period) < 0,
        )
        .map((i) => i['id'])
        .toSet();
    model.Row? previousReading(String kind) {
      final readings =
          data.readings
              .where(
                (r) =>
                    r['room_id'] == room['id'] &&
                    r['kind'] == kind &&
                    earlierFinalIds.contains(r['invoice_id']),
              )
              .toList()
            ..sort((a, b) => (b['period'] as String).compareTo(a['period']));
      return readings.isEmpty ? null : readings.first;
    }

    model.Row? currentReading(String kind) {
      final readings = data.readings.where(
        (r) => r['invoice_id'] == invoice?['id'] && r['kind'] == kind,
      );
      return readings.isEmpty ? null : readings.first;
    }

    final previousElectricity = previousReading('electricity');
    final previousWater = previousReading('water');
    final electricityPrevious = TextEditingController(
      text: decimalOf(
        previousElectricity?['current_value'] ??
            currentReading('electricity')?['previous_value'] ??
            0,
        3,
      ),
    );
    final waterPrevious = TextEditingController(
      text: decimalOf(
        previousWater?['current_value'] ??
            currentReading('water')?['previous_value'] ??
            0,
        3,
      ),
    );
    final electricityCurrent = TextEditingController(
      text: currentReading('electricity') == null
          ? ''
          : decimalOf(currentReading('electricity')!['current_value'], 3),
    );
    final waterCurrent = TextEditingController(
      text: currentReading('water') == null
          ? ''
          : decimalOf(currentReading('water')!['current_value'], 3),
    );
    final electricLine = data.lines.where(
      (l) => l['invoice_id'] == invoice?['id'] && l['kind'] == 'electricity',
    );
    final waterLine = data.lines.where(
      (l) => l['invoice_id'] == invoice?['id'] && l['kind'] == 'water',
    );
    final adjustmentLines = data.lines.where(
      (l) => l['invoice_id'] == invoice?['id'] && l['kind'] == 'adjustment',
    );
    final electricityShared = TextEditingController(
      text: electricLine.isEmpty
          ? '0.00'
          : decimalOf(electricLine.first['amount_cents']),
    );
    final waterShared = TextEditingController(
      text: waterLine.isEmpty
          ? '0.00'
          : decimalOf(waterLine.first['amount_cents']),
    );
    final adjustment = TextEditingController(
      text: adjustmentLines.isEmpty
          ? '0.00'
          : decimalOf(adjustmentLines.first['amount_cents']),
    );
    final adjustmentNote = TextEditingController(
      text: adjustmentLines.isEmpty ? '' : adjustmentLines.first['description'],
    );
    final start = DateTime.parse('$period-01');
    final maxDay = DateTime(start.year, start.month + 1, 0).day;
    final dueDate = TextEditingController(
      text:
          invoice?['due_date'] ??
          isoDate(
            DateTime(
              start.year,
              start.month,
              math.min(tenancy['due_day'] as int, maxDay),
            ),
          ),
    );
    final result = await showEditor(
      context,
      title: '${room['name']} · ${monthLabel(period)}',
      description:
          '${data.tenantName(tenancy['id'])}\nSave a draft first. You can review every charge before finalizing.',
      fields: (context, setState) {
        void changed(String _) => setState(() {});
        int? previewCharge(
          String kind,
          TextEditingController previous,
          TextEditingController current,
          TextEditingController shared,
        ) {
          try {
            final mode = room['${kind}_mode'];
            if (mode == 'fixed') return room['${kind}_rate'];
            if (mode == 'shared') return parseFixed(shared.text);
            final consumption =
                parseFixed(current.text, decimals: 3) -
                parseFixed(previous.text, decimals: 3);
            if (consumption < 0) return null;
            final rounded =
                (BigInt.from(consumption) *
                        BigInt.from(room['${kind}_rate'] as int) +
                    BigInt.from(500)) ~/
                BigInt.from(1000);
            if (rounded > BigInt.from(900000000000)) return null;
            return rounded.toInt();
          } catch (_) {
            return null;
          }
        }

        final electricAmount = previewCharge(
          'electricity',
          electricityPrevious,
          electricityCurrent,
          electricityShared,
        );
        final waterAmount = previewCharge(
          'water',
          waterPrevious,
          waterCurrent,
          waterShared,
        );
        int? adjustmentAmount;
        try {
          adjustmentAmount = parseFixed(adjustment.text, allowNegative: true);
        } catch (_) {}
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailRow('House rent', money(tenancy['rent_cents']), strong: true),
            const SizedBox(height: 14),
            _meterInputs(
              context,
              kind: 'electricity',
              label: 'Electricity',
              unit: 'kWh',
              room: room,
              previous: electricityPrevious,
              current: electricityCurrent,
              shared: electricityShared,
              hasPrevious: previousElectricity != null,
              amount: electricAmount,
              onChanged: changed,
            ),
            _meterInputs(
              context,
              kind: 'water',
              label: 'Water',
              unit: 'm³',
              room: room,
              previous: waterPrevious,
              current: waterCurrent,
              shared: waterShared,
              hasPrevious: previousWater != null,
              amount: waterAmount,
              onChanged: changed,
            ),
            input(
              adjustment,
              'Adjustment or discount',
              prefix: '₱ ',
              keyboard: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              helper: 'Use a minus sign for a discount, for example -500.00.',
              onChanged: changed,
            ),
            input(adjustmentNote, 'Adjustment reason (if any)', lines: 2),
            DateInput(controller: dueDate, label: 'Payment due date'),
            SectionCard(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFEEF3E9)
                  : null,
              child: DetailRow(
                'Estimated new charges',
                electricAmount == null ||
                        waterAmount == null ||
                        adjustmentAmount == null
                    ? 'Enter readings'
                    : money(
                        (tenancy['rent_cents'] as int) +
                            electricAmount +
                            waterAmount +
                            adjustmentAmount,
                      ),
                strong: true,
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
      onSave: () async {
        final adj = parseFixed(adjustment.text, allowNegative: true);
        if (adj != 0 && adjustmentNote.text.trim().isEmpty) {
          throw const FormatException(
            'Add a reason for this adjustment or discount.',
          );
        }
        await repository.saveDraft(
          tenancyId: tenancy['id'],
          period: period,
          dueDate: dueDate.text,
          electricityCurrent: room['electricity_mode'] == 'metered'
              ? parseFixed(electricityCurrent.text, decimals: 3)
              : null,
          waterCurrent: room['water_mode'] == 'metered'
              ? parseFixed(waterCurrent.text, decimals: 3)
              : null,
          electricityPrevious:
              room['electricity_mode'] == 'metered' &&
                  previousElectricity == null
              ? parseFixed(electricityPrevious.text, decimals: 3)
              : null,
          waterPrevious:
              room['water_mode'] == 'metered' && previousWater == null
              ? parseFixed(waterPrevious.text, decimals: 3)
              : null,
          electricitySharedCents: room['electricity_mode'] == 'shared'
              ? parseFixed(electricityShared.text)
              : null,
          waterSharedCents: room['water_mode'] == 'shared'
              ? parseFixed(waterShared.text)
              : null,
          adjustmentCents: adj,
          adjustmentNote: adjustmentNote.text.trim(),
        );
      },
      saveLabel: 'Save draft',
    );
    if (result) onChanged();
    for (final c in [
      electricityPrevious,
      waterPrevious,
      electricityCurrent,
      waterCurrent,
      electricityShared,
      waterShared,
      adjustment,
      adjustmentNote,
      dueDate,
    ]) {
      c.dispose();
    }
  }

  Widget _meterInputs(
    BuildContext context, {
    required String kind,
    required String label,
    required String unit,
    required model.Row room,
    required TextEditingController previous,
    required TextEditingController current,
    required TextEditingController shared,
    required bool hasPrevious,
    required int? amount,
    required ValueChanged<String> onChanged,
  }) {
    final mode = room['${kind}_mode'];
    String? consumption;
    try {
      final value =
          parseFixed(current.text, decimals: 3) -
          parseFixed(previous.text, decimals: 3);
      if (value >= 0) consumption = decimalOf(value, 3);
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Icon(
              kind == 'electricity'
                  ? Icons.bolt_outlined
                  : Icons.water_drop_outlined,
              size: 20,
              color: muted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (mode == 'metered') ...[
          if (hasPrevious)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Previous reading: ${previous.text} $unit\nFrom the last finalized bill.',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            )
          else
            input(
              previous,
              'Initial previous reading ($unit)',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              helper:
                  'Starting meter value before this billing period. It will carry forward automatically after finalization.',
              required: true,
              onChanged: onChanged,
            ),
          input(
            current,
            'Current reading ($unit)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
            onChanged: onChanged,
          ),
          Text(
            '${consumption == null ? '—' : '$consumption $unit'} × ${money(room['${kind}_rate'])} / $unit',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
        ] else if (mode == 'shared')
          input(
            shared,
            'This room’s allocated share',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            helper:
                'Enter the amount allocated to this room from the shared bill.',
            required: true,
            onChanged: onChanged,
          ),
        DetailRow(
          mode == 'fixed' ? 'Fixed monthly charge' : 'Calculated charge',
          amount == null ? '—' : money(amount),
          strong: true,
        ),
      ],
    );
  }

  String _utilityLabel(model.Row room, String kind, String unit) =>
      room['${kind}_mode'] == 'fixed'
      ? '${money(room['${kind}_rate'])} fixed'
      : room['${kind}_mode'] == 'shared'
      ? 'Shared monthly charge'
      : '${money(room['${kind}_rate'])} / $unit';
}

String _kindLabel(String kind) => switch (kind) {
  'rent' => 'House rent',
  'electricity' => 'Electricity',
  'water' => 'Water',
  _ => 'Adjustment / discount',
};

Future<void> showInvoiceDetails(
  BuildContext context,
  AppData data,
  model.Row invoice,
) async {
  final lines = data.lines
      .where((l) => l['invoice_id'] == invoice['id'])
      .toList();
  final readings = data.readings
      .where((r) => r['invoice_id'] == invoice['id'])
      .toList();
  final prior = data.invoices
      .where(
        (i) =>
            i['tenancy_id'] == invoice['tenancy_id'] &&
            i['status'] == 'final' &&
            (i['period'] as String).compareTo(invoice['period']) < 0,
      )
      .fold<int>(0, (n, i) => n + data.balance(i['id']));
  final allocations = data.allocations
      .where((a) => a['invoice_id'] == invoice['id'])
      .toList();
  await showDetails(
    context,
    title: 'Billing statement',
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              invoice['reference'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          StatusPill(invoiceStatus(data, invoice)),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        data.tenantName(invoice['tenancy_id']),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      Text(
        '${data.room(invoice['room_id'])?['name']} · ${monthLabel(invoice['period'])}',
        style: const TextStyle(color: muted),
      ),
      DetailRow('Due date', dateLabel(invoice['due_date'])),
      const Divider(height: 24),
      ...lines.map(
        (l) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailRow(
              _kindLabel(l['kind']),
              money(l['amount_cents']),
              strong: true,
            ),
            if ((l['description'] as String).isNotEmpty)
              Text(
                l['description'],
                style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
              ),
            if (l['kind'] == 'electricity' || l['kind'] == 'water')
              Text(
                '${decimalOf(l['quantity'], 3)} × ${money(l['rate_cents'])}',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ...readings.map(
        (r) => DetailRow(
          '${r['kind'] == 'electricity' ? 'Electric' : 'Water'} meter',
          '${decimalOf(r['previous_value'], 3)} → ${decimalOf(r['current_value'], 3)}',
        ),
      ),
      const Divider(height: 24),
      DetailRow(
        'This month’s new charges',
        money(invoice['total_cents']),
        strong: true,
      ),
      DetailRow('Paid toward this bill', money(data.paid(invoice['id']))),
      DetailRow(
        'Remaining on this bill',
        money(data.balance(invoice['id'])),
        strong: true,
      ),
      if (prior > 0) ...[
        const SizedBox(height: 14),
        SectionCard(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xFFFFF7E9)
              : null,
          child: Column(
            children: [
              DetailRow('Earlier unpaid bills', money(prior), strong: true),
              const Text(
                'Shown for reference. This amount is kept on the original bills and is not included in the new charges above.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ],
      if (allocations.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Text(
          'Payment history',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...allocations.map((a) {
          final p = data.payments.firstWhere((p) => p['id'] == a['payment_id']);
          return DetailRow(
            '${dateLabel(p['date'])} · ${p['method']}${p['reversed_at'] == null ? '' : ' · reversed'}',
            money(a['amount_cents']),
          );
        }),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () => perform(
          context,
          () => DocumentService.statement(data, invoice['id']),
        ),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Open PDF statement'),
      ),
      if (invoice['status'] == 'draft')
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'This is a draft and has not been added to outstanding balances.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ),
    ],
  );
}
