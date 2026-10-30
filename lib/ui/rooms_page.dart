import 'package:flutter/material.dart';
import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;
import '../data/repository.dart';
import 'common.dart';

class RoomsPage extends StatefulWidget {
  final AppData data;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final String period;
  const RoomsPage({
    super.key,
    required this.data,
    required this.repository,
    required this.onChanged,
    required this.period,
  });
  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  bool showArchived = false;
  @override
  Widget build(BuildContext context) {
    final rooms =
        widget.data.rooms
            .where((r) => showArchived || r['archived'] == 0)
            .toList()
          ..sort((a, b) => (a['name'] as String).compareTo(b['name']));
    final active = widget.data.rooms.where((r) => r['archived'] == 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: 'A place for every tenant',
          title: 'Rooms & tenants',
          subtitle:
              '$active room${active == 1 ? '' : 's'} in your property. Keep agreements and past stays together.',
        ),
        FilledButton.icon(
          onPressed: () => editRoom(context),
          icon: const Icon(Icons.add),
          label: const Text('Add a room'),
        ),
        if (widget.data.rooms.any((r) => r['archived'] == 1))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show archived rooms',
                style: TextStyle(fontSize: 14),
              ),
              value: showArchived,
              onChanged: (value) => setState(() => showArchived = value),
            ),
          ),
        const SizedBox(height: 22),
        if (rooms.isEmpty)
          const EmptyState(
            icon: Icons.meeting_room_outlined,
            title: 'Room for a fresh start',
            description:
                'Add a room with its monthly rent and utility rates. Then assign your first tenant.',
          ),
        ...rooms.map((room) {
          final tenancy = widget.data.activeTenancy(room['id']);
          final tenant = tenancy == null
              ? null
              : widget.data.tenant(tenancy['tenant_id']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: sage.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.meeting_room_outlined,
                          size: 26,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room['name'],
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${money(tenancy?['rent_cents'] ?? room['rent_cents'])} / month',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Room options',
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await editRoom(context, room);
                            return;
                          }
                          if (value == 'archive') {
                            final confirmed = await confirmAction(
                              context,
                              title: 'Archive ${room['name']}?',
                              message:
                                  'The room will be hidden from your active list. All tenant, bill, and payment history will be kept. Move the current tenant out first.',
                              confirmLabel: 'Archive room',
                              destructive: true,
                            );
                            if (confirmed && context.mounted) {
                              await perform(
                                context,
                                () => widget.repository.archiveRoom(room['id']),
                                onChanged: widget.onChanged,
                                success: 'Room archived. History is kept.',
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit room & utility rates'),
                          ),
                          if (room['archived'] == 0)
                            const PopupMenuItem(
                              value: 'archive',
                              child: Text('Archive room'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      StatusPill(
                        room['archived'] == 1
                            ? 'Archived'
                            : tenancy == null
                            ? 'Vacant'
                            : 'Occupied',
                      ),
                      if (tenancy != null)
                        Text(
                          'Due day ${tenancy['due_day']}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  if (tenancy != null) ...[
                    Text(
                      tenant?['name'] ?? 'Tenant',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (tenant?['phone'] as String? ?? '').isEmpty
                          ? 'No contact number saved'
                          : tenant!['phone'],
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Moved in ${dateLabel(tenancy['move_in'])}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => roomDetails(context, room),
                      icon: const Icon(Icons.person_outline, size: 19),
                      label: const Text('Tenant & room details'),
                    ),
                  ] else if (room['archived'] == 0) ...[
                    const Text(
                      'Ready for someone new.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => assignTenant(context, room),
                      icon: const Icon(Icons.person_add_alt_outlined, size: 19),
                      label: const Text('Assign a tenant'),
                    ),
                    if (widget.data.tenancies.any(
                      (t) => t['room_id'] == room['id'],
                    ))
                      TextButton(
                        onPressed: () => roomDetails(context, room),
                        child: const Text('View previous tenants'),
                      ),
                  ] else
                    TextButton(
                      onPressed: () => roomDetails(context, room),
                      child: const Text('View tenant history'),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        const Text(
          'Moving a tenant out keeps every past bill and payment. Security deposits are tracked separately from rent.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted, height: 1.5),
        ),
      ],
    );
  }

  Future<void> editRoom(BuildContext context, [model.Row? room]) async {
    final name = TextEditingController(text: room?['name'] ?? '');
    final rent = TextEditingController(
      text: decimalOf(room?['rent_cents'] ?? 0),
    );
    final electricRate = TextEditingController(
      text: decimalOf(room?['electricity_rate'] ?? 1200),
    );
    final waterRate = TextEditingController(
      text: decimalOf(room?['water_rate'] ?? 3500),
    );
    final notes = TextEditingController(text: room?['notes'] ?? '');
    var electricity = room?['electricity_mode'] as String? ?? 'metered';
    var water = room?['water_mode'] as String? ?? 'metered';
    final result = await showEditor(
      context,
      title: room == null ? 'Add a room' : 'Edit ${room['name']}',
      description:
          'Rates apply to new drafts. Finalized bills keep their original amounts.',
      fields: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          input(name, 'Room name or number', required: true),
          input(
            rent,
            'Monthly rent',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
          ),
          _utilityFields(
            'Electricity',
            electricity,
            electricRate,
            (mode) => setState(() => electricity = mode),
          ),
          _utilityFields(
            'Water',
            water,
            waterRate,
            (mode) => setState(() => water = mode),
          ),
          input(notes, 'Room notes (optional)', lines: 3),
        ],
      ),
      onSave: () async {
        await widget.repository.saveRoom({
          if (room != null) 'id': room['id'],
          'name': requiredText(name, 'a room name'),
          'rent_cents': parseFixed(rent.text),
          'electricity_mode': electricity,
          'electricity_rate': electricity == 'shared'
              ? 0
              : parseFixed(electricRate.text),
          'water_mode': water,
          'water_rate': water == 'shared' ? 0 : parseFixed(waterRate.text),
          'notes': notes.text.trim(),
          'archived': room?['archived'] ?? 0,
        });
      },
      saveLabel: room == null ? 'Add room' : 'Save room',
    );
    if (result) widget.onChanged();
    for (final c in [name, rent, electricRate, waterRate, notes]) {
      c.dispose();
    }
  }

  Widget _utilityFields(
    String label,
    String mode,
    TextEditingController rate,
    ValueChanged<String> onMode,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Billing method'),
          items: const [
            DropdownMenuItem(
              value: 'metered',
              child: Text(
                'Metered consumption',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'fixed',
              child: Text(
                'Fixed monthly charge',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'shared',
              child: Text(
                'Shared charge (allocated monthly)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) onMode(value);
          },
        ),
      ),
      if (mode != 'shared')
        input(
          rate,
          mode == 'metered'
              ? 'Rate per ${label == 'Water' ? 'cubic meter' : 'kWh'}'
              : 'Fixed monthly amount',
          prefix: '₱ ',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          required: true,
        )
      else
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text(
            'Enter this room’s share in the monthly billing worksheet.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
    ],
  );

  Future<void> assignTenant(BuildContext context, model.Row room) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    final moveIn = TextEditingController(text: isoDate(manilaNow()));
    final rent = TextEditingController(text: decimalOf(room['rent_cents']));
    final deposit = TextEditingController(text: '0.00');
    final day = TextEditingController(text: '5');
    final result = await showEditor(
      context,
      title: 'Welcome a new tenant',
      description:
          'Assign a tenant to ${room['name']}. Their agreed rent is saved with this stay.\n\nOne bill is allowed per room each month. Rent is not prorated automatically. For a replacement tenant in the same month, choose who to bill and enter any rent adjustment yourself.',
      fields: (context, _) => Column(
        children: [
          input(name, 'Full name', required: true),
          input(
            phone,
            'Contact number (optional)',
            keyboard: TextInputType.phone,
          ),
          DateInput(controller: moveIn, label: 'Move-in date'),
          input(
            rent,
            'Agreed monthly rent',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
          ),
          input(
            deposit,
            'Security deposit received',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            helper: 'Tracked separately from rent payments.',
          ),
          input(
            day,
            'Payment due day (1–31)',
            keyboard: TextInputType.number,
            helper: 'Shorter months use their last day.',
            required: true,
          ),
          input(notes, 'Tenant notes (optional)', lines: 3),
        ],
      ),
      onSave: () async {
        await widget.repository.assignTenant(
          roomId: room['id'],
          name: requiredText(name, 'the tenant’s name'),
          phone: phone.text.trim(),
          moveIn: moveIn.text,
          rentCents: parseFixed(rent.text),
          depositCents: parseFixed(deposit.text),
          dueDay: int.tryParse(day.text) ?? 0,
          notes: notes.text.trim(),
        );
      },
      saveLabel: 'Assign tenant',
    );
    if (result) widget.onChanged();
    for (final c in [name, phone, notes, moveIn, rent, deposit, day]) {
      c.dispose();
    }
  }

  Future<void> editTenant(BuildContext context, model.Row tenancy) async {
    final tenant = widget.data.tenant(tenancy['tenant_id'])!;
    final name = TextEditingController(text: tenant['name']);
    final phone = TextEditingController(text: tenant['phone']);
    final notes = TextEditingController(text: tenant['notes']);
    final rent = TextEditingController(text: decimalOf(tenancy['rent_cents']));
    final day = TextEditingController(text: '${tenancy['due_day']}');
    final result = await showEditor(
      context,
      title: 'Edit tenant agreement',
      description:
          'Changes apply to future drafts. Past finalized bills stay as they were.',
      fields: (context, _) => Column(
        children: [
          input(name, 'Full name', required: true),
          input(phone, 'Contact number', keyboard: TextInputType.phone),
          input(
            rent,
            'Agreed monthly rent',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
          ),
          input(
            day,
            'Payment due day (1–31)',
            keyboard: TextInputType.number,
            required: true,
          ),
          input(notes, 'Notes (optional)', lines: 3),
        ],
      ),
      onSave: () async {
        await widget.repository.updateTenant(
          tenancyId: tenancy['id'],
          name: requiredText(name, 'the tenant’s name'),
          phone: phone.text.trim(),
          rentCents: parseFixed(rent.text),
          dueDay: int.tryParse(day.text) ?? 0,
          notes: notes.text.trim(),
        );
      },
      saveLabel: 'Save agreement',
    );
    if (result) widget.onChanged();
    for (final c in [name, phone, notes, rent, day]) {
      c.dispose();
    }
  }

  Future<void> moveOut(BuildContext context, model.Row tenancy) async {
    final date = TextEditingController(text: isoDate(manilaNow()));
    final result = await showEditor(
      context,
      title: 'Move tenant out?',
      description:
          '${widget.data.tenantName(tenancy['id'])} will no longer occupy this room. Every past bill, payment, and deposit remains in the ledger. Settle the deposit separately.',
      fields: (context, _) =>
          DateInput(controller: date, label: 'Move-out date'),
      onSave: () => widget.repository.moveOut(tenancy['id'], date.text),
      saveLabel: 'Confirm move-out',
      destructive: true,
    );
    if (result) widget.onChanged();
    date.dispose();
  }

  Future<void> settleDeposit(BuildContext context, model.Row tenancy) async {
    final amount = TextEditingController(
      text: decimalOf(widget.data.depositBalance(tenancy['id'])),
    );
    final notes = TextEditingController();
    final date = TextEditingController(text: isoDate(manilaNow()));
    var kind = 'refund';
    final result = await showEditor(
      context,
      title: 'Settle security deposit',
      description:
          'Available deposit: ${money(widget.data.depositBalance(tenancy['id']))}. Deductions record the tenant’s authorized use of their deposit and do not count as rent collection.',
      fields: (context, setState) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Deposit action'),
              items: const [
                DropdownMenuItem(
                  value: 'refund',
                  child: Text(
                    'Refund to tenant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'deduction',
                  child: Text(
                    'Authorized deduction',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => kind = value);
              },
            ),
          ),
          input(
            amount,
            'Amount',
            prefix: '₱ ',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            required: true,
          ),
          DateInput(controller: date, label: 'Transaction date'),
          input(
            notes,
            'Reason / authorization',
            helper:
                'Describe the refund or the deduction agreed with the tenant.',
            lines: 3,
            required: true,
          ),
        ],
      ),
      onSave: () => widget.repository.settleDeposit(
        tenancyId: tenancy['id'],
        kind: kind,
        amountCents: parseFixed(amount.text),
        date: date.text,
        notes: requiredText(notes, 'a reason or authorization'),
      ),
      saveLabel: 'Record deposit transaction',
    );
    if (result) widget.onChanged();
    for (final c in [amount, notes, date]) {
      c.dispose();
    }
  }

  Future<void> roomDetails(BuildContext context, model.Row room) async {
    final stays =
        widget.data.tenancies.where((t) => t['room_id'] == room['id']).toList()
          ..sort((a, b) => (b['move_in'] as String).compareTo(a['move_in']));
    await showDetails(
      context,
      title: room['name'],
      children: [
        DetailRow('Default monthly rent', money(room['rent_cents'])),
        DetailRow(
          'Electricity',
          _utilityDescription(room, 'electricity', 'kWh'),
        ),
        DetailRow('Water', _utilityDescription(room, 'water', 'm³')),
        if ((room['notes'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(room['notes'], style: const TextStyle(color: muted)),
          ),
        const SizedBox(height: 16),
        Text('Tenant history', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (stays.isEmpty)
          const Text(
            'No tenants have been assigned yet.',
            style: TextStyle(color: muted),
          ),
        ...stays.map((stay) {
          final tenant = widget.data.tenant(stay['tenant_id'])!;
          final movements = widget.data.deposits
              .where((d) => d['tenancy_id'] == stay['id'])
              .toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tenant['name'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${dateLabel(stay['move_in'])} → ${stay['move_out'] == null ? 'Present' : dateLabel(stay['move_out'])}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  if ((tenant['phone'] as String).isNotEmpty)
                    DetailRow('Contact', tenant['phone']),
                  DetailRow('Agreed rent', money(stay['rent_cents'])),
                  DetailRow('Due day', '${stay['due_day']}'),
                  DetailRow(
                    'Deposit held',
                    money(widget.data.depositBalance(stay['id'])),
                    strong: true,
                  ),
                  if ((tenant['notes'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        tenant['notes'],
                        style: const TextStyle(color: muted),
                      ),
                    ),
                  ...movements.map(
                    (d) => DetailRow(
                      '${d['kind'] == 'received'
                          ? 'Received'
                          : d['kind'] == 'refund'
                          ? 'Refund'
                          : 'Deduction'} · ${dateLabel(d['date'])}',
                      money(d['amount_cents']),
                    ),
                  ),
                  if (widget.data.depositBalance(stay['id']) > 0 &&
                      stay['move_out'] != null)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        settleDeposit(context, stay);
                      },
                      child: const Text('Refund or deduct deposit'),
                    ),
                  if (widget.data.depositBalance(stay['id']) > 0 &&
                      stay['move_out'] == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Move the tenant out before refunding or deducting their deposit.',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  if (stay['move_out'] == null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        editTenant(context, stay);
                      },
                      child: const Text('Edit tenant agreement'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        moveOut(context, stay);
                      },
                      style: TextButton.styleFrom(foregroundColor: danger),
                      child: const Text('Move tenant out'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _utilityDescription(model.Row room, String kind, String unit) {
    if (room['${kind}_mode'] == 'shared') return 'Shared · entered monthly';
    if (room['${kind}_mode'] == 'fixed') {
      return '${money(room['${kind}_rate'])} / month';
    }
    return '${money(room['${kind}_rate'])} / $unit';
  }
}
