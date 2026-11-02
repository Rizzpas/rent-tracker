import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_time.dart';
import 'common.dart' show amber, ink, muted, sage;

const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// Tactile, non-technical-user-friendly date field backed by our custom
/// Asia/Manila bottom-sheet calendar picker.
class DateInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String>? onChanged;

  const DateInput({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final raw = value.text.trim();
          final pretty = raw.isEmpty
              ? 'Select a date'
              : formatIsoDateLabel(raw, includeWeekday: true);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: isDark ? const Color(0xFF1A2620) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF2E3E36)
                        : const Color(0xFFD6DFD5),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final initial = _parseIso(raw) ?? manilaNow();
                    final picked = await showUpaDatePicker(
                      context,
                      initialDate: initial,
                      title: label,
                    );
                    if (picked != null) {
                      final formatted = isoDate(picked);
                      controller.text = formatted;
                      onChanged?.call(formatted);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF253C32)
                                : sage.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(
                              Icons.event_rounded,
                              size: 20,
                              color: isDark ? const Color(0xFFAAD7B9) : ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                pretty,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (raw.isNotEmpty)
                                Text(
                                  '$raw · Asia/Manila',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF24372E)
                                : const Color(0xFFEEF3EC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              'Pick',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFFAAD7B9) : ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (helper != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12, right: 12),
                  child: Text(
                    helper!,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 1-tap preset due-day selector (`5th`, `15th`, `30th`, `End of month`)
/// paired with custom day input (`1–31`) and live February/short-month preview.
class DueDaySelector extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const DueDaySelector({
    super.key,
    required this.controller,
    this.label = 'Payment due day (1–31)',
  });

  static const List<({int day, String label})> presets = [
    (day: 5, label: '5th'),
    (day: 15, label: '15th'),
    (day: 30, label: '30th'),
    (day: 31, label: 'End of month'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final parsed = int.tryParse(value.text.trim());
        String helper =
            'Tap a common due schedule above or enter any day from 1 to 31.';
        if (parsed != null && parsed >= 1 && parsed <= 31) {
          if (parsed == 31) {
            helper =
                'End of month: 31st on 31-day months, 30th on 30-day months, and 28th/29th in February.';
          } else if (parsed >= 29) {
            helper =
                'Every ${ordinalDay(parsed)} — automatically uses Feb 28 (or Feb 29 in leap years).';
          } else {
            helper = 'Due on the ${ordinalDay(parsed)} of every month (Asia/Manila).';
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Due date schedule',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets
                  .map(
                    (preset) => ChoiceChip(
                      label: Text(preset.label),
                      selected: parsed == preset.day,
                      onSelected: (_) => controller.text = '${preset.day}',
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: label,
                helperText: helper,
                helperMaxLines: 3,
              ),
              validator: (v) {
                final d = int.tryParse((v ?? '').trim());
                if (d == null || d < 1 || d > 31) {
                  return 'Choose a due day from 1 to 31.';
                }
                return null;
              },
            ),
          ],
        );
      },
    ),
  );
}

DateTime? _parseIso(String input) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(input.trim());
  if (match == null) return null;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  return DateTime.utc(y, m, d);
}

/// Opens Upa Renta's fast, thumb-friendly bottom-sheet calendar picker in
/// `Asia/Manila` time, with 1-tap presets for Today, 5th, 15th, 30th, and
/// End-of-month (including February).
Future<DateTime?> showUpaDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  String title = 'Select date',
  int firstYear = 1990,
  int lastYear = 2100,
  DateTime? manilaClock,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => UpaDatePickerSheet(
    initialDate: DateTime.utc(
      initialDate.year.clamp(firstYear, lastYear),
      initialDate.month,
      clampDayToMonth(
        initialDate.year.clamp(firstYear, lastYear),
        initialDate.month,
        initialDate.day,
      ),
    ),
    title: title,
    firstYear: firstYear,
    lastYear: lastYear,
    manilaClock: manilaClock,
  ),
);

class UpaDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final String title;
  final int firstYear;
  final int lastYear;
  final DateTime? manilaClock;

  const UpaDatePickerSheet({
    super.key,
    required this.initialDate,
    required this.title,
    this.firstYear = 1990,
    this.lastYear = 2100,
    this.manilaClock,
  });

  @override
  State<UpaDatePickerSheet> createState() => _UpaDatePickerSheetState();
}

class _UpaDatePickerSheetState extends State<UpaDatePickerSheet> {
  late DateTime _selected = widget.initialDate;
  late int _viewYear = widget.initialDate.year;
  late int _viewMonth = widget.initialDate.month;
  bool _pickingMonthYear = false;

  void _shiftMonth(int delta) {
    final moved = DateTime.utc(_viewYear, _viewMonth + delta, 1);
    if (moved.year < widget.firstYear || moved.year > widget.lastYear) return;
    setState(() {
      _viewYear = moved.year;
      _viewMonth = moved.month;
    });
  }

  void _selectDay(int year, int month, int day) {
    final clamped = clampDayToMonth(year, month, day);
    setState(() {
      _viewYear = year;
      _viewMonth = month;
      _selected = DateTime.utc(year, month, clamped);
      _pickingMonthYear = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nowManila = manilaNow(widget.manilaClock);
    final todayIso = isoDate(nowManila);
    final selectedIso = isoDate(_selected);
    final totalDays = daysInMonth(_viewYear, _viewMonth);
    final firstWeekdayOffset = DateTime.utc(_viewYear, _viewMonth, 1).weekday % 7;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatIsoDateLabel(selectedIso, includeWeekday: true),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF20332A)
                        : sage.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      'Asia/Manila',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFAAD7B9) : ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _presetChip(
                  label: 'Today',
                  selected: selectedIso == todayIso,
                  onTap: () => _selectDay(
                    nowManila.year,
                    nowManila.month,
                    nowManila.day,
                  ),
                ),
                _presetChip(
                  label: '5th',
                  selected:
                      _selected.year == _viewYear &&
                      _selected.month == _viewMonth &&
                      _selected.day == 5,
                  onTap: () => _selectDay(_viewYear, _viewMonth, 5),
                ),
                _presetChip(
                  label: '15th',
                  selected:
                      _selected.year == _viewYear &&
                      _selected.month == _viewMonth &&
                      _selected.day == 15,
                  onTap: () => _selectDay(_viewYear, _viewMonth, 15),
                ),
                _presetChip(
                  label: '30th',
                  selected:
                      _selected.year == _viewYear &&
                      _selected.month == _viewMonth &&
                      _selected.day ==
                          clampDayToMonth(_viewYear, _viewMonth, 30) &&
                      totalDays >= 30,
                  onTap: () => _selectDay(_viewYear, _viewMonth, 30),
                ),
                _presetChip(
                  label: 'End of month ($totalDays)',
                  selected:
                      _selected.year == _viewYear &&
                      _selected.month == _viewMonth &&
                      _selected.day == totalDays,
                  onTap: () => _selectDay(_viewYear, _viewMonth, 31),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF18241E)
                    : const Color(0xFFF3F6F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(
                          () => _pickingMonthYear = !_pickingMonthYear,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  formatPeriodLabel(
                                    '${_viewYear.toString().padLeft(4, '0')}-${_viewMonth.toString().padLeft(2, '0')}',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _pickingMonthYear
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_pickingMonthYear)
              _buildMonthYearGrid(isDark)
            else
              _buildCalendarGrid(
                isDark: isDark,
                totalDays: totalDays,
                firstWeekdayOffset: firstWeekdayOffset,
                todayIso: todayIso,
                selectedIso: selectedIso,
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: Text('Use ${formatIsoDateLabel(selectedIso)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => ActionChip(
    visualDensity: VisualDensity.compact,
    backgroundColor: selected ? sage : null,
    side: BorderSide(
      color: selected ? ink : const Color(0xFFCBD5C9),
      width: selected ? 1.4 : 1.0,
    ),
    label: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? ink : null,
      ),
    ),
    onPressed: onTap,
  );

  Widget _buildMonthYearGrid(bool isDark) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous year',
            onPressed: _viewYear > widget.firstYear
                ? () => setState(() => _viewYear--)
                : null,
            icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$_viewYear',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Next year',
            onPressed: _viewYear < widget.lastYear
                ? () => setState(() => _viewYear++)
                : null,
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 12,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
        ),
        itemBuilder: (context, index) {
          final month = index + 1;
          final active = month == _viewMonth;
          return Material(
            color: active
                ? ink
                : (isDark ? const Color(0xFF1A2821) : const Color(0xFFF3F6F1)),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _selectDay(_viewYear, month, _selected.day),
              child: Center(
                child: Text(
                  _shortMonths[index],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );

  Widget _buildCalendarGrid({
    required bool isDark,
    required int totalDays,
    required int firstWeekdayOffset,
    required String todayIso,
    required String selectedIso,
  }) {
    final cellCount = firstWeekdayOffset + totalDays;
    return Column(
      children: [
        Row(
          children: _weekdayHeaders
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.32,
          ),
          itemBuilder: (context, index) {
            if (index < firstWeekdayOffset) return const SizedBox.shrink();
            final day = index - firstWeekdayOffset + 1;
            final cellIso =
                '${_viewYear.toString().padLeft(4, '0')}-${_viewMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            final isSelected = cellIso == selectedIso;
            final isToday = cellIso == todayIso;
            return Material(
              color: isSelected
                  ? ink
                  : isToday
                  ? (isDark
                        ? const Color(0xFF23382E)
                        : sage.withValues(alpha: 0.65))
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isToday && !isSelected
                    ? BorderSide(
                        color: isDark ? const Color(0xFFAAD7B9) : amber,
                        width: 1.3,
                      )
                    : BorderSide.none,
              ),
              child: InkWell(
                key: ValueKey('calendar-day-$cellIso'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => _selectDay(_viewYear, _viewMonth, day),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontWeight: isSelected || isToday
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Fast 1-tap billing month picker (`YYYY-MM`) in `Asia/Manila` time.
Future<String?> showUpaMonthPicker(
  BuildContext context, {
  required String initialPeriod,
  int firstYear = 2000,
  int lastYear = 2100,
  DateTime? manilaClock,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => _UpaMonthPickerSheet(
    initialPeriod: initialPeriod,
    firstYear: firstYear,
    lastYear: lastYear,
    manilaClock: manilaClock,
  ),
);

class _UpaMonthPickerSheet extends StatefulWidget {
  final String initialPeriod;
  final int firstYear;
  final int lastYear;
  final DateTime? manilaClock;

  const _UpaMonthPickerSheet({
    required this.initialPeriod,
    required this.firstYear,
    required this.lastYear,
    this.manilaClock,
  });

  @override
  State<_UpaMonthPickerSheet> createState() => _UpaMonthPickerSheetState();
}

class _UpaMonthPickerSheetState extends State<_UpaMonthPickerSheet> {
  late int _year = int.parse(widget.initialPeriod.substring(0, 4));
  late final int _initialMonth = int.parse(widget.initialPeriod.substring(5, 7));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = manilaNow(widget.manilaClock);
    final thisMonth = billingPeriod(now);
    final lastMonth = billingPeriod(DateTime.utc(now.year, now.month - 1, 1));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'BILLING MONTH · ASIA/MANILA',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Choose billing month',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text('This month (${formatPeriodLabel(thisMonth)})'),
                  onPressed: () => Navigator.pop(context, thisMonth),
                ),
                ActionChip(
                  label: Text('Last month (${formatPeriodLabel(lastMonth)})'),
                  onPressed: () => Navigator.pop(context, lastMonth),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  onPressed: _year > widget.firstYear
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '$_year',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next year',
                  onPressed: _year < widget.lastYear
                      ? () => setState(() => _year++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.2,
              ),
              itemBuilder: (context, index) {
                final month = index + 1;
                final period =
                    '${_year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
                final selected =
                    period == widget.initialPeriod ||
                    (_year == int.parse(widget.initialPeriod.substring(0, 4)) &&
                        month == _initialMonth);
                return Material(
                  color: selected
                      ? ink
                      : (isDark
                            ? const Color(0xFF1A2821)
                            : const Color(0xFFF3F6F1)),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: ValueKey('month-cell-$period'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, period),
                    child: Center(
                      child: Text(
                        _shortMonths[index],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
