import 'dart:convert';

import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/models.dart';
import 'backup.dart';
import 'local_time.dart';

String peso(int cents) {
  final value = cents.abs();
  final whole = (value ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${cents < 0 ? '-' : ''}₱$whole.${(value % 100).toString().padLeft(2, '0')}';
}

String _decimal(int cents) =>
    '${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2, '0')}';
String _units(int value) =>
    '${value ~/ 1000}.${(value % 1000).toString().padLeft(3, '0')}';

class ReportData {
  final List<Row> invoices, payments, deposits, tenancies;
  final Map<String, int> billedByKind;
  final int billed, collected, outstanding;
  const ReportData({
    required this.invoices,
    required this.payments,
    required this.deposits,
    required this.tenancies,
    required this.billedByKind,
    required this.billed,
    required this.collected,
    required this.outstanding,
  });
}

class DocumentService {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static Future<pw.ThemeData>? _fonts;

  static Future<pw.ThemeData> _theme() => _fonts ??= () async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }();

  static Future<void> statement(AppData data, int invoiceId) async {
    final bill = data.invoice(invoiceId);
    if (bill == null) {
      throw const FormatException('This bill could not be found.');
    }
    await _preview(
      await statementBytes(data, invoiceId),
      '${bill['reference']}.pdf',
      'Billing statement',
    );
  }

  static Future<void> receipt(AppData data, int paymentId) async {
    await _preview(
      await receiptBytes(data, paymentId),
      'RCP-${paymentId.toString().padLeft(6, '0')}.pdf',
      'Payment receipt',
    );
  }

  static Future<void> report(
    AppData data, {
    String? period,
    int? year,
    int? roomId,
    int? tenantId,
  }) async {
    final selected = select(
      data,
      period: period,
      year: year,
      roomId: roomId,
      tenantId: tenantId,
    );
    final pdf = pw.Document(theme: await _theme(), title: 'Rental report');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.all(36),
        footer: _footer,
        build: (_) => [
          ..._header(
            data,
            'Rental report',
            period ?? (year?.toString() ?? 'All records'),
          ),
          if (roomId != null) pw.Text('Room: ${data.room(roomId)?['name']}'),
          if (tenantId != null)
            pw.Text('Tenant: ${data.tenant(tenantId)?['name']}'),
          pw.SizedBox(height: 20),
          ..._totals([
            ['Rent billed', peso(selected.billedByKind['rent'] ?? 0)],
            [
              'Electricity billed',
              peso(selected.billedByKind['electricity'] ?? 0),
            ],
            ['Water billed', peso(selected.billedByKind['water'] ?? 0)],
            [
              'Adjustments / discounts',
              peso(selected.billedByKind['adjustment'] ?? 0),
            ],
            ['Total charges in selected period', peso(selected.billed)],
            ['Payments received in selected period', peso(selected.collected)],
            ['Current balance of selected bills', peso(selected.outstanding)],
          ]),
          pw.SizedBox(height: 12),
          pw.Text(
            'Payments are filtered by the date received, independently of the bill’s month. '
            'Balances reflect payments and reversals saved as of this report. '
            'Draft bills and security deposits are excluded from rent collection.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          _heading('Finalized bills'),
          _table(
            [
              'Reference / month',
              'Room / tenant',
              'Charges',
              'Paid',
              'Balance',
            ],
            selected.invoices
                .map(
                  (b) => [
                    '${b['reference']}\n${b['period']}',
                    '${data.room(b['room_id'])?['name']}\n${data.tenantName(b['tenancy_id'])}',
                    peso(b['total_cents']),
                    peso(data.paid(b['id'])),
                    peso(data.balance(b['id'])),
                  ],
                )
                .toList(),
          ),
          _heading('Payments received'),
          _table(
            ['Date / receipt', 'Room / bill month', 'Method', 'Amount'],
            selected.payments.map((p) {
              final b = data.invoice(p['invoice_id']);
              return [
                '${p['date']}\nRCP-${p['id'].toString().padLeft(6, '0')}',
                '${data.room(b?['room_id'] ?? -1)?['name'] ?? ''}\n${b?['period'] ?? ''}',
                p['method'].toString(),
                peso(p['amount_cents']),
              ];
            }).toList(),
          ),
          _heading('Security deposit movements'),
          _table(
            ['Date', 'Room / tenant', 'Type', 'Amount'],
            selected.deposits.map((d) {
              final t = data.tenancy(d['tenancy_id']);
              return [
                d['date'].toString(),
                '${data.room(t?['room_id'] ?? -1)?['name']}\n${data.tenantName(d['tenancy_id'])}',
                d['kind'].toString(),
                peso(d['amount_cents']),
              ];
            }).toList(),
          ),
          _heading('Occupancy during selected period'),
          _table(
            ['Room', 'Tenant', 'Move-in', 'Move-out'],
            selected.tenancies
                .map(
                  (t) => [
                    data.room(t['room_id'])?['name'].toString() ?? '',
                    data.tenantName(t['id']),
                    t['move_in'].toString(),
                    t['move_out']?.toString() ?? 'Still occupying',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    await _preview(
      await pdf.save(),
      'Rental-report-${period ?? year ?? 'all'}.pdf',
      'Rental report',
    );
  }

  static ReportData select(
    AppData data, {
    String? period,
    int? year,
    int? roomId,
    int? tenantId,
  }) {
    bool dateMatches(String date) => period != null
        ? date.startsWith(period)
        : year != null
        ? date.startsWith('$year-')
        : true;
    bool tenancyMatches(int id) {
      final t = data.tenancy(id);
      return t != null &&
          (roomId == null || t['room_id'] == roomId) &&
          (tenantId == null || t['tenant_id'] == tenantId);
    }

    final invoices =
        data.invoices
            .where(
              (b) =>
                  b['status'] == 'final' &&
                  dateMatches(b['period']) &&
                  tenancyMatches(b['tenancy_id']),
            )
            .toList()
          ..sort(
            (a, b) => (a['period'] as String).compareTo(b['period'] as String),
          );
    // Each report payment row represents an allocation. This keeps exports and
    // room/tenant filters correct for restored multi-invoice transactions too.
    final payments = <Row>[];
    for (final payment in data.payments) {
      if (payment['reversed_at'] != null || !dateMatches(payment['date'])) {
        continue;
      }
      for (final allocation in data.allocations.where(
        (a) => a['payment_id'] == payment['id'],
      )) {
        final bill = data.invoice(allocation['invoice_id']);
        if (bill != null && tenancyMatches(bill['tenancy_id'])) {
          payments.add({
            ...payment,
            'transaction_amount_cents': payment['amount_cents'],
            'amount_cents': allocation['amount_cents'],
            'invoice_id': allocation['invoice_id'],
          });
        }
      }
    }
    payments.sort(
      (a, b) => (a['date'] as String).compareTo(b['date'] as String),
    );
    final deposits = data.deposits
        .where((d) => dateMatches(d['date']) && tenancyMatches(d['tenancy_id']))
        .toList();
    final ids = invoices.map((b) => b['id']).toSet();
    final kinds = <String, int>{};
    for (final line in data.lines.where((l) => ids.contains(l['invoice_id']))) {
      final kind = line['kind'] as String;
      kinds[kind] = (kinds[kind] ?? 0) + (line['amount_cents'] as int);
    }
    String? start, end;
    if (period != null) {
      start = '$period-01';
      final d = DateTime.parse(start);
      end = isoDate(DateTime(d.year, d.month + 1, 1));
    } else if (year != null) {
      start = '$year-01-01';
      end = '${year + 1}-01-01';
    }
    final tenancies = data.tenancies
        .where(
          (t) =>
              tenancyMatches(t['id']) &&
              (end == null || (t['move_in'] as String).compareTo(end) < 0) &&
              (start == null ||
                  t['move_out'] == null ||
                  (t['move_out'] as String).compareTo(start) > 0),
        )
        .toList();
    final collected = payments.fold<int>(
      0,
      (sum, p) => sum + (p['amount_cents'] as int),
    );
    return ReportData(
      invoices: invoices,
      payments: payments,
      deposits: deposits,
      tenancies: tenancies,
      billedByKind: kinds,
      billed: invoices.fold<int>(
        0,
        (sum, b) => sum + (b['total_cents'] as int),
      ),
      collected: collected,
      outstanding: invoices.fold<int>(
        0,
        (sum, b) => sum + data.balance(b['id']),
      ),
    );
  }

  static Future<void> exportCsv(
    AppData data, {
    String? period,
    int? year,
    int? roomId,
    int? tenantId,
  }) async {
    final content = csv(
      data,
      period: period,
      year: year,
      roomId: roomId,
      tenantId: tenantId,
    );
    await BackupService.saveBytes(
      Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(content)]),
      'Rental-report-${period ?? year ?? 'all'}.csv',
      title: 'Save rental report',
      extensions: ['csv'],
    );
  }

  @visibleForTesting
  static String csv(
    AppData data, {
    String? period,
    int? year,
    int? roomId,
    int? tenantId,
  }) {
    final selected = select(
      data,
      period: period,
      year: year,
      roomId: roomId,
      tenantId: tenantId,
    );
    final rows = <List<String>>[
      [
        'Record type',
        'Reference',
        'Bill month',
        'Date',
        'Room',
        'Tenant',
        'Kind',
        'Rent PHP',
        'Electricity PHP',
        'Water PHP',
        'Adjustment PHP',
        'Charges PHP',
        'Paid to bill PHP',
        'Current balance PHP',
        'Cash received PHP',
        'Deposit amount PHP',
        'Method',
        'Notes',
      ],
    ];
    for (final b in selected.invoices) {
      int amount(String kind) => data.lines
          .where((l) => l['invoice_id'] == b['id'] && l['kind'] == kind)
          .fold<int>(0, (s, l) => s + (l['amount_cents'] as int));
      rows.add([
        'Bill',
        b['reference'].toString(),
        b['period'].toString(),
        b['due_date'].toString(),
        data.room(b['room_id'])?['name'].toString() ?? '',
        data.tenantName(b['tenancy_id']),
        'final',
        _decimal(amount('rent')),
        _decimal(amount('electricity')),
        _decimal(amount('water')),
        _decimal(amount('adjustment')),
        _decimal(b['total_cents']),
        _decimal(data.paid(b['id'])),
        _decimal(data.balance(b['id'])),
        '',
        '',
        '',
        '',
      ]);
    }
    for (final p in selected.payments) {
      final b = data.invoice(p['invoice_id']);
      rows.add([
        'Payment',
        'RCP-${p['id'].toString().padLeft(6, '0')}',
        b?['period'].toString() ?? '',
        p['date'].toString(),
        data.room(b?['room_id'] ?? -1)?['name'].toString() ?? '',
        b == null ? '' : data.tenantName(b['tenancy_id']),
        'received',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        _decimal(p['amount_cents']),
        '',
        p['method'].toString(),
        '${p['reference'] ?? ''} ${p['notes'] ?? ''}'.trim(),
      ]);
    }
    for (final d in selected.deposits) {
      final t = data.tenancy(d['tenancy_id']);
      rows.add([
        'Deposit',
        'DEP-${d['id']}',
        '',
        d['date'].toString(),
        data.room(t?['room_id'] ?? -1)?['name'].toString() ?? '',
        data.tenantName(d['tenancy_id']),
        d['kind'].toString(),
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        _decimal(d['amount_cents']),
        '',
        d['notes'].toString(),
      ]);
    }
    for (final t in selected.tenancies) {
      rows.add([
        'Occupancy',
        'TEN-${t['id']}',
        '',
        t['move_in'].toString(),
        data.room(t['room_id'])?['name'].toString() ?? '',
        data.tenantName(t['id']),
        t['move_out'] == null ? 'active' : 'moved out',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        'Move-out: ${t['move_out'] ?? 'Still occupying'}',
      ]);
    }
    return rows.map((row) => row.map(_csvField).join(',')).join('\r\n');
  }

  static String _csvField(String value) {
    // Neutralize formulas in user-controlled room names, names and notes.
    if (RegExp(r'^[\s]*[=+@\-\t\r]').hasMatch(value)) value = "'$value";
    return '"${value.replaceAll('"', '""')}"';
  }

  @visibleForTesting
  static Future<Uint8List> statementBytes(AppData data, int invoiceId) async {
    final bill = data.invoice(invoiceId);
    if (bill == null) throw const FormatException('Bill not found.');
    final pdf = pw.Document(
      theme: await _theme(),
      title: 'Billing statement ${bill['reference']}',
    );
    final invoiceLines = data.lines
        .where((l) => l['invoice_id'] == invoiceId)
        .toList();
    final previous = data.invoices
        .where(
          (b) =>
              b['tenancy_id'] == bill['tenancy_id'] &&
              b['status'] == 'final' &&
              (b['period'] as String).compareTo(bill['period']) < 0 &&
              data.balance(b['id']) > 0,
        )
        .toList();
    final previousBalance = previous.fold<int>(
      0,
      (sum, b) => sum + data.balance(b['id']),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: _footer,
        build: (_) => [
          ..._header(
            data,
            bill['status'] == 'draft'
                ? 'DRAFT • Billing statement'
                : 'Billing statement',
            bill['reference'],
          ),
          ..._billIdentity(data, bill),
          _heading('This month’s charges'),
          _table(
            ['Description', 'Quantity', 'Rate', 'Amount'],
            invoiceLines
                .map(
                  (l) => [
                    l['description'].toString(),
                    _units(l['quantity']),
                    peso(l['rate_cents']),
                    peso(l['amount_cents']),
                  ],
                )
                .toList(),
          ),
          ..._totals([
            ['New charges for ${bill['period']}', peso(bill['total_cents'])],
            ['Payments allocated to this bill', peso(data.paid(invoiceId))],
            ['Remaining on this bill', peso(data.balance(invoiceId))],
            ['Older unpaid bills (shown separately)', peso(previousBalance)],
            [
              'Outstanding through this billing period',
              peso(data.balance(invoiceId) + previousBalance),
            ],
          ]),
          if (previous.isNotEmpty) ...[
            _heading('Previous balances'),
            _table(
              ['Bill reference', 'Month', 'Remaining balance'],
              previous
                  .map(
                    (b) => [
                      b['reference'].toString(),
                      b['period'].toString(),
                      peso(data.balance(b['id'])),
                    ],
                  )
                  .toList(),
            ),
            pw.Text(
              'Previous balances remain on their original bills and are not added to this month’s new charges.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          _heading('Meter readings'),
          _table(
            ['Utility', 'Previous', 'Current', 'Consumption'],
            data.readings
                .where((r) => r['invoice_id'] == invoiceId)
                .map(
                  (r) => [
                    r['kind'].toString(),
                    _units(r['previous_value']),
                    _units(r['current_value']),
                    _units(
                      (r['current_value'] as int) -
                          (r['previous_value'] as int),
                    ),
                  ],
                )
                .toList(),
          ),
          _heading('Payments on this bill'),
          _table(
            ['Date', 'Receipt', 'Method', 'Amount'],
            data.allocations.where((a) => a['invoice_id'] == invoiceId).map((
              a,
            ) {
              final p = data.payments.firstWhere(
                (p) => p['id'] == a['payment_id'],
              );
              return [
                p['date'].toString(),
                'RCP-${p['id'].toString().padLeft(6, '0')}${p['reversed_at'] != null ? ' (reversed)' : ''}',
                p['method'].toString(),
                peso(a['amount_cents']),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Prepared by ${data.settings['owner_name']?.isNotEmpty == true ? data.settings['owner_name'] : data.settings['property_name']}. '
            'Amounts and balances as of ${isoDate(manilaNow())} (Asia/Manila).',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  @visibleForTesting
  static Future<Uint8List> receiptBytes(AppData data, int paymentId) async {
    final payment = data.payments
        .where((p) => p['id'] == paymentId)
        .firstOrNull;
    if (payment == null) throw const FormatException('Payment not found.');
    final pdf = pw.Document(theme: await _theme(), title: 'Payment receipt');
    final reference = 'RCP-${paymentId.toString().padLeft(6, '0')}';
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: _footer,
        build: (_) => [
          ..._header(
            data,
            payment['reversed_at'] == null
                ? 'Payment receipt'
                : 'REVERSED • Payment receipt',
            reference,
          ),
          ..._totals([
            ['Payment date', payment['date'].toString()],
            ['Amount received', peso(payment['amount_cents'])],
            ['Payment method', payment['method'].toString()],
            [
              'Reference number',
              (payment['reference'] as String).isEmpty
                  ? '—'
                  : payment['reference'],
            ],
          ]),
          if (payment['reversed_at'] != null) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'Reversed: ${formatManilaTimestamp(payment['reversed_at'])}\nReason: ${payment['reversal_reason']}\n'
              'This reversed transaction does not reduce the outstanding balance.',
            ),
          ],
          for (final allocation in data.allocations.where(
            (a) => a['payment_id'] == paymentId,
          )) ...[
            _heading(
              'Applied to bill ${data.invoice(allocation['invoice_id'])?['reference']}',
            ),
            ..._billIdentity(data, data.invoice(allocation['invoice_id'])!),
            _table(
              ['Charge', 'Amount'],
              data.lines
                  .where((l) => l['invoice_id'] == allocation['invoice_id'])
                  .map(
                    (l) => [
                      l['description'].toString(),
                      peso(l['amount_cents']),
                    ],
                  )
                  .toList(),
            ),
            ..._totals([
              ['This payment allocation', peso(allocation['amount_cents'])],
              [
                'Bill total',
                peso(data.invoice(allocation['invoice_id'])!['total_cents']),
              ],
              [
                'Total paid to this bill',
                peso(data.paid(allocation['invoice_id'])),
              ],
              [
                'Bill balance now',
                peso(data.balance(allocation['invoice_id'])),
              ],
            ]),
          ],
          if ((payment['notes'] as String).isNotEmpty) ...[
            _heading('Notes'),
            pw.Text(payment['notes']),
          ],
          pw.SizedBox(height: 24),
          pw.Text(
            'Recorded by ${data.settings['owner_name']?.isNotEmpty == true ? data.settings['owner_name'] : data.settings['property_name']}. '
            'Balances as of ${isoDate(manilaNow())} (Asia/Manila).',
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static List<pw.Widget> _header(
    AppData data,
    String title,
    String reference,
  ) => [
    pw.Text(
      data.settings['property_name'] ?? 'My rental property',
      style: pw.TextStyle(
        fontSize: 22,
        fontWeight: pw.FontWeight.bold,
        color: const PdfColor.fromInt(0xff194d42),
      ),
    ),
    if (data.settings['property_address']?.isNotEmpty == true)
      pw.Text(data.settings['property_address']!),
    pw.SizedBox(height: 18),
    pw.Text(
      title,
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.Text(reference, style: const pw.TextStyle(fontSize: 10)),
    pw.Divider(color: const PdfColor.fromInt(0xffcccccc)),
  ];
  static List<pw.Widget> _billIdentity(AppData data, Row bill) => [
    pw.Text('Tenant: ${data.tenantName(bill['tenancy_id'])}'),
    pw.Text('Room: ${data.room(bill['room_id'])?['name']}'),
    pw.Text(
      'Billing month: ${bill['period']}     Due date: ${bill['due_date']}',
    ),
    pw.SizedBox(height: 12),
  ];
  static pw.Widget _heading(String label) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 20, bottom: 8),
    child: pw.Text(
      label,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );
  static pw.Widget _table(List<String> headers, List<List<String>> rows) =>
      rows.isEmpty
      ? pw.Text('No records.', style: const pw.TextStyle(fontSize: 9))
      : pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xffe9f0eb),
          ),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(7),
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColor.fromInt(0xffeeeeee),
            ),
          ),
        );
  static List<pw.Widget> _totals(List<List<String>> rows) => rows
      .map(
        (r) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(r[0], style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.Text(
                r[1],
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      )
      .toList();
  static pw.Widget _footer(pw.Context context) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Bahay Rent · Created offline · ${isoDate(manilaNow())}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
      pw.Text(
        '${context.pageNumber} / ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8),
      ),
    ],
  );

  static Future<void> _preview(
    Uint8List bytes,
    String fileName,
    String title,
  ) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      // Retains offline print/save support when called before a preview host exists.
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
      return;
    }
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'Save PDF to device',
                icon: const Icon(Icons.save_alt_rounded),
                onPressed: () async {
                  try {
                    final saved = await BackupService.saveBytes(
                      bytes,
                      fileName,
                      extensions: ['pdf'],
                    );
                    if (context.mounted && saved) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PDF saved.')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not save PDF. Please choose another location.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          body: PdfPreview(
            build: (_) async => bytes,
            pdfFileName: fileName,
            canDebug: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            onError: (_, error) => const Center(
              child: Text(
                'Could not display the PDF. Use Save PDF to open it in another app.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
