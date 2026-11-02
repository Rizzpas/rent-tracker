import 'dart:async';

import 'package:flutter/material.dart';
import 'data/models.dart' hide Row;
import 'data/repository.dart';
import 'services/app_lock.dart';
import 'services/documents.dart';
import 'services/reminders.dart';
import 'ui/billing_page.dart';
import 'ui/collections_page.dart';
import 'ui/common.dart';
import 'ui/home_page.dart';
import 'ui/more_page.dart';
import 'ui/payments_page.dart';
import 'ui/rooms_page.dart';

class UpaRentaApp extends StatefulWidget {
  final RentalRepository? repository;
  final bool enablePlatformServices;
  const UpaRentaApp({
    super.key,
    this.repository,
    this.enablePlatformServices = true,
  });
  @override
  State<UpaRentaApp> createState() => _UpaRentaAppState();
}

class _UpaRentaAppState extends State<UpaRentaApp> {
  RentalRepository? _repository;
  AppData? _data;
  Object? _error;
  int _page = 0;
  String _period = billingPeriod(manilaNow());

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final repository = widget.repository ?? await RentalRepository.open();
      final data = await repository.load();
      if (mounted) {
        setState(() {
          _repository = repository;
          _data = data;
          _error = null;
        });
      }
      _schedule(data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    try {
      final data = await _repository!.load();
      if (mounted) setState(() => _data = data);
      _schedule(data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _schedule(AppData data) {
    if (!widget.enablePlatformServices) return;
    unawaited(
      ReminderService.reschedule(data).catchError((Object error) {
        if (mounted && data.settings['reminders'] == 'true') {
          final context = DocumentService.navigatorKey.currentContext;
          if (context != null && context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Reminders could not be scheduled. Check notification permission in phone settings.',
                ),
              ),
            );
          }
        }
      }),
    );
  }

  @override
  void dispose() {
    if (widget.repository == null) {
      unawaited(_repository?.close() ?? Future<void>.value());
    }
    super.dispose();
  }

  void _month(int delta) {
    final year = int.parse(_period.substring(0, 4));
    final month = int.parse(_period.substring(5, 7));
    final shifted = DateTime.utc(year, month + delta, 1);
    if (shifted.year >= 2000 && shifted.year <= 2100) {
      setState(() => _period = billingPeriod(shifted));
    }
  }

  Widget _activePage(AppData data, RentalRepository repository) =>
      switch (_page) {
        0 => HomePage(
          data: data,
          repository: repository,
          onChanged: _refresh,
          period: _period,
          onNavigate: (page) => setState(() => _page = page),
        ),
        1 => RoomsPage(
          data: data,
          repository: repository,
          onChanged: _refresh,
          period: _period,
        ),
        2 => BillingPage(
          data: data,
          repository: repository,
          onChanged: _refresh,
          period: _period,
        ),
        3 => PaymentsPage(
          data: data,
          repository: repository,
          onChanged: _refresh,
          period: _period,
        ),
        _ => MorePage(
          data: data,
          repository: repository,
          onChanged: _refresh,
          period: _period,
          enablePlatformServices: widget.enablePlatformServices,
        ),
      };

  ThemeData _theme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: brightness,
      primary: isLight ? ink : const Color(0xFFAAD7B9),
      surface: isLight ? Colors.white : const Color(0xFF18241E),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF3F6F1)
          : const Color(0xFF0E1713),
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: isLight ? const Color(0xFF1D3128) : const Color(0xFFE4ECE4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? Colors.white : const Color(0xFF14201A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: isLight ? const Color(0xFFCED8CC) : const Color(0xFF34463C),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : const Color(0xFF18241E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFD6DFD5) : const Color(0xFF2E3E36),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFD6DFD5) : const Color(0xFF2E3E36),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? ink : const Color(0xFFAAD7B9),
            width: 1.8,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(
            color: isLight ? const Color(0xFFC4D1C2) : const Color(0xFF394C41),
            width: 1.2,
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: isLight ? Colors.white : const Color(0xFF14201A),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: isLight ? sage : const Color(0xFF274234),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: DocumentService.navigatorKey,
    builder: (_, child) =>
        widget.enablePlatformServices ? AppLock(child: child!) : child!,
    title: 'Upa Renta · Offline rental ledger',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _data?.settings['dark_mode'] == 'true'
        ? ThemeMode.dark
        : ThemeMode.light,
    home: Builder(
      builder: (context) {
        if (_error != null) {
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storage_outlined, size: 48),
                      const SizedBox(height: 20),
                      const Text(
                        'Unable to open your records',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(friendlyError(_error!)),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _repository == null ? _open() : _refresh();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (_data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = _data!;
        final repository = _repository!;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final currentPeriod = billingPeriod(manilaNow());
        final collectionsCount = CollectionsSchedule.from(data).actionableCount;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF14201A) : Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? const Color(0xFF25362D)
                            : const Color(0xFFE0E7DE),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        const UpaRentaLogo(size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Upa Renta',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              Text(
                                '${data.settings['property_name'] ?? 'Your property'} · Offline',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: collectionsCount > 0
                              ? ink
                              : (isDark
                                    ? const Color(0xFF21352B)
                                    : sage.withValues(alpha: 0.85)),
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            key: const ValueKey('top-collections-day'),
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => openCollectionsDay(
                              context,
                              data: data,
                              repository: repository,
                              onChanged: _refresh,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 16,
                                    color: collectionsCount > 0
                                        ? gold
                                        : (isDark
                                              ? const Color(0xFFAAD7B9)
                                              : ink),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    collectionsCount > 0
                                        ? 'Collect ($collectionsCount)'
                                        : 'Collect',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: collectionsCount > 0
                                          ? Colors.white
                                          : (isDark
                                                ? const Color(0xFFAAD7B9)
                                                : ink),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_page != 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF18241E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF283A31)
                              : const Color(0xFFDCE4DA),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => _month(-1),
                              icon: const Icon(Icons.chevron_left_rounded),
                              tooltip: 'Previous month',
                            ),
                            Expanded(
                              child: InkWell(
                                key: const ValueKey('period-picker-trigger'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final selected = await showUpaMonthPicker(
                                    context,
                                    initialPeriod: _period,
                                  );
                                  if (selected != null) {
                                    setState(() => _period = selected);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.calendar_month_rounded,
                                        size: 16,
                                        color: isDark
                                            ? const Color(0xFFAAD7B9)
                                            : ink,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          monthLabel(_period),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_period != currentPeriod)
                              TextButton(
                                onPressed: () =>
                                    setState(() => _period = currentPeriod),
                                child: const Text(
                                  'Now',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            IconButton(
                              onPressed: () => _month(1),
                              icon: const Icon(Icons.chevron_right_rounded),
                              tooltip: 'Next month',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      key: ValueKey('$_page-$_period'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: _activePage(data, repository),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF25362D)
                      : const Color(0xFFE0E7DE),
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (value) => setState(() => _page = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.meeting_room_outlined),
                  selectedIcon: Icon(Icons.meeting_room_rounded),
                  label: 'Rooms',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'Billing',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'Payments',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'More',
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
