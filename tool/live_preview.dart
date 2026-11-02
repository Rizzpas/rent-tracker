import 'dart:async';

import 'package:bahay_rent/app.dart';
import 'package:bahay_rent/data/repository.dart';
import 'package:bahay_rent/services/documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';

import 'preview_database.dart';
import 'preview_seed.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DocumentService.platformActionsEnabled = false;
  runApp(const LivePreviewBootstrap());
}

@Preview(name: 'Bahay · Live app', group: 'Bahay', size: Size(430, 900))
Widget liveAppPreview() => const LivePreviewBootstrap();

/// Boots the real application against a separate, temporary browser ledger.
/// Refreshing the page discards edits and creates the demonstration records.
class LivePreviewBootstrap extends StatefulWidget {
  const LivePreviewBootstrap({super.key});

  @override
  State<LivePreviewBootstrap> createState() => _LivePreviewBootstrapState();
}

class _LivePreviewBootstrapState extends State<LivePreviewBootstrap> {
  late Future<RentalRepository> _opening;
  RentalRepository? _repository;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // @Preview invokes the widget without running this file's main().
    DocumentService.platformActionsEnabled = false;
    _opening = _open();
  }

  Future<RentalRepository> _open() async {
    RentalRepository? repository;
    try {
      final fonts = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      await fonts.load();
      repository = await openPreviewRepository();
      await seedPreviewData(repository);
      if (!mounted) {
        throw StateError('The preview was closed.');
      }
      _repository = repository;
      return repository;
    } catch (_) {
      if (repository != null && _repository != repository) {
        await repository.close();
      }
      rethrow;
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    final repository = _repository;
    if (repository != null) unawaited(repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bahay · Live UI preview',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF163D35)),
      fontFamily: 'Roboto',
    ),
    home: Scaffold(
      backgroundColor: const Color(0xFFE8ECE5),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final desktop = viewport.maxWidth >= 600;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 28 : 14,
                    vertical: desktop ? 16 : 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_android_rounded,
                        size: 16,
                        color: Color(0xFF355446),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Live UI preview',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF355446),
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'Demo data · refresh to reset',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: desktop ? 12 : 10,
                            color: const Color(0xFF617367),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 20 : 0,
                        0,
                        desktop ? 20 : 0,
                        desktop ? 8 : 0,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 430,
                          maxHeight: 900,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F5F0),
                            borderRadius: BorderRadius.circular(
                              desktop ? 24 : 0,
                            ),
                            boxShadow: desktop
                                ? const [
                                    BoxShadow(
                                      color: Color(0x1C163D35),
                                      blurRadius: 32,
                                      offset: Offset(0, 10),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              desktop ? 24 : 0,
                            ),
                            child: LayoutBuilder(
                              builder: (context, phone) => MediaQuery(
                                data: MediaQuery.of(
                                  context,
                                ).copyWith(size: phone.biggest),
                                child: FutureBuilder<RentalRepository>(
                                  future: _opening,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return _bootError();
                                    }
                                    if (!snapshot.hasData) {
                                      return const Material(
                                        color: Color(0xFFF6F5F0),
                                        child: Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(28),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(),
                                                SizedBox(height: 22),
                                                Text(
                                                  'Preparing your demo ledger…',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return BahayApp(
                                      repository: snapshot.data!,
                                      enablePlatformServices: false,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (desktop)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 14),
                    child: Text(
                      'Explore the actual app screens and forms. Preview changes stay in this browser tab.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF617367)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _bootError() => Material(
    color: const Color(0xFFF6F5F0),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.refresh_rounded,
              size: 40,
              color: Color(0xFF355446),
            ),
            const SizedBox(height: 18),
            const Text(
              'The demo could not start',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'Try reloading the demo. If it keeps happening, restart the local preview server.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: Color(0xFF617367)),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () {
                if (_loading) return;
                _loading = true;
                setState(() => _opening = _open());
              },
              child: const Text('Retry preview'),
            ),
          ],
        ),
      ),
    ),
  );
}
