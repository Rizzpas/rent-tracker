import 'package:flutter/material.dart';
import '../data/models.dart' hide Row;
import '../data/models.dart' as model show Row;
import '../services/documents.dart' show peso;
import '../services/local_time.dart';

export 'date_picker.dart';

const ink = Color(0xFF14453B);
const inkDeep = Color(0xFF0C2E27);
const gold = Color(0xFFF5B841);
const sage = Color(0xFFDCEBE0);
const warm = Color(0xFFF5F6F2);
const muted = Color(0xFF5C6D64);
const amber = Color(0xFF9E6314);
const danger = Color(0xFFB83E31);

/// Exact, allocation-light Philippine Peso formatter for integer centavos.
String money(int cents) => peso(cents);

String decimalOf(int value, [int places = 2]) {
  final negative = value < 0 ? '-' : '';
  final digits = value.abs().toString().padLeft(places + 1, '0');
  return '$negative${digits.substring(0, digits.length - places)}.${digits.substring(digits.length - places)}';
}

String monthLabel(String period) => formatPeriodLabel(period);
String dateLabel(String value) => formatIsoDateLabel(value);

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
  final id = invoice['id'] as int;
  final remaining = data.balance(id);
  if (remaining <= 0) return 'Paid';
  final paidAmount = data.paid(id);
  final overdue = (invoice['due_date'] as String).compareTo(manilaToday()) < 0;
  if (overdue) {
    return paidAmount > 0 ? 'Partial · overdue' : 'Overdue';
  }
  return paidAmount > 0 ? 'Partial' : 'Unpaid';
}

/// Crisp vector brand mark for Upa Renta: Tropical Roof + 'U' Home Arch + Gold Sun/Coin.
/// Uses lightweight direct canvas drawing (zero bitmap decode, zero GPU blur).
class UpaRentaLogo extends StatelessWidget {
  final double size;
  const UpaRentaLogo({super.key, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.30);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F6E5C), Color(0xFF144A3E), Color(0xFF0C2E26)],
        ),
        borderRadius: radius,
      ),
      child: CustomPaint(
        size: Size.square(size),
        painter: const _UpaLogoPainter(),
      ),
    );
  }
}

class _UpaLogoPainter extends CustomPainter {
  const _UpaLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108.0;
    final ivory = Paint()
      ..color = const Color(0xFFFFFDF7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Roof chevron
    final roof = Path()
      ..moveTo(51.2 * s, 23.2 * s)
      ..lineTo(23.5 * s, 46.8 * s)
      ..cubicTo(21.7 * s, 48.3 * s, 21.8 * s, 51.0 * s, 23.7 * s, 52.5 * s)
      ..lineTo(25.8 * s, 54.1 * s)
      ..cubicTo(27.6 * s, 55.4 * s, 30.1 * s, 55.2 * s, 31.8 * s, 53.7 * s)
      ..lineTo(54.0 * s, 34.6 * s)
      ..lineTo(76.2 * s, 53.7 * s)
      ..cubicTo(77.9 * s, 55.2 * s, 80.4 * s, 55.4 * s, 82.2 * s, 54.1 * s)
      ..lineTo(84.3 * s, 52.5 * s)
      ..cubicTo(86.2 * s, 51.0 * s, 86.3 * s, 48.3 * s, 84.5 * s, 46.8 * s)
      ..lineTo(56.8 * s, 23.2 * s)
      ..cubicTo(55.2 * s, 21.8 * s, 52.8 * s, 21.8 * s, 51.2 * s, 23.2 * s)
      ..close();
    canvas.drawPath(roof, ivory);

    // 'U' house body
    final body = Path()
      ..moveTo(32.0 * s, 51.0 * s)
      ..cubicTo(32.0 * s, 49.0 * s, 33.6 * s, 47.5 * s, 35.5 * s, 47.5 * s)
      ..lineTo(39.5 * s, 47.5 * s)
      ..cubicTo(41.4 * s, 47.5 * s, 43.0 * s, 49.0 * s, 43.0 * s, 51.0 * s)
      ..lineTo(43.0 * s, 62.5 * s)
      ..cubicTo(43.0 * s, 68.58 * s, 47.92 * s, 73.5 * s, 54.0 * s, 73.5 * s)
      ..cubicTo(60.08 * s, 73.5 * s, 65.0 * s, 68.58 * s, 65.0 * s, 62.5 * s)
      ..lineTo(65.0 * s, 51.0 * s)
      ..cubicTo(65.0 * s, 49.0 * s, 66.6 * s, 47.5 * s, 68.5 * s, 47.5 * s)
      ..lineTo(72.5 * s, 47.5 * s)
      ..cubicTo(74.4 * s, 47.5 * s, 76.0 * s, 49.0 * s, 76.0 * s, 51.0 * s)
      ..lineTo(76.0 * s, 62.5 * s)
      ..cubicTo(76.0 * s, 74.65 * s, 66.15 * s, 84.5 * s, 54.0 * s, 84.5 * s)
      ..cubicTo(41.85 * s, 84.5 * s, 32.0 * s, 74.65 * s, 32.0 * s, 62.5 * s)
      ..close();
    canvas.drawPath(body, ivory);

    // Golden Peso coin / Philippine sun emblem
    final goldPaint = Paint()
      ..color = gold
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(54.0 * s, 57.5 * s), 8.2 * s, goldPaint);

    final innerGlow = Paint()
      ..color = const Color(0xFFFFF6DC)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(54.0 * s, 57.5 * s), 3.6 * s, innerGlow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              eyebrow.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: muted,
              ),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.45)),
      ],
    ),
  );
}

/// Lightweight, high-contrast surface card engineered for smooth 60 FPS
/// scrolling on low-end Android phones (zero BackdropFilter / offscreen blur).
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double borderRadius;
  final Border? border;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderRadius = 20,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    final resolvedBorder =
        border ??
        Border.all(
          color: isDark ? const Color(0xFF283A31) : const Color(0xFFDCE4DA),
          width: 1.0,
        );
    final resolvedColor =
        color ?? (isDark ? const Color(0xFF18241E) : Colors.white);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: radius,
        border: resolvedBorder,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.hardEdge,
        child: Padding(
          padding: padding,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  const StatusPill(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final lower = text.toLowerCase();
    final bad = lower.contains('overdue') || lower == 'reversed';
    final good =
        ['paid', 'occupied', 'finalized'].contains(lower) ||
        lower.endsWith(' paid');
    final color = bad
        ? danger
        : good
        ? ink
        : amber;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.11),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.42 : 0.26),
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: isDark && good ? const Color(0xFFAAD7B9) : color,
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: sage,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, size: 32, color: ink),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: muted, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
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
    padding: const EdgeInsets.symmetric(vertical: 6),
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
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
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
                      const SizedBox(height: 18),
                      fields(sheetContext, setState),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: danger,
                              fontWeight: FontWeight.w600,
                            ),
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
