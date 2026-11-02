import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:upa_renta/data/repository.dart';

/// Runs the real SQLite schema and financial ledger inside this browser tab.
///
/// Preview records stay in memory and are discarded when the page is reloaded.
/// The Android database is never opened. The web driver may create its own
/// browser storage metadata, but the SQLite ledger itself uses `:memory:`.
Future<RentalRepository> openPreviewRepository() async {
  if (!kIsWeb) {
    throw UnsupportedError('The browser preview must run on a web device.');
  }
  final factory = createDatabaseFactoryFfiWeb(
    options: SqfliteFfiWebOptions(
      inMemory: true,
      indexedDbName: 'upa_renta_preview_storage',
      sqlite3WasmUri: Uri.base.resolve('sqlite3.wasm'),
    ),
    noWebWorker: true,
  );
  return RentalRepository.open(factory: factory, path: inMemoryDatabasePath);
}
