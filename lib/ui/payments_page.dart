import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;
import '../data/repository.dart';
import '../services/documents.dart';
import 'collections_page.dart';
import 'common.dart';

class PaymentsPage extends StatefulWidget {
  final AppData data;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final String period;
  const PaymentsPage({
    super.key,
    required this.data,
    required this.repository,
    required this.onChanged,
    required this.period,
  });
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  bool allHistory = false;
  @override
  Widget build(BuildContext context) {
    final monthlyPayments = widget.data.payments
        .where(
          (p) =>
              (p['date'] as String).startsWith(widget.period) &&
              p['reversed_at'] == null,
        )
        .toList();
    final total = monthlyPayments.fold<int>(
      0,
      (n, p) => n + (p['amount_cents'] as int),
    );
    final payments =
        widget.data.payments
            .where(
              (p) =>
                  allHistory || (p['date'] as String).startsWith(widget.period),
            )
            .toList()
          ..sort((a, b) {
            final byDate = (b['date'] as String).compareTo(a['date'] as String);
            return byDate != 0 ? byDate : (b['id'] as int).compareTo(a['id'] as int);
          });
    final outstanding =
        widget.data.invoices
            .where(
              (i) =>
                  i['status'] == 'final' &&
                  widget.data.balance(i['id'] as int) > 0,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['due_date'] as String).compareTo(b['due_date'] as String),
          );
    final schedule = CollectionsSchedule.from(widget.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          eyebrow: 'Every payment, accounted for',
          title: 'Keep the good records.',
          subtitle:
              'Full or partial payments. Cash, GCash, or bank. Every transaction stays in your ledger.',
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RECEIVED THIS MONTH',
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                money(total),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${monthlyPayments.length} payment${monthlyPayments.length == 1 ? '' : 's'} received in ${monthLabel(widget.period)}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 5),
              const Text(
                'Based on payment date. Security deposits are kept separately.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('payments-collections-day'),
          onPressed: () => openCollectionsDay(
            context,
            data: widget.data,
            repository: widget.repository,
            onChanged: widget.onChanged,
          ),
          icon: const Icon(Icons.bolt_rounded, color: amber),
          label: Text(
            schedule.actionableCount > 0
                ? 'Collections Day (${schedule.actionableCount} due · 1-tap pay & receipt)'
                : 'Open Collections Day (1-tap pay & receipt)',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => recordPaymentDialog(
            context,
            data: widget.data,
            repository: widget.repository,
            onChanged: widget.onChanged,
          ),
          icon: const Icon(Icons.add),
          label: const Text('Record a payment'),
        ),
        if (outstanding.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Ready to collect',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...outstanding
              .take(6)
              .map(
                (invoice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.data.room(invoice['room_id'] as int)?['name']} · ${widget.data.tenantName(invoice['tenancy_id'] as int)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${monthLabel(invoice['period'] as String)} · due ${dateLabel(invoice['due_date'] as String)}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              money(widget.data.balance(invoice['id'] as int)),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            StatusPill(invoiceStatus(widget.data, invoice)),
                            TextButton.icon(
                              onPressed: () => recordPaymentDialog(
                                context,
                                data: widget.data,
                                repository: widget.repository,
                                onChanged: widget.onChanged,
                                invoiceId: invoice['id'] as int,
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Record payment'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (outstanding.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${outstanding.length - 6} more unpaid bills available in Record a payment.',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
        ],
        const SizedBox(height: 26),
        Text(
          'Transaction history',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show all months', style: TextStyle(fontSize: 14)),
          value: allHistory,
          onChanged: (value) => setState(() => allHistory = value),
        ),
        if (payments.isEmpty)
          const EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Your payment ledger is ready',
            description:
                'Payments will appear here as you record them. Finalize a bill in Monthly Billing to receive your first payment.',
          ),
        ...payments.map((p) {
          final paymentId = p['id'] as int;
          final allocation = widget.data.allocationsForPayment(paymentId);
          final invoice = allocation.isEmpty
              ? null
              : widget.data.invoice(allocation.first['invoice_id'] as int);
          final reversed = p['reversed_at'] != null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => paymentDetails(context, p),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: (reversed ? danger : ink).withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Icon(
                              reversed
                                  ? Icons.undo_rounded
                                  : p['method'] == 'Cash'
                                  ? Icons.payments_outlined
                                  : p['method'] == 'GCash'
                                  ? Icons.phone_android_outlined
                                  : Icons.account_balance_outlined,
                              color: reversed ? danger : ink,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoice == null
                                    ? 'Payment'
                                    : widget.data.tenantName(
                                        invoice['tenancy_id'] as int,
                                      ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${invoice == null ? '' : '${widget.data.room(invoice['room_id'] as int)?['name']} · '}${p['method']}',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  money(p['amount_cents'] as int),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: reversed ? muted : null,
                                    decoration: reversed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                dateLabel(p['date'] as String),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!reversed) ...[
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: 'Open receipt',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: () => perform(
                              context,
                              () => DocumentService.receipt(
                                widget.data,
                                paymentId,
                              ),
                            ),
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 19,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (reversed)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: StatusPill('Reversed'),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (payments.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Tap the receipt icon for an instant PDF receipt, or tap a payment to inspect or correct it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: muted, height: 1.5),
            ),
          ),
      ],
    );
  }

  Future<void> paymentDetails(BuildContext context, model.Row payment) async {
    final paymentId = payment['id'] as int;
    final allocations = widget.data.allocationsForPayment(paymentId);
    final reversed = payment['reversed_at'] != null;
    await showDetails(
      context,
      title: reversed ? 'Reversed payment' : 'Payment details',
      children: [
        Text(
          money(payment['amount_cents'] as int),
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        DetailRow('Payment date', dateLabel(payment['date'] as String)),
        DetailRow('Method', payment['method'] as String),
        DetailRow(
          'Receipt reference',
          'RCP-${paymentId.toString().padLeft(6, '0')}',
        ),
        if ((payment['reference'] as String).isNotEmpty)
          DetailRow('Transaction reference', payment['reference'] as String),
        if ((payment['notes'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              payment['notes'] as String,
              style: const TextStyle(color: muted, height: 1.5),
            ),
          ),
        const Divider(height: 24),
        ...allocations.map((a) {
          final invoice = widget.data.invoice(a['invoice_id'] as int)!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.data.tenantName(invoice['tenancy_id'] as int),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.data.room(invoice['room_id'] as int)?['name']} · ${monthLabel(invoice['period'] as String)}',
                style: const TextStyle(color: muted),
              ),
              DetailRow(
                'Applied to ${invoice['reference']}',
                money(a['amount_cents'] as int),
              ),
              DetailRow(
                'Current bill balance',
                money(widget.data.balance(invoice['id'] as int)),
              ),
              const SizedBox(height: 10),
            ],
          );
        }),
        if (reversed) ...[
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This payment was reversed',
                  style: TextStyle(color: danger, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  (payment['reversal_reason'] as String?) ?? '',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Its amount no longer reduces the bill balance.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => perform(
            context,
            () => DocumentService.receipt(widget.data, paymentId),
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open PDF receipt'),
        ),
        if (!reversed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: danger),
              onPressed: () {
                Navigator.pop(context);
                reversePayment(context, payment);
              },
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Correct this payment'),
            ),
          ),
      ],
    );
  }

  Future<void> reversePayment(BuildContext context, model.Row payment) async {
    final reason = TextEditingController();
    final result = await showEditor(
      context,
      title: 'Reverse this payment?',
      description:
          '${money(payment['amount_cents'] as int)} will be restored to the bill’s unpaid balance. The original transaction and your reason will stay in the audit history. If needed, record a new payment with the correct details afterward.',
      fields: (context, _) =>
          input(reason, 'Reason for correction', lines: 3, required: true),
      onSave: () => widget.repository.reversePayment(
        payment['id'] as int,
        requiredText(reason, 'a reason for the correction'),
      ),
      saveLabel: 'Reverse payment',
      destructive: true,
    );
    if (result) widget.onChanged();
    reason.dispose();
  }
}

Future<void> recordPaymentDialog(
  BuildContext context, {
  required AppData data,
  required RentalRepository repository,
  required VoidCallback onChanged,
  int? invoiceId,
}) async {
  final bills =
      data.invoices
          .where(
            (i) => i['status'] == 'final' && data.balance(i['id'] as int) > 0,
          )
          .toList()
        ..sort(
          (a, b) =>
              (a['due_date'] as String).compareTo(b['due_date'] as String),
        );
  if (bills.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No unpaid bills yet'),
        content: const Text(
          'Prepare and finalize a bill in Monthly Billing before recording a payment. Fully paid bills do not need another payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    return;
  }
  var selected = invoiceId ?? bills.first['id'] as int;
  final amount = TextEditingController(text: decimalOf(data.balance(selected)));
  final date = TextEditingController(text: manilaToday());
  final reference = TextEditingController();
  final notes = TextEditingController();
  var method = 'Cash';
  final requestId = const Uuid().v4();
  final result = await showEditor(
    context,
    title: 'Record a payment',
    description:
        'Choose the bill, then enter the amount received. Partial payments are welcome.',
    fields: (context, setState) {
      final invoice = data.invoice(selected)!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<int>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bill to pay'),
              items: bills
                  .map(
                    (i) => DropdownMenuItem<int>(
                      value: i['id'] as int,
                      child: Text(
                        '${data.room(i['room_id'] as int)?['name']} · ${data.tenantName(i['tenancy_id'] as int)} · ${monthLabel(i['period'] as String)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selected = value;
                    amount.text = decimalOf(data.balance(value));
                  });
                }
              },
            ),
          ),
          SectionCard(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFEEF3E9)
                : null,
            child: Column(
              children: [
                DetailRow(
                  'Unpaid on this bill',
                  money(data.balance(selected)),
                  strong: true,
                ),
                DetailRow('Due date', dateLabel(invoice['due_date'] as String)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          input(
            amount,
            'Amount received',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
            helper: 'Enter a smaller amount to record a partial payment.',
          ),
          DateInput(controller: date, label: 'Payment date'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Payment method',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const ['Cash', 'GCash', 'Bank transfer', 'Other']
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m),
                      selected: method == m,
                      onSelected: (_) => setState(() => method = m),
                    ),
                  )
                  .toList(),
            ),
          ),
          input(reference, 'Transaction reference (optional)'),
          input(notes, 'Payment notes (optional)', lines: 2),
        ],
      );
    },
    onSave: () async {
      await repository.recordPayment(
        invoiceId: selected,
        amountCents: parseFixed(amount.text),
        date: date.text,
        method: method,
        requestId: requestId,
        reference: reference.text.trim(),
        notes: notes.text.trim(),
      );
    },
    saveLabel: 'Save payment',
  );
  if (result) onChanged();
  for (final c in [amount, date, reference, notes]) {
    c.dispose();
  }
}
