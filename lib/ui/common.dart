import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;

const ink = Color(0xFF163D35);
const sage = Color(0xFFDAE8D9);
const warm = Color(0xFFF6F5F0);
const muted = Color(0xFF64736B);
const amber = Color(0xFF9B641A);
const danger = Color(0xFFB74437);

String money(int cents) => NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
).format(cents / 100);
String decimalOf(int value, [int places = 2]) {
  final negative = value < 0 ? '-' : '';
  final digits = value.abs().toString().padLeft(places + 1, '0');
  return '$negative${digits.substring(0, digits.length - places)}.${digits.substring(digits.length - places)}';
}

String monthLabel(String period) =>
    DateFormat('MMMM yyyy').format(DateTime.parse('$period-01'));
String dateLabel(String value) =>
    DateFormat('d MMM yyyy').format(DateTime.parse(value));
String friendlyError(Object error) => error.toString().replaceFirst(
  RegExp(r'^(Exception|FormatException|StateError|Bad state):\s*'),
  '',
);
String requiredText(TextEditingController field, String label) {
  final value = field.text.trim();
  if (value.isEmpty) throw FormatException('Please enter $label.');
  return value;
}

String invoiceStatus(AppData data, model.Row invoice) {
  if (invoice['status'] == 'draft') return 'Draft';
  final remaining = data.balance(invoice['id']);
  if (remaining <= 0) return 'Paid';
  final overdue =
      (invoice['due_date'] as String).compareTo(isoDate(manilaNow())) < 0;
  if (overdue) {
    return data.paid(invoice['id']) > 0 ? 'Partial · overdue' : 'Overdue';
  }
  return data.paid(invoice['id']) > 0 ? 'Partial' : 'Unpaid';
}

class PageHeader extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget? action;
  const PageHeader({
    super.key,
    this.eyebrow = '',
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              eyebrow.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: muted,
              ),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String text;
  const StatusPill(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final bad = text.toLowerCase().contains('overdue');
    final good = ['Paid', 'Occupied', 'Finalized'].contains(text);
    final color = bad
        ? danger
        : good
        ? ink
        : amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).brightness == Brightness.dark && good
              ? const Color(0xFFAAD4B5)
              : color,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: sage.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: ink),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(color: muted, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  final String label, value;
  final bool strong;
  const DetailRow(this.label, this.value, {super.key, this.strong = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: strong ? null : muted,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget input(
  TextEditingController controller,
  String label, {
  String? helper,
  String? prefix,
  TextInputType? keyboard,
  int lines = 1,
  bool required = false,
  ValueChanged<String>? onChanged,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    onChanged: onChanged,
    maxLines: lines,
    keyboardType:
        keyboard ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
    textCapitalization: keyboard == null
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      prefixText: prefix,
    ),
    validator: required
        ? (value) => value == null || value.trim().isEmpty
              ? 'Please enter $label.'
              : null
        : null,
  ),
);

class DateInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const DateInput({super.key, required this.controller, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      onTap: () async {
        final parsed = DateTime.tryParse(controller.text) ?? manilaNow();
        final selected = await showDatePicker(
          context: context,
          initialDate: parsed,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (selected != null) controller.text = isoDate(selected);
      },
    ),
  );
}

Future<bool> showEditor(
  BuildContext context, {
  required String title,
  String? description,
  required Widget Function(BuildContext, StateSetter) fields,
  required Future<void> Function() onSave,
  String saveLabel = 'Save',
  bool destructive = false,
}) async {
  final form = GlobalKey<FormState>();
  var busy = false;
  String? error;
  TransitionRoute<bool>? sheetRoute;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    enableDrag: false,
    isDismissible: false,
    builder: (sheetContext) {
      sheetRoute = ModalRoute.of<bool>(sheetContext) as TransitionRoute<bool>?;
      return StatefulBuilder(
        builder: (sheetContext, setState) => PopScope(
          canPop: !busy,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(sheetContext)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      if (description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: Text(
                            description,
                            style: const TextStyle(color: muted, height: 1.5),
                          ),
                        ),
                      const SizedBox(height: 20),
                      fields(sheetContext, setState),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: danger),
                          ),
                        ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (busy || !form.currentState!.validate()) {
                                  return;
                                }
                                setState(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  await onSave();
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext, true);
                                  }
                                } catch (e) {
                                  if (sheetContext.mounted) {
                                    setState(() {
                                      error = friendlyError(e);
                                      busy = false;
                                    });
                                  }
                                }
                              },
                        style: destructive
                            ? FilledButton.styleFrom(backgroundColor: danger)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(saveLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  // Field controllers belong to callers. Keep them alive until the closing
  // animation has removed the route and its text fields from the overlay.
  await sheetRoute?.completed;
  return result ?? false;
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: danger)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

Future<void> perform(
  BuildContext context,
  Future<void> Function() action, {
  VoidCallback? onChanged,
  String? success,
}) async {
  try {
    await action();
    onChanged?.call();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: danger),
      );
    }
  }
}

Future<void> showDetails(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(sheetContext),
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  ),
);
