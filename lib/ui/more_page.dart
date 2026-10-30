import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart' hide Row;
import '../data/repository.dart';
import '../services/app_lock.dart';
import '../services/backup.dart';
import '../services/documents.dart';
import '../services/local_time.dart';
import '../services/reminders.dart';
import 'common.dart';

class MorePage extends StatefulWidget {
  final AppData data;
  final RentalRepository repository;
  final VoidCallback onChanged;
  final String period;
  const MorePage({
    super.key,
    required this.data,
    required this.repository,
    required this.onChanged,
    required this.period,
  });
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  bool _busy = false, _pin = false, _biometrics = false, _hasSafetyCopy = false;
  String? _securityError;
  @override
  void initState() {
    super.initState();
    _loadSecurity();
    _loadSafetyCopy();
  }

  Future<void> _loadSafetyCopy() async {
    try {
      final exists = await BackupService.hasSafetyCopy();
      if (mounted) setState(() => _hasSafetyCopy = exists);
    } catch (_) {
      /* Optional recovery copy; primary backups still work. */
    }
  }

  Future<void> _loadSecurity() async {
    try {
      final pin = await LockService.isEnabled();
      final bio = await LockService.biometricsEnabled();
      if (mounted) {
        setState(() {
          _pin = pin;
          _biometrics = bio;
          _securityError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _securityError =
              'Secure storage is unavailable. Restart your phone and try again.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      if (mounted && success != null) _message(success);
    } catch (error) {
      if (mounted) _message(friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? danger : null,
        ),
      );

  Future<void> _profile() async {
    final name = TextEditingController(
      text: widget.data.settings['property_name'],
    );
    final address = TextEditingController(
      text: widget.data.settings['property_address'],
    );
    final owner = TextEditingController(
      text: widget.data.settings['owner_name'],
    );
    final saved = await showEditor(
      context,
      title: 'Your property',
      description: 'These details appear on billing statements and receipts.',
      fields: (_, setState) => Column(
        children: [
          input(name, 'Property name', required: true),
          input(address, 'Property address', lines: 2),
          input(owner, 'Landlady / owner name'),
        ],
      ),
      onSave: () async => widget.repository.saveSettings({
        'property_name': requiredText(name, 'a property name'),
        'property_address': address.text.trim(),
        'owner_name': owner.text.trim(),
      }),
    );
    if (saved) widget.onChanged();
    _disposeAfter([name, address, owner]);
  }

  Future<void> _backup({bool safetyCopy = false}) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Save a backup'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'password'),
            child: const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Protect with a password'),
              subtitle: Text(
                'You will need this password to restore the backup.',
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'plain'),
            child: const ListTile(
              leading: Icon(Icons.save_alt_rounded),
              title: Text('Save without a password'),
              subtitle: Text('Store this file somewhere private and safe.'),
            ),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    String? password;
    if (mode == 'password') {
      password = await BackupService.askPassword(
        context,
        title: 'Protect your backup',
        description:
            'Use at least 8 characters. Keep this password somewhere safe; it cannot be recovered.',
        confirm: true,
      );
      if (password == null || !mounted) return;
    }
    await _run(() async {
      final saved = safetyCopy
          ? await BackupService.exportSafetyCopy(
              widget.repository,
              password: password,
            )
          : await BackupService.exportBackup(
              widget.repository,
              password: password,
            );
      if (mounted && saved) _message('Backup saved to your chosen location.');
    });
  }

  Future<void> _restore() async {
    await _run(() async {
      if (!await LockService.confirmIdentity(context) || !mounted) return;
      final restored = await BackupService.importBackup(
        widget.repository,
        context,
      );
      if (mounted && restored) {
        await _loadSafetyCopy();
        _message('Backup restored. Your records are ready.');
      }
    });
  }

  Future<void> _setPin() async {
    if (!await LockService.confirmIdentity(context) || !mounted) return;
    final pin = TextEditingController();
    final again = TextEditingController();
    await showEditor(
      context,
      title: _pin ? 'Change your PIN' : 'Protect your records',
      description:
          'Choose a 6-digit PIN. The app locks on launch and after 30 seconds in the background. '
          'Keep your PIN safe; it cannot be recovered. Backups do not contain your PIN.',
      fields: (_, setState) => Column(
        children: [
          TextFormField(
            controller: pin,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'New 6-digit PIN'),
            validator: (v) =>
                RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : 'Enter 6 digits.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: again,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Repeat PIN'),
            validator: (v) => v == pin.text ? null : 'The PINs do not match.',
          ),
        ],
      ),
      onSave: () => LockService.setPin(pin.text),
      saveLabel: 'Save PIN',
    );
    await _loadSecurity();
    _disposeAfter([pin, again]);
  }

  Future<void> _disablePin() async {
    if (!await LockService.confirmIdentity(context) || !mounted) return;
    if (!await confirmAction(
      context,
      title: 'Turn off the app lock?',
      message:
          'Anyone using your unlocked phone will be able to open your rental records.',
      confirmLabel: 'Turn off lock',
    )) {
      return;
    }
    await _run(() async {
      await LockService.disable();
      await _loadSecurity();
    });
  }

  Future<void> _toggleReminders(bool enabled) async {
    await _run(() async {
      if (enabled && !await ReminderService.requestPermission()) {
        throw const FormatException(
          'Notifications are not permitted. Enable them in your phone’s app settings, then try again.',
        );
      }
      await widget.repository.saveSettings({'reminders': '$enabled'});
      await ReminderService.reschedule(await widget.repository.load());
    });
  }

  Future<void> _meterDay() async {
    final day = TextEditingController(
      text: widget.data.settings['meter_day'] ?? '25',
    );
    final saved = await showEditor(
      context,
      title: 'Monthly meter reminder',
      description:
          'Choose a day from 1 to 28. Reminders are delivered around 9 AM, Manila time.',
      fields: (_, setState) => input(
        day,
        'Day of the month',
        keyboard: TextInputType.number,
        required: true,
      ),
      onSave: () async {
        final value = int.tryParse(day.text);
        if (value == null || value < 1 || value > 28) {
          throw const FormatException('Choose a day from 1 to 28.');
        }
        await widget.repository.saveSettings({'meter_day': '$value'});
        await ReminderService.reschedule(await widget.repository.load());
      },
    );
    if (saved) widget.onChanged();
    _disposeAfter([day]);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeader(
        eyebrow: 'Your property, in your hands',
        title: 'More',
        subtitle: 'Reports, settings, and a safe copy of your records.',
      ),
      SectionCard(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff243a32)
            : const Color(0xffe7eee2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              'Your records stay with you',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Everything works without internet. Save a backup outside this app regularly, especially before changing phones.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 14),
            Text(
              'Last saved backup: ${_lastBackup()}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _backup,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Save backup'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restore'),
                ),
              ],
            ),
            if (_hasSafetyCopy)
              TextButton.icon(
                onPressed: _busy ? null : () => _backup(safetyCopy: true),
                icon: const Icon(Icons.history_rounded),
                label: const Text('Save pre-restore safety copy'),
              ),
            TextButton(
              onPressed: () => showDetails(
                context,
                title: 'Keep a safe copy',
                children: const [
                  Text(
                    '1. Tap Save backup and choose a folder outside the app, such as Downloads or an attached USB drive.\n\n'
                    '2. Keep another copy on a separate device. A backup inside your phone alone cannot protect you if the phone is lost.\n\n'
                    '3. To restore, install Bahay Rent, open More → Restore, and select your .brbackup file. Enter the backup password if needed.\n\n'
                    '4. Review the file date and record counts. Confirm replacement only when you are ready. Current records are not merged.\n\n'
                    'After restoring, Save pre-restore safety copy lets you export the records that were on this phone before the latest restore.\n\n'
                    'Backups contain your property, room, tenant, billing, payment, deposit, settings, and audit records. Your app PIN stays on this device.',
                  ),
                ],
              ),
              child: const Text('Backup and restore instructions'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _label('Your records'),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _tile(
              Icons.assessment_outlined,
              'Reports & exports',
              'Monthly and yearly totals, CSV and PDF',
              () =>
                  _push(_ReportsPage(data: widget.data, period: widget.period)),
            ),
            _tile(
              Icons.history_rounded,
              'Bills & payment history',
              'All months, including reversed payments',
              () => _push(_HistoryPage(data: widget.data)),
            ),
            _tile(
              Icons.people_outline_rounded,
              'Tenancy & deposit history',
              'Move-ins, move-outs, refunds, deductions',
              () => _push(_TenancyHistoryPage(data: widget.data)),
            ),
            _tile(
              Icons.fact_check_outlined,
              'Activity & corrections',
              'A record of financial changes',
              () => _push(_AuditPage(data: widget.data)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _label('Property & preferences'),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _tile(
              Icons.home_work_outlined,
              widget.data.settings['property_name'] ?? 'Your property',
              'Property details for statements and receipts',
              _profile,
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark mode'),
              value: widget.data.settings['dark_mode'] == 'true',
              onChanged: _busy
                  ? null
                  : (value) => _run(
                      () => widget.repository.saveSettings({
                        'dark_mode': '$value',
                      }),
                    ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 6,
              ),
              secondary: const Icon(Icons.notifications_none_rounded),
              title: const Text('Local reminders'),
              subtitle: const Text(
                'Due dates, overdue bills, drafts, and meters',
              ),
              value: widget.data.settings['reminders'] == 'true',
              onChanged: _busy ? null : _toggleReminders,
            ),
            _tile(
              Icons.event_repeat_outlined,
              'Meter reading day',
              'Day ${widget.data.settings['meter_day'] ?? '25'} of each month · around 9 AM',
              _meterDay,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _label('Privacy & security'),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (_securityError != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _securityError!,
                  style: const TextStyle(color: danger),
                ),
              ),
            _tile(
              Icons.pin_outlined,
              _pin ? 'Change app PIN' : 'Set up app PIN',
              _pin
                  ? '6-digit PIN is enabled'
                  : 'Optional protection on this phone',
              _setPin,
            ),
            if (_pin) ...[
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Fingerprint or face unlock'),
                subtitle: const Text(
                  'Use biometrics already set up on your phone',
                ),
                value: _biometrics,
                onChanged: _busy
                    ? null
                    : (value) => _run(() async {
                        if (!await LockService.confirmIdentity(context)) return;
                        await LockService.setBiometrics(value);
                        await _loadSecurity();
                      }),
              ),
              _tile(
                Icons.lock_open_outlined,
                'Turn off app lock',
                'Requires your current PIN or biometrics',
                _disablePin,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (_busy) const LinearProgressIndicator(),
      const Padding(
        padding: EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          'BAHAY RENT  1.0\nMade for everyday rental care.\nPhilippine pesos · Asia/Manila · No online account',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, height: 1.8),
        ),
      ),
    ],
  );

  String _lastBackup() {
    final input = widget.data.settings['last_backup'] ?? '';
    return DateTime.tryParse(input) == null
        ? 'Not yet saved'
        : formatManilaTimestamp(input);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _busy ? null : onTap,
  );
  Future<void> _push(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  void _disposeAfter(List<TextEditingController> controllers) {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }
}

class _ReportsPage extends StatefulWidget {
  final AppData data;
  final String period;
  const _ReportsPage({required this.data, required this.period});
  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> {
  String _range = 'month';
  late String _period = widget.period;
  late int _year = int.parse(widget.period.substring(0, 4));
  int? _room, _tenant;
  bool _busy = false;
  ReportData get _report => DocumentService.select(
    widget.data,
    period: _range == 'month' ? _period : null,
    year: _range == 'year' ? _year : null,
    roomId: _room,
    tenantId: _tenant,
  );
  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & exports')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'See the full picture',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Charges follow the bill’s month. Collections follow the date money was received.',
            style: TextStyle(color: muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _range,
            decoration: const InputDecoration(labelText: 'Report period'),
            items: const [
              DropdownMenuItem(value: 'month', child: Text('Monthly')),
              DropdownMenuItem(value: 'year', child: Text('Yearly')),
              DropdownMenuItem(value: 'all', child: Text('All records')),
            ],
            onChanged: (v) => setState(() => _range = v!),
          ),
          const SizedBox(height: 16),
          if (_range != 'all')
            SectionCard(
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous ${_range == 'month' ? 'month' : 'year'}',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shift(-1),
                  ),
                  Expanded(
                    child: Text(
                      _range == 'month' ? monthLabel(_period) : '$_year',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next ${_range == 'month' ? 'month' : 'year'}',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shift(1),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _room,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Room'),
            items: [
              const DropdownMenuItem<int>(
                value: null,
                child: Text('All rooms'),
              ),
              ...widget.data.rooms.map(
                (r) => DropdownMenuItem<int>(
                  value: r['id'],
                  child: Text(r['name'], overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _room = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _tenant,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tenant'),
            items: [
              const DropdownMenuItem<int>(
                value: null,
                child: Text('All tenants'),
              ),
              ...widget.data.tenants.map(
                (t) => DropdownMenuItem<int>(
                  value: t['id'],
                  child: Text(t['name'], overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _tenant = v),
          ),
          const SizedBox(height: 24),
          SectionCard(
            child: Column(
              children: [
                DetailRow(
                  'Rent billed',
                  money(report.billedByKind['rent'] ?? 0),
                ),
                DetailRow(
                  'Electricity billed',
                  money(report.billedByKind['electricity'] ?? 0),
                ),
                DetailRow(
                  'Water billed',
                  money(report.billedByKind['water'] ?? 0),
                ),
                DetailRow(
                  'Adjustments / discounts',
                  money(report.billedByKind['adjustment'] ?? 0),
                ),
                const Divider(),
                DetailRow('Total charges', money(report.billed), strong: true),
                DetailRow(
                  'Payments received',
                  money(report.collected),
                  strong: true,
                ),
                DetailRow(
                  'Balance of selected bills now',
                  money(report.outstanding),
                ),
                DetailRow('Finalized bills', '${report.invoices.length}'),
                DetailRow(
                  'Tenancies during period',
                  '${report.tenancies.length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Security deposits are tracked separately. Balances reflect the latest payments and reversals, including later months.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _export(pdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('View PDF report'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _export(pdf: false),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Save CSV report'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _shift(int delta) => setState(() {
    if (_range == 'month') {
      final date = DateTime.parse('$_period-01');
      final changed = DateTime(date.year, date.month + delta);
      if (changed.year >= 2000 && changed.year <= 2100) {
        _period = billingPeriod(changed);
      }
    } else if (_year + delta >= 2000 && _year + delta <= 2100) {
      _year += delta;
    }
  });
  Future<void> _export({required bool pdf}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (pdf) {
        await DocumentService.report(
          widget.data,
          period: _range == 'month' ? _period : null,
          year: _range == 'year' ? _year : null,
          roomId: _room,
          tenantId: _tenant,
        );
      } else {
        await DocumentService.exportCsv(
          widget.data,
          period: _range == 'month' ? _period : null,
          year: _range == 'year' ? _year : null,
          roomId: _room,
          tenantId: _tenant,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _HistoryPage extends StatefulWidget {
  final AppData data;
  const _HistoryPage({required this.data});
  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  String _search = '';
  bool _bills = true;
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final bills =
        data.invoices
            .where(
              (b) =>
                  '${b['reference']} ${b['period']} ${data.room(b['room_id'])?['name']} ${data.tenantName(b['tenancy_id'])}'
                      .toLowerCase()
                      .contains(_search),
            )
            .toList()
          ..sort(
            (a, b) => (b['period'] as String).compareTo(a['period'] as String),
          );
    final payments =
        data.payments
            .where(
              (p) =>
                  '${p['date']} ${p['method']} ${p['reference']} ${p['notes']} RCP-${p['id'].toString().padLeft(6, '0')} ${_paymentTenant(data, p['id'])}'
                      .toLowerCase()
                      .contains(_search),
            )
            .toList()
          ..sort(
            (a, b) => (b['date'] as String).compareTo(a['date'] as String),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Bills & payment history')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search name, room, month, or reference',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase().trim()),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Bills'),
                selected: _bills,
                onSelected: (_) => setState(() => _bills = true),
              ),
              ChoiceChip(
                label: const Text('Payments'),
                selected: !_bills,
                onSelected: (_) => setState(() => _bills = false),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_bills && bills.isEmpty || !_bills && payments.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No matching records',
              description: 'Saved bills and payments will appear here.',
            ),
          if (_bills)
            ...bills.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data.room(b['room_id'])?['name']} · ${b['period']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(data.tenantName(b['tenancy_id'])),
                      const SizedBox(height: 10),
                      StatusPill(invoiceStatus(data, b)),
                      DetailRow('Reference', b['reference']),
                      DetailRow('Charges', money(b['total_cents'])),
                      DetailRow('Balance', money(data.balance(b['id']))),
                      OutlinedButton.icon(
                        onPressed: () => perform(
                          context,
                          () => DocumentService.statement(data, b['id']),
                        ),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('View statement'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_bills)
            ...payments.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RCP-${p['id'].toString().padLeft(6, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(_paymentTenant(data, p['id'])),
                      DetailRow(
                        '${dateLabel(p['date'])} · ${p['method']}',
                        money(p['amount_cents']),
                        strong: true,
                      ),
                      if (p['reversed_at'] != null)
                        Text(
                          'Reversed · ${p['reversal_reason']}',
                          style: const TextStyle(color: danger),
                        ),
                      if ((p['reference'] as String).isNotEmpty)
                        Text('Reference: ${p['reference']}'),
                      if ((p['notes'] as String).isNotEmpty) Text(p['notes']),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => perform(
                          context,
                          () => DocumentService.receipt(data, p['id']),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('View receipt'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _paymentTenant(AppData data, int paymentId) {
    final allocation = data.allocations
        .where((a) => a['payment_id'] == paymentId)
        .firstOrNull;
    final invoice = allocation == null
        ? null
        : data.invoice(allocation['invoice_id']);
    return invoice == null
        ? ''
        : '${data.room(invoice['room_id'])?['name']} · ${data.tenantName(invoice['tenancy_id'])}';
  }
}

class _TenancyHistoryPage extends StatelessWidget {
  final AppData data;
  const _TenancyHistoryPage({required this.data});
  @override
  Widget build(BuildContext context) {
    final records = [...data.tenancies]
      ..sort(
        (a, b) => (b['move_in'] as String).compareTo(a['move_in'] as String),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Tenancy & deposits')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (records.isEmpty)
            const EmptyState(
              icon: Icons.people_outline,
              title: 'No tenancy records yet',
              description:
                  'Assign a tenant to a room to start a rental history.',
            ),
          ...records.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.tenantName(t['id']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${data.room(t['room_id'])?['name']} · ${t['move_out'] == null ? 'Current tenant' : 'Moved out'}',
                    ),
                    DetailRow('Move-in', dateLabel(t['move_in'])),
                    DetailRow(
                      'Move-out',
                      t['move_out'] == null
                          ? 'Still occupying'
                          : dateLabel(t['move_out']),
                    ),
                    DetailRow('Agreed monthly rent', money(t['rent_cents'])),
                    DetailRow(
                      'Deposit still held',
                      money(data.depositBalance(t['id'])),
                      strong: true,
                    ),
                    const Divider(),
                    ...data.deposits
                        .where((d) => d['tenancy_id'] == t['id'])
                        .map(
                          (d) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DetailRow(
                                  '${d['kind']} · ${dateLabel(d['date'])}',
                                  money(d['amount_cents']),
                                ),
                                if ((d['notes'] as String).isNotEmpty)
                                  Text(
                                    d['notes'],
                                    style: const TextStyle(color: muted),
                                  ),
                              ],
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
    );
  }
}

class _AuditPage extends StatelessWidget {
  final AppData data;
  const _AuditPage({required this.data});
  @override
  Widget build(BuildContext context) {
    final audit = [...data.audit]
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return Scaffold(
      appBar: AppBar(title: const Text('Activity & corrections')),
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: audit.isEmpty ? 1 : audit.length,
        itemBuilder: (context, index) {
          if (audit.isEmpty) {
            return const EmptyState(
              icon: Icons.fact_check_outlined,
              title: 'A clear record of changes',
              description:
                  'Saved changes and financial corrections will appear here.',
            );
          }
          final event = audit[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (event['action'] as String).replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${event['entity']} #${event['entity_id']} · ${formatManilaTimestamp(event['created_at'])}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(event['detail'].toString()),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
