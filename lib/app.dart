import 'dart:async';

import 'package:flutter/material.dart';
import 'data/models.dart' hide Row;
import 'data/repository.dart';
import 'services/documents.dart';
import 'services/app_lock.dart';
import 'services/reminders.dart';
import 'ui/common.dart';
import 'ui/home_page.dart';
import 'ui/rooms_page.dart';
import 'ui/billing_page.dart';
import 'ui/payments_page.dart';
import 'ui/more_page.dart';

class BahayApp extends StatefulWidget {
  final RentalRepository? repository;
  final bool enablePlatformServices;
  const BahayApp({
    super.key,
    this.repository,
    this.enablePlatformServices = true,
  });
  @override
  State<BahayApp> createState() => _BahayAppState();
}

class _BahayAppState extends State<BahayApp> {
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
    final current = DateTime.parse('$_period-01');
    setState(
      () => _period = billingPeriod(
        DateTime(current.year, current.month + delta),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: brightness,
      primary: brightness == Brightness.light ? ink : const Color(0xFFA8D2BA),
      surface: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF202B26),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? warm
          : const Color(0xFF151E1A),
      fontFamily: 'Roboto',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: brightness == Brightness.light
            ? const Color(0xFF263B31)
            : const Color(0xFFE4EBE3),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: brightness == Brightness.light
          ? const Color(0xFFCBD4C9)
          : const Color(0xFF64736B),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFF7F8F4)
            : const Color(0xFF17211B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4DCD2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4DCD2)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 78,
        backgroundColor: scheme.surface,
        indicatorColor: brightness == Brightness.light
            ? sage
            : const Color(0xFF375744),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: DocumentService.navigatorKey,
    builder: (_, child) =>
        widget.enablePlatformServices ? AppLock(child: child!) : child!,
    title: 'Bahay · Rent made simple',
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
        final pages = [
          HomePage(
            data: data,
            repository: repository,
            onChanged: _refresh,
            period: _period,
            onNavigate: (page) => setState(() => _page = page),
          ),
          RoomsPage(
            data: data,
            repository: repository,
            onChanged: _refresh,
            period: _period,
          ),
          BillingPage(
            data: data,
            repository: repository,
            onChanged: _refresh,
            period: _period,
          ),
          PaymentsPage(
            data: data,
            repository: repository,
            onChanged: _refresh,
            period: _period,
          ),
          MorePage(
            data: data,
            repository: repository,
            onChanged: _refresh,
            period: _period,
          ),
        ];
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 16, 16, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.roofing_rounded,
                          color: Color(0xFFE7EFDC),
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'bahay',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                              ),
                            ),
                            Text(
                              data.settings['property_name'] ??
                                  'Your rental property',
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: sage.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.offline_pin_outlined,
                              size: 14,
                              color: ink,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Offline ready',
                              style: TextStyle(
                                fontSize: 10,
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_page != 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => _month(-1),
                          icon: const Icon(Icons.chevron_left),
                          tooltip: 'Previous month',
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              final current = DateTime.parse('$_period-01');
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: current,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                initialDatePickerMode: DatePickerMode.year,
                                helpText: 'Choose a date in the billing month',
                              );
                              if (selected != null) {
                                setState(
                                  () => _period = billingPeriod(selected),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      monthLabel(_period),
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.expand_more, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _month(1),
                          icon: const Icon(Icons.chevron_right),
                          tooltip: 'Next month',
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      key: ValueKey('$_page-$_period'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1000),
                            child: pages[_page],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
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
        );
      },
    ),
  );
}
