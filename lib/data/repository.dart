import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// The single writer for the offline financial ledger.
/// Money is always integer centavos. Quantities are integer thousandths.
class RentalRepository {
  final Database _db;
  final DatabaseFactory _factory;
  RentalRepository._(this._db, this._factory);

  static const _maximum = 900000000000;
  static const defaults = <String, String>{
    'property_name': 'My rental property',
    'property_address': '',
    'owner_name': '',
    'dark_mode': 'false',
    'reminders': 'false',
    'meter_day': '25',
    'last_backup': '',
  };
  static const _tables = [
    'rooms',
    'tenants',
    'tenancies',
    'invoices',
    'lines',
    'readings',
    'payments',
    'allocations',
    'deposits',
    'audit',
    'settings',
  ];
  static const _columns = <String, Set<String>>{
    'rooms': {
      'id',
      'name',
      'rent_cents',
      'electricity_mode',
      'electricity_rate',
      'water_mode',
      'water_rate',
      'notes',
      'archived',
    },
    'tenants': {'id', 'name', 'phone', 'notes'},
    'tenancies': {
      'id',
      'room_id',
      'tenant_id',
      'move_in',
      'move_out',
      'rent_cents',
      'due_day',
    },
    'invoices': {
      'id',
      'tenancy_id',
      'room_id',
      'period',
      'due_date',
      'status',
      'total_cents',
      'reference',
      'created_at',
      'finalized_at',
    },
    'lines': {
      'id',
      'invoice_id',
      'kind',
      'mode',
      'description',
      'quantity',
      'rate_cents',
      'amount_cents',
    },
    'readings': {
      'id',
      'room_id',
      'kind',
      'period',
      'previous_value',
      'current_value',
      'invoice_id',
    },
    'payments': {
      'id',
      'date',
      'amount_cents',
      'method',
      'reference',
      'notes',
      'request_id',
      'reversed_at',
      'reversal_reason',
    },
    'allocations': {'id', 'payment_id', 'invoice_id', 'amount_cents'},
    'deposits': {'id', 'tenancy_id', 'kind', 'amount_cents', 'date', 'notes'},
    'audit': {'id', 'action', 'entity', 'entity_id', 'detail', 'created_at'},
    'settings': {'key', 'value'},
  };

  static Future<RentalRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final dbPath =
        path ??
        p.join(await selectedFactory.getDatabasesPath(), 'bahay_rent.db');
    final db = await selectedFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
          for (final entry in defaults.entries) {
            await db.insert('settings', {
              'key': entry.key,
              'value': entry.value,
            });
          }
        },
      ),
    );
    return RentalRepository._(db, selectedFactory);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    final statements = <String>[
      'CREATE TABLE restore_guard (id INTEGER PRIMARY KEY CHECK(id=1), enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN(0,1)))',
      'INSERT INTO restore_guard(id,enabled) VALUES(1,0)',
      '''CREATE TABLE rooms (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name))>0),
        rent_cents INTEGER NOT NULL CHECK(rent_cents>=0),
        electricity_mode TEXT NOT NULL CHECK(electricity_mode IN('metered','fixed','shared')),
        electricity_rate INTEGER NOT NULL CHECK(electricity_rate>=0),
        water_mode TEXT NOT NULL CHECK(water_mode IN('metered','fixed','shared')),
        water_rate INTEGER NOT NULL CHECK(water_rate>=0), notes TEXT NOT NULL DEFAULT '',
        archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN(0,1)))''',
      '''CREATE TABLE tenants (id INTEGER PRIMARY KEY, name TEXT NOT NULL CHECK(length(trim(name))>0),
        phone TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '')''',
      '''CREATE TABLE tenancies (
        id INTEGER PRIMARY KEY, room_id INTEGER NOT NULL REFERENCES rooms(id),
        tenant_id INTEGER NOT NULL REFERENCES tenants(id), move_in TEXT NOT NULL, move_out TEXT,
        rent_cents INTEGER NOT NULL CHECK(rent_cents>=0), due_day INTEGER NOT NULL CHECK(due_day BETWEEN 1 AND 31),
        CHECK(move_out IS NULL OR move_out>=move_in))''',
      'CREATE UNIQUE INDEX one_active_room ON tenancies(room_id) WHERE move_out IS NULL',
      'CREATE UNIQUE INDEX one_active_tenant ON tenancies(tenant_id) WHERE move_out IS NULL',
      '''CREATE TABLE invoices (
        id INTEGER PRIMARY KEY, tenancy_id INTEGER NOT NULL REFERENCES tenancies(id), room_id INTEGER NOT NULL REFERENCES rooms(id),
        period TEXT NOT NULL, due_date TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN('draft','final')),
        total_cents INTEGER NOT NULL CHECK(total_cents>=0), reference TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL, finalized_at TEXT, UNIQUE(room_id,period), UNIQUE(tenancy_id,period),
        CHECK((status='draft' AND finalized_at IS NULL) OR (status='final' AND finalized_at IS NOT NULL)))''',
      '''CREATE TABLE lines (
        id INTEGER PRIMARY KEY, invoice_id INTEGER NOT NULL REFERENCES invoices(id),
        kind TEXT NOT NULL CHECK(kind IN('rent','electricity','water','adjustment')),
        mode TEXT NOT NULL CHECK(mode IN('rent','metered','fixed','shared','adjustment')),
        description TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity>=0),
        rate_cents INTEGER NOT NULL, amount_cents INTEGER NOT NULL,
        CHECK(kind='adjustment' OR (amount_cents>=0 AND rate_cents>=0)), UNIQUE(invoice_id,kind))''',
      '''CREATE TABLE readings (
        id INTEGER PRIMARY KEY, room_id INTEGER NOT NULL REFERENCES rooms(id),
        kind TEXT NOT NULL CHECK(kind IN('electricity','water')), period TEXT NOT NULL,
        previous_value INTEGER NOT NULL CHECK(previous_value>=0), current_value INTEGER NOT NULL CHECK(current_value>=previous_value),
        invoice_id INTEGER NOT NULL REFERENCES invoices(id), UNIQUE(room_id,kind,period), UNIQUE(invoice_id,kind))''',
      '''CREATE TABLE payments (
        id INTEGER PRIMARY KEY, date TEXT NOT NULL, amount_cents INTEGER NOT NULL CHECK(amount_cents>0),
        method TEXT NOT NULL CHECK(method IN('Cash','GCash','Bank transfer','Other')),
        reference TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', request_id TEXT NOT NULL UNIQUE CHECK(length(request_id)>0),
        reversed_at TEXT, reversal_reason TEXT,
        CHECK((reversed_at IS NULL AND reversal_reason IS NULL) OR (reversed_at IS NOT NULL AND length(trim(reversal_reason))>0)))''',
      '''CREATE TABLE allocations (id INTEGER PRIMARY KEY, payment_id INTEGER NOT NULL REFERENCES payments(id),
        invoice_id INTEGER NOT NULL REFERENCES invoices(id), amount_cents INTEGER NOT NULL CHECK(amount_cents>0),
        UNIQUE(payment_id,invoice_id))''',
      '''CREATE TABLE deposits (id INTEGER PRIMARY KEY, tenancy_id INTEGER NOT NULL REFERENCES tenancies(id),
        kind TEXT NOT NULL CHECK(kind IN('received','refund','deduction')),
        amount_cents INTEGER NOT NULL CHECK(amount_cents>0), date TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '')''',
      '''CREATE TABLE audit (id INTEGER PRIMARY KEY, action TEXT NOT NULL, entity TEXT NOT NULL,
        entity_id INTEGER NOT NULL, detail TEXT NOT NULL, created_at TEXT NOT NULL)''',
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      'CREATE INDEX invoice_period ON invoices(period,status)',
      'CREATE INDEX payments_date ON payments(date)',
      'CREATE INDEX reading_history ON readings(room_id,kind,period)',
      '''CREATE TRIGGER frozen_invoice_update BEFORE UPDATE ON invoices
        WHEN OLD.status='final' AND (SELECT enabled FROM restore_guard WHERE id=1)=0
        BEGIN SELECT RAISE(ABORT,'Finalized invoices cannot be changed.'); END''',
      '''CREATE TRIGGER frozen_invoice_delete BEFORE DELETE ON invoices
        WHEN OLD.status='final' AND (SELECT enabled FROM restore_guard WHERE id=1)=0
        BEGIN SELECT RAISE(ABORT,'Finalized invoices cannot be deleted.'); END''',
    ];
    for (final statement in statements) {
      await db.execute(statement);
    }
    for (final table in ['lines', 'readings']) {
      for (final operation in ['UPDATE', 'DELETE']) {
        await db.execute(
          '''CREATE TRIGGER frozen_${table}_${operation.toLowerCase()} BEFORE $operation ON $table
          WHEN (SELECT status FROM invoices WHERE id=OLD.invoice_id)='final'
          AND (SELECT enabled FROM restore_guard WHERE id=1)=0
          BEGIN SELECT RAISE(ABORT,'Finalized bill details cannot be changed.'); END''',
        );
      }
    }
    for (final table in ['allocations', 'deposits', 'audit']) {
      for (final operation in ['UPDATE', 'DELETE']) {
        await db.execute(
          '''CREATE TRIGGER ledger_${table}_${operation.toLowerCase()} BEFORE $operation ON $table
          WHEN (SELECT enabled FROM restore_guard WHERE id=1)=0
          BEGIN SELECT RAISE(ABORT,'Ledger history must be preserved.'); END''',
        );
      }
    }
    await db.execute(
      '''CREATE TRIGGER payment_update BEFORE UPDATE ON payments
      WHEN (SELECT enabled FROM restore_guard WHERE id=1)=0 AND (
        OLD.reversed_at IS NOT NULL OR NEW.reversed_at IS NULL OR NEW.reversal_reason IS NULL OR length(trim(NEW.reversal_reason))=0
        OR NEW.id!=OLD.id OR NEW.date!=OLD.date OR NEW.amount_cents!=OLD.amount_cents OR NEW.method!=OLD.method
        OR NEW.reference!=OLD.reference OR NEW.notes!=OLD.notes OR NEW.request_id!=OLD.request_id)
      BEGIN SELECT RAISE(ABORT,'Payments can only be reversed with a reason.'); END''',
    );
    await db.execute(
      '''CREATE TRIGGER payment_delete BEFORE DELETE ON payments
      WHEN (SELECT enabled FROM restore_guard WHERE id=1)=0
      BEGIN SELECT RAISE(ABORT,'Payments must be reversed, not deleted.'); END''',
    );
  }

  Future<void> close() => _db.close();

  Future<AppData> load() => _db.transaction((tx) async {
    final data = <String, List<Row>>{};
    for (final table in _tables) {
      data[table] = (await tx.query(
        table,
        orderBy: table == 'settings' ? 'key' : 'id',
      )).map((r) => Map<String, dynamic>.from(r)).toList();
    }
    return AppData(
      rooms: data['rooms']!,
      tenants: data['tenants']!,
      tenancies: data['tenancies']!,
      readings: data['readings']!,
      invoices: data['invoices']!,
      lines: data['lines']!,
      payments: data['payments']!,
      allocations: data['allocations']!,
      deposits: data['deposits']!,
      audit: data['audit']!,
      settings: {
        for (final r in data['settings']!)
          r['key'] as String: r['value'] as String,
      },
    );
  });

  static String _now() => DateTime.now().toUtc().toIso8601String();
  static void _fail(String message) => throw StateError(message);
  static void _money(int amount, {bool signed = false, bool positive = false}) {
    if ((!signed && amount < 0) ||
        (positive && amount <= 0) ||
        amount > _maximum ||
        amount < -_maximum) {
      _fail(
        'Enter a ${positive ? 'positive' : 'valid'} amount within the supported limit.',
      );
    }
  }

  static void _date(String date) {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        isoDate(parsed) != date ||
        parsed.year < 1900 ||
        parsed.year > 2200) {
      _fail('Enter a valid date between 1900 and 2200.');
    }
  }

  static void _period(String period) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      _fail('Choose a valid billing month.');
    }
    _date('$period-01');
  }

  static void _dueDay(int day) {
    if (day < 1 || day > 31) _fail('The due day must be between 1 and 31.');
  }

  static String _text(String text, {bool required = false, int limit = 10000}) {
    final value = text.trim();
    if ((required && value.isEmpty) || value.length > limit) {
      _fail(
        'Enter ${required ? 'a value' : 'text'} of up to $limit characters.',
      );
    }
    return value;
  }

  static Future<Row> _require(DatabaseExecutor db, String table, int id) async {
    final rows = await db.query(table, where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) {
      _fail('This $table record could not be found. Refresh and try again.');
    }
    return Map<String, dynamic>.from(rows.first);
  }

  static Future<void> _audit(
    DatabaseExecutor db,
    String action,
    String entity,
    int id,
    String detail,
  ) => db
      .insert('audit', {
        'action': action,
        'entity': entity,
        'entity_id': id,
        'detail': detail,
        'created_at': _now(),
      })
      .then((_) {});

  Future<int> saveRoom(Row values) async {
    final name = _text(
      values['name'] as String? ?? '',
      required: true,
      limit: 100,
    );
    final rent = values['rent_cents'] as int? ?? 0;
    final electricityRate = values['electricity_rate'] as int? ?? 0;
    final waterRate = values['water_rate'] as int? ?? 0;
    for (final v in [rent, electricityRate, waterRate]) {
      _money(v);
    }
    final electricityMode = values['electricity_mode'] as String? ?? 'metered';
    final waterMode = values['water_mode'] as String? ?? 'metered';
    for (final mode in [electricityMode, waterMode]) {
      if (!['metered', 'fixed', 'shared'].contains(mode)) {
        _fail('Choose metered, fixed, or shared utility billing.');
      }
    }
    return _db.transaction((tx) async {
      final id = values['id'] as int?;
      final duplicates = await tx.query(
        'rooms',
        where: 'name=? COLLATE NOCASE AND id!=?',
        whereArgs: [name, id ?? -1],
      );
      if (duplicates.isNotEmpty) {
        _fail('A room with this name already exists. Choose another name.');
      }
      final row = <String, Object?>{
        'name': name,
        'rent_cents': rent,
        'electricity_mode': electricityMode,
        'electricity_rate': electricityRate,
        'water_mode': waterMode,
        'water_rate': waterRate,
        'notes': _text(values['notes'] as String? ?? ''),
      };
      if (id != null) {
        await _require(tx, 'rooms', id);
        await tx.update('rooms', row, where: 'id=?', whereArgs: [id]);
        await _audit(
          tx,
          'updated',
          'room',
          id,
          'Room information and future billing defaults updated.',
        );
        return id;
      }
      final inserted = await tx.insert('rooms', row);
      await _audit(tx, 'created', 'room', inserted, 'Created room $name.');
      return inserted;
    });
  }

  Future<void> archiveRoom(int id) => _db.transaction((tx) async {
    await _require(tx, 'rooms', id);
    if ((await tx.query(
      'tenancies',
      where: 'room_id=? AND move_out IS NULL',
      whereArgs: [id],
    )).isNotEmpty) {
      _fail('Move the current tenant out before archiving this room.');
    }
    await tx.update('rooms', {'archived': 1}, where: 'id=?', whereArgs: [id]);
    await _audit(
      tx,
      'archived',
      'room',
      id,
      'Room archived; all historical records retained.',
    );
  });

  Future<int> assignTenant({
    required int roomId,
    required String name,
    required String phone,
    required String moveIn,
    required int rentCents,
    required int depositCents,
    required int dueDay,
    String notes = '',
  }) async {
    _date(moveIn);
    _money(rentCents);
    _money(depositCents);
    _dueDay(dueDay);
    final validName = _text(name, required: true, limit: 200);
    final validPhone = _text(phone, limit: 100);
    final validNotes = _text(notes);
    return _db.transaction((tx) async {
      final room = await _require(tx, 'rooms', roomId);
      if (room['archived'] == 1) {
        _fail('This room is archived. Use an available room.');
      }
      final overlaps = await tx.query(
        'tenancies',
        where: 'room_id=? AND (move_out IS NULL OR move_out>?)',
        whereArgs: [roomId, moveIn],
      );
      if (overlaps.isNotEmpty) {
        _fail(
          'This assignment overlaps another tenant. Check the room and move-in date.',
        );
      }
      final tenantId = await tx.insert('tenants', {
        'name': validName,
        'phone': validPhone,
        'notes': validNotes,
      });
      final id = await tx.insert('tenancies', {
        'room_id': roomId,
        'tenant_id': tenantId,
        'move_in': moveIn,
        'move_out': null,
        'rent_cents': rentCents,
        'due_day': dueDay,
      });
      if (depositCents > 0) {
        await tx.insert('deposits', {
          'tenancy_id': id,
          'kind': 'received',
          'amount_cents': depositCents,
          'date': moveIn,
          'notes': 'Security deposit received at move-in.',
        });
      }
      await _audit(
        tx,
        'assigned',
        'tenancy',
        id,
        '$validName assigned to ${room['name']}; security deposit $depositCents centavos.',
      );
      return id;
    });
  }

  Future<void> updateTenant({
    required int tenancyId,
    required String name,
    required String phone,
    required int rentCents,
    required int dueDay,
    String notes = '',
  }) async {
    _money(rentCents);
    _dueDay(dueDay);
    final validName = _text(name, required: true, limit: 200);
    final validPhone = _text(phone, limit: 100);
    final validNotes = _text(notes);
    await _db.transaction((tx) async {
      final tenancy = await _require(tx, 'tenancies', tenancyId);
      await tx.update(
        'tenants',
        {'name': validName, 'phone': validPhone, 'notes': validNotes},
        where: 'id=?',
        whereArgs: [tenancy['tenant_id']],
      );
      await tx.update(
        'tenancies',
        {'rent_cents': rentCents, 'due_day': dueDay},
        where: 'id=?',
        whereArgs: [tenancyId],
      );
      await _audit(
        tx,
        'updated',
        'tenancy',
        tenancyId,
        'Tenant agreement updated; existing finalized bills retain their original charges.',
      );
    });
  }

  Future<void> moveOut(int tenancyId, String date) async {
    _date(date);
    await _db.transaction((tx) async {
      final tenancy = await _require(tx, 'tenancies', tenancyId);
      if (tenancy['move_out'] != null) {
        _fail('This tenant has already moved out.');
      }
      if (date.compareTo(tenancy['move_in'] as String) < 0) {
        _fail('Move-out cannot be before move-in.');
      }
      if ((await tx.query(
        'invoices',
        where: 'tenancy_id=? AND (period>? OR (period=? AND ?=1))',
        whereArgs: [
          tenancyId,
          date.substring(0, 7),
          date.substring(0, 7),
          date.endsWith('-01') ? 1 : 0,
        ],
      )).isNotEmpty) {
        _fail(
          'This tenant has bills after the selected move-out month. Check the date.',
        );
      }
      await tx.update(
        'tenancies',
        {'move_out': date},
        where: 'id=?',
        whereArgs: [tenancyId],
      );
      await _audit(
        tx,
        'moved_out',
        'tenancy',
        tenancyId,
        'Move-out on $date. Bills, payments, and security deposit history retained.',
      );
    });
  }

  static int _charge(int quantity, int rate) {
    final result =
        (BigInt.from(quantity) * BigInt.from(rate) + BigInt.from(500)) ~/
        BigInt.from(1000);
    if (result > BigInt.from(_maximum)) {
      _fail('This utility amount is too large. Check the reading and rate.');
    }
    return result.toInt();
  }

  Future<int> saveDraft({
    required int tenancyId,
    required String period,
    required String dueDate,
    int? electricityCurrent,
    int? waterCurrent,
    int? electricityPrevious,
    int? waterPrevious,
    int adjustmentCents = 0,
    String adjustmentNote = '',
    int? electricitySharedCents,
    int? waterSharedCents,
  }) async {
    _period(period);
    _date(dueDate);
    _money(adjustmentCents, signed: true);
    final note = _text(adjustmentNote);
    if (adjustmentCents != 0 && note.isEmpty) {
      _fail('Describe the adjustment or discount.');
    }
    for (final value in [
      electricityCurrent,
      waterCurrent,
      electricityPrevious,
      waterPrevious,
    ]) {
      if (value != null && (value < 0 || value > _maximum)) {
        _fail(
          'Meter readings must be positive and within the supported limit.',
        );
      }
    }
    for (final value in [electricitySharedCents, waterSharedCents]) {
      if (value != null) _money(value);
    }
    return _db.transaction((tx) async {
      final tenancy = await _require(tx, 'tenancies', tenancyId);
      final room = await _require(tx, 'rooms', tenancy['room_id'] as int);
      final start = DateTime.parse('$period-01');
      final end = isoDate(DateTime(start.year, start.month + 1, 0));
      if ((tenancy['move_in'] as String).compareTo(end) > 0 ||
          (tenancy['move_out'] != null &&
              (tenancy['move_out'] as String).compareTo('$period-01') <= 0)) {
        _fail('The tenant did not occupy this room during the selected month.');
      }
      final existing = await tx.query(
        'invoices',
        where: 'room_id=? AND period=?',
        whereArgs: [room['id'], period],
      );
      if (existing.isNotEmpty && existing.first['tenancy_id'] != tenancyId) {
        _fail(
          'This room already has a bill for this month under its previous tenant.',
        );
      }
      if (existing.isNotEmpty && existing.first['status'] == 'final') {
        _fail('This bill has already been finalized and cannot be changed.');
      }
      final id = existing.isEmpty
          ? await tx.insert('invoices', {
              'tenancy_id': tenancyId,
              'room_id': room['id'],
              'period': period,
              'due_date': dueDate,
              'status': 'draft',
              'total_cents': 0,
              'reference': 'BILL-${period.replaceAll('-', '')}-R${room['id']}',
              'created_at': _now(),
              'finalized_at': null,
            })
          : existing.first['id'] as int;
      final oldReadings = await tx.query(
        'readings',
        where: 'invoice_id=?',
        whereArgs: [id],
      );
      await tx.delete('lines', where: 'invoice_id=?', whereArgs: [id]);
      await tx.delete('readings', where: 'invoice_id=?', whereArgs: [id]);
      final rent = tenancy['rent_cents'] as int;
      await tx.insert('lines', {
        'invoice_id': id,
        'kind': 'rent',
        'mode': 'rent',
        'description': 'Monthly house rent',
        'quantity': 1000,
        'rate_cents': rent,
        'amount_cents': rent,
      });
      var total = rent;
      for (final kind in ['electricity', 'water']) {
        final mode = room['${kind}_mode'] as String;
        final rate = room['${kind}_rate'] as int;
        var amount = rate;
        var quantity = 1000;
        var appliedRate = rate;
        final label = kind == 'electricity' ? 'Electricity' : 'Water';
        var description = '$label · $mode charge';
        if (mode == 'metered') {
          final later = await tx.rawQuery(
            '''SELECT r.id FROM readings r JOIN invoices i ON i.id=r.invoice_id
            WHERE r.room_id=? AND r.kind=? AND r.period>? AND i.status='final' LIMIT 1''',
            [room['id'], kind, period],
          );
          if (later.isNotEmpty) {
            _fail(
              'A later month already has a finalized $kind reading. Enter meter bills in month order.',
            );
          }
          final history = await tx.rawQuery(
            '''SELECT r.current_value FROM readings r JOIN invoices i ON i.id=r.invoice_id
            WHERE r.room_id=? AND r.kind=? AND r.period<? AND i.status='final' ORDER BY r.period DESC LIMIT 1''',
            [room['id'], kind, period],
          );
          final old = oldReadings.where((r) => r['kind'] == kind).firstOrNull;
          final initial = kind == 'electricity'
              ? electricityPrevious
              : waterPrevious;
          final previous = history.isNotEmpty
              ? history.first['current_value'] as int
              : initial ?? old?['previous_value'] as int? ?? 0;
          if (history.isNotEmpty && initial != null && initial != previous) {
            _fail(
              'The previous $kind reading must match the last finalized reading.',
            );
          }
          final current = kind == 'electricity'
              ? electricityCurrent
              : waterCurrent;
          quantity = 0;
          amount = 0;
          description = '$label · awaiting meter reading';
          if (current != null) {
            if (current < previous) {
              _fail(
                'The current $kind reading cannot be lower than $previous thousandths. Check the previous reading.',
              );
            }
            quantity = current - previous;
            amount = _charge(quantity, rate);
            description = '$label · metered consumption';
            await tx.insert('readings', {
              'room_id': room['id'],
              'kind': kind,
              'period': period,
              'previous_value': previous,
              'current_value': current,
              'invoice_id': id,
            });
          }
        } else if (mode == 'shared') {
          amount =
              (kind == 'electricity'
                  ? electricitySharedCents
                  : waterSharedCents) ??
              rate;
          appliedRate = amount;
          description = '$label · allocated shared charge';
        }
        total += amount;
        await tx.insert('lines', {
          'invoice_id': id,
          'kind': kind,
          'mode': mode,
          'description': description,
          'quantity': quantity,
          'rate_cents': appliedRate,
          'amount_cents': amount,
        });
      }
      if (adjustmentCents != 0) {
        total += adjustmentCents;
        await tx.insert('lines', {
          'invoice_id': id,
          'kind': 'adjustment',
          'mode': 'adjustment',
          'description': note,
          'quantity': 1000,
          'rate_cents': adjustmentCents,
          'amount_cents': adjustmentCents,
        });
      }
      _money(total);
      await tx.update(
        'invoices',
        {'due_date': dueDate, 'total_cents': total},
        where: 'id=?',
        whereArgs: [id],
      );
      await _audit(
        tx,
        existing.isEmpty ? 'draft_created' : 'draft_updated',
        'invoice',
        id,
        'Billing period $period; total $total centavos.',
      );
      return id;
    });
  }

  Future<void> finalizeInvoice(int id) => _db.transaction((tx) async {
    final invoice = await _require(tx, 'invoices', id);
    if (invoice['status'] == 'final') return;
    final lines = await tx.query(
      'lines',
      where: 'invoice_id=?',
      whereArgs: [id],
    );
    final readings = await tx.query(
      'readings',
      where: 'invoice_id=?',
      whereArgs: [id],
    );
    for (final line in lines.where((l) => l['mode'] == 'metered')) {
      if (!readings.any((r) => r['kind'] == line['kind'])) {
        _fail('Enter the ${line['kind']} reading before finalizing this bill.');
      }
    }
    final earlier = await tx.rawQuery(
      '''SELECT DISTINCT i.id FROM invoices i JOIN lines l ON l.invoice_id=i.id
      WHERE i.room_id=? AND i.period<? AND i.status='draft' AND l.mode='metered' LIMIT 1''',
      [invoice['room_id'], invoice['period']],
    );
    if (earlier.isNotEmpty) {
      _fail(
        'Finalize this room’s earlier meter bill first, then review this draft’s readings.',
      );
    }
    for (final reading in readings) {
      final previous = await tx.rawQuery(
        '''SELECT r.current_value FROM readings r JOIN invoices i ON i.id=r.invoice_id
        WHERE r.room_id=? AND r.kind=? AND r.period<? AND i.status='final' ORDER BY r.period DESC LIMIT 1''',
        [reading['room_id'], reading['kind'], reading['period']],
      );
      if (previous.isNotEmpty &&
          previous.first['current_value'] != reading['previous_value']) {
        _fail(
          'A previous bill was finalized after this draft. Review and save the readings again.',
        );
      }
      final later = await tx.rawQuery(
        '''SELECT r.id FROM readings r JOIN invoices i ON i.id=r.invoice_id
        WHERE r.room_id=? AND r.kind=? AND r.period>? AND i.status='final' LIMIT 1''',
        [reading['room_id'], reading['kind'], reading['period']],
      );
      if (later.isNotEmpty) {
        _fail(
          'A later meter bill is already finalized. Historical readings cannot be inserted.',
        );
      }
    }
    if (lines.length < 3 || !lines.any((l) => l['kind'] == 'rent')) {
      _fail('This draft is incomplete. Review it before finalizing.');
    }
    final total = lines.fold<int>(
      0,
      (sum, l) => sum + (l['amount_cents'] as int),
    );
    if (total != invoice['total_cents']) {
      _fail('The bill total does not match its charges. Review the draft.');
    }
    await tx.update(
      'invoices',
      {'status': 'final', 'finalized_at': _now()},
      where: 'id=?',
      whereArgs: [id],
    );
    await _audit(
      tx,
      'finalized',
      'invoice',
      id,
      'Finalized ${invoice['reference']}; rates and amounts are locked.',
    );
  });

  static Future<int> _paid(DatabaseExecutor tx, int invoiceId) async {
    final rows = await tx.rawQuery(
      '''SELECT COALESCE(SUM(a.amount_cents),0) AS amount FROM allocations a
      JOIN payments p ON p.id=a.payment_id WHERE a.invoice_id=? AND p.reversed_at IS NULL''',
      [invoiceId],
    );
    return rows.first['amount'] as int;
  }

  Future<int> recordPayment({
    required int invoiceId,
    required int amountCents,
    required String date,
    required String method,
    required String requestId,
    String reference = '',
    String notes = '',
  }) async {
    _money(amountCents, positive: true);
    _date(date);
    if (!['Cash', 'GCash', 'Bank transfer', 'Other'].contains(method)) {
      _fail('Choose a supported payment method.');
    }
    final request = _text(requestId, required: true, limit: 200);
    final validReference = _text(reference, limit: 500);
    final validNotes = _text(notes);
    return _db.transaction((tx) async {
      final previous = await tx.query(
        'payments',
        where: 'request_id=?',
        whereArgs: [request],
      );
      if (previous.isNotEmpty) {
        final payment = previous.first;
        final allocation = await tx.query(
          'allocations',
          where: 'payment_id=?',
          whereArgs: [payment['id']],
        );
        if (payment['amount_cents'] != amountCents ||
            payment['date'] != date ||
            payment['method'] != method ||
            payment['reference'] != validReference ||
            payment['notes'] != validNotes ||
            allocation.length != 1 ||
            allocation.first['invoice_id'] != invoiceId) {
          _fail(
            'This payment request was already used for a different transaction. Reopen the payment form.',
          );
        }
        return payment['id'] as int;
      }
      final invoice = await _require(tx, 'invoices', invoiceId);
      if (invoice['status'] != 'final') {
        _fail('Finalize the bill before recording a payment.');
      }
      final balance =
          (invoice['total_cents'] as int) - await _paid(tx, invoiceId);
      if (amountCents > balance) {
        _fail('The payment exceeds the bill’s remaining balance.');
      }
      final id = await tx.insert('payments', {
        'date': date,
        'amount_cents': amountCents,
        'method': method,
        'reference': validReference,
        'notes': validNotes,
        'request_id': request,
        'reversed_at': null,
        'reversal_reason': null,
      });
      await tx.insert('allocations', {
        'payment_id': id,
        'invoice_id': invoiceId,
        'amount_cents': amountCents,
      });
      await _audit(
        tx,
        'recorded',
        'payment',
        id,
        '$amountCents centavos applied to ${invoice['reference']} via $method on $date.',
      );
      return id;
    });
  }

  Future<void> reversePayment(int id, String reason) async {
    final validReason = _text(reason, required: true);
    await _db.transaction((tx) async {
      final payment = await _require(tx, 'payments', id);
      if (payment['reversed_at'] != null) {
        _fail('This payment has already been reversed.');
      }
      await tx.update(
        'payments',
        {'reversed_at': _now(), 'reversal_reason': validReason},
        where: 'id=?',
        whereArgs: [id],
      );
      await _audit(
        tx,
        'reversed',
        'payment',
        id,
        '${payment['amount_cents']} centavos reversed. Reason: $validReason',
      );
    });
  }

  Future<void> settleDeposit({
    required int tenancyId,
    required String kind,
    required int amountCents,
    required String date,
    required String notes,
  }) async {
    _money(amountCents, positive: true);
    _date(date);
    if (!['received', 'refund', 'deduction'].contains(kind)) {
      _fail('Choose a valid deposit transaction.');
    }
    final validNotes = _text(notes, required: true);
    await _db.transaction((tx) async {
      final tenancy = await _require(tx, 'tenancies', tenancyId);
      if (date.compareTo(tenancy['move_in'] as String) < 0) {
        _fail('Deposit transactions cannot be dated before move-in.');
      }
      if (kind != 'received' && tenancy['move_out'] == null) {
        _fail(
          'Record the tenant’s move-out before refunding or deducting their security deposit.',
        );
      }
      final rows = await tx.rawQuery(
        "SELECT COALESCE(SUM(CASE WHEN kind='received' THEN amount_cents ELSE -amount_cents END),0) AS amount FROM deposits WHERE tenancy_id=?",
        [tenancyId],
      );
      final balance = rows.first['amount'] as int;
      if (kind != 'received' && amountCents > balance) {
        _fail('This amount exceeds the security deposit held.');
      }
      if (kind == 'received') _money(balance + amountCents);
      final id = await tx.insert('deposits', {
        'tenancy_id': tenancyId,
        'kind': kind,
        'amount_cents': amountCents,
        'date': date,
        'notes': validNotes,
      });
      await _audit(
        tx,
        kind,
        'deposit',
        id,
        '$amountCents centavos. $validNotes',
      );
    });
  }

  Future<void> saveSettings(Map<String, String> values) =>
      _db.transaction((tx) async {
        for (final entry in values.entries) {
          _text(entry.key, required: true, limit: 100);
          _text(entry.value);
          if (entry.key == 'meter_day') _dueDay(int.tryParse(entry.value) ?? 0);
          if (['dark_mode', 'reminders'].contains(entry.key) &&
              !['true', 'false'].contains(entry.value)) {
            _fail('Invalid settings value.');
          }
          await tx.insert('settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<Map<String, dynamic>> exportData() => _db.transaction((tx) async {
    final tables = <String, dynamic>{};
    for (final table in _tables) {
      tables[table] = await tx.query(
        table,
        orderBy: table == 'settings' ? 'key' : 'id',
      );
    }
    return {
      'format': 'bahay-rent-backup',
      'version': 1,
      'created_at': _now(),
      'tables': tables,
    };
  });

  static Map<String, List<Row>> _decodeBackup(Map<String, dynamic> backup) {
    if (backup['format'] != 'bahay-rent-backup' ||
        backup['version'] != 1 ||
        backup['tables'] is! Map ||
        backup['created_at'] is! String ||
        DateTime.tryParse(backup['created_at'] as String) == null) {
      _fail(
        'This is not a supported Bahay Rent backup. Your current records were not changed.',
      );
    }
    final source = backup['tables'] as Map;
    if (source.length != _tables.length || !_tables.every(source.containsKey)) {
      _fail('The backup is missing required tables.');
    }
    final result = <String, List<Row>>{};
    var rowCount = 0;
    for (final table in _tables) {
      if (source[table] is! List) _fail('Invalid backup table: $table.');
      final rows = <Row>[];
      for (final value in source[table] as List) {
        if (value is! Map ||
            value.keys.any((k) => k is! String) ||
            value.length != _columns[table]!.length ||
            !_columns[table]!.every(value.containsKey)) {
          _fail('Invalid columns in backup table: $table.');
        }
        final row = Map<String, dynamic>.from(value);
        for (final field in row.entries) {
          if (field.value is! String &&
              field.value is! int &&
              field.value != null) {
            _fail('Invalid value in $table.${field.key}.');
          }
          if (field.value is String && (field.value as String).length > 30000) {
            _fail('Backup text is too long.');
          }
          if (field.value is int &&
              ((field.value as int) > _maximum ||
                  (field.value as int) < -_maximum)) {
            _fail('Backup number is out of range.');
          }
        }
        if (table != 'settings' &&
            (row['id'] is! int || (row['id'] as int) <= 0)) {
          _fail('Invalid record identifier in $table.');
        }
        rows.add(row);
        rowCount++;
        if (rowCount > 300000) {
          _fail('This backup exceeds the supported record limit.');
        }
      }
      result[table] = rows;
    }
    return result;
  }

  static Future<void> _insertTables(
    DatabaseExecutor db,
    Map<String, List<Row>> tables,
  ) async {
    // Insert parents before children. Foreign-key checks stay enabled throughout.
    for (final table in _tables) {
      for (final row in tables[table]!) {
        await db.insert(table, row);
      }
    }
  }

  Future<void> validateBackup(Map<String, dynamic> backup) async {
    final tables = _decodeBackup(backup);
    Database? candidate;
    try {
      candidate = await _factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      await candidate.transaction((tx) async {
        await _createSchema(tx);
        await _insertTables(tx, tables);
        await _validateLedger(tx, tables);
      });
    } catch (error) {
      if (error is StateError) rethrow;
      _fail(
        'Backup validation failed. The file is incomplete or contains inconsistent records. Your current data is safe.',
      );
    } finally {
      await candidate?.close();
    }
  }

  static Future<void> _validateLedger(
    DatabaseExecutor db,
    Map<String, List<Row>> tables,
  ) async {
    final intFields = <String, List<String>>{
      'rooms': ['rent_cents', 'electricity_rate', 'water_rate', 'archived'],
      'tenancies': ['room_id', 'tenant_id', 'rent_cents', 'due_day'],
      'invoices': ['tenancy_id', 'room_id', 'total_cents'],
      'lines': ['invoice_id', 'quantity', 'rate_cents', 'amount_cents'],
      'readings': ['room_id', 'previous_value', 'current_value', 'invoice_id'],
      'payments': ['amount_cents'],
      'allocations': ['payment_id', 'invoice_id', 'amount_cents'],
      'deposits': ['tenancy_id', 'amount_cents'],
      'audit': ['entity_id'],
    };
    for (final table in _tables) {
      for (final row in tables[table]!) {
        for (final field in intFields[table] ?? <String>[]) {
          if (row[field] is! int) {
            _fail('Expected an integer in $table.$field.');
          }
        }
        for (final field in row.keys.where(
          (k) => k != 'id' && !(intFields[table] ?? []).contains(k),
        )) {
          if (row[field] == null &&
              [
                'move_out',
                'finalized_at',
                'reversed_at',
                'reversal_reason',
              ].contains(field)) {
            continue;
          }
          if (row[field] is! String) _fail('Expected text in $table.$field.');
        }
      }
    }
    for (final row in tables['tenancies']!) {
      _date(row['move_in'] as String);
      if (row['move_out'] != null) _date(row['move_out'] as String);
    }
    final overlaps = await db.rawQuery(
      '''SELECT a.id FROM tenancies a JOIN tenancies b ON a.id<b.id
      AND (a.room_id=b.room_id OR a.tenant_id=b.tenant_id)
      AND (a.move_out IS NULL OR a.move_out>b.move_in)
      AND (b.move_out IS NULL OR b.move_out>a.move_in) LIMIT 1''',
    );
    if (overlaps.isNotEmpty) {
      _fail('The backup has overlapping tenant assignments.');
    }
    for (final row in tables['invoices']!) {
      _period(row['period'] as String);
      _date(row['due_date'] as String);
      final tenancy = tables['tenancies']!
          .where((t) => t['id'] == row['tenancy_id'])
          .single;
      if (tenancy['room_id'] != row['room_id']) {
        _fail('A bill is assigned to the wrong room.');
      }
      final start = DateTime.parse('${row['period']}-01');
      final end = isoDate(DateTime(start.year, start.month + 1, 0));
      if ((tenancy['move_in'] as String).compareTo(end) > 0 ||
          (tenancy['move_out'] != null &&
              (tenancy['move_out'] as String).compareTo(
                    '${row['period']}-01',
                  ) <=
                  0)) {
        _fail('A bill falls outside its tenant’s occupancy.');
      }
      if (DateTime.tryParse(row['created_at'] as String) == null ||
          (row['finalized_at'] != null &&
              DateTime.tryParse(row['finalized_at'] as String) == null)) {
        _fail('A bill has an invalid timestamp.');
      }
      final lines = tables['lines']!
          .where((l) => l['invoice_id'] == row['id'])
          .toList();
      if (![
        'rent',
        'electricity',
        'water',
      ].every((kind) => lines.any((l) => l['kind'] == kind))) {
        _fail('A bill is missing required charges.');
      }
      if (lines.fold<int>(0, (sum, l) => sum + (l['amount_cents'] as int)) !=
          row['total_cents']) {
        _fail('A bill’s total does not match its charges.');
      }
      for (final line in lines) {
        final mode = line['mode'];
        final kind = line['kind'];
        if ((kind == 'rent' && mode != 'rent') ||
            (kind == 'adjustment' && mode != 'adjustment') ||
            (['electricity', 'water'].contains(kind) &&
                !['metered', 'fixed', 'shared'].contains(mode))) {
          _fail('A charge has an invalid billing mode.');
        }
        if (mode != 'metered' && line['quantity'] != 1000) {
          _fail('A fixed charge has an invalid quantity.');
        }
        if (kind == 'adjustment') {
          if (line['quantity'] != 1000 ||
              line['rate_cents'] != line['amount_cents'] ||
              (line['description'] as String).trim().isEmpty) {
            _fail('An adjustment is invalid.');
          }
        } else if (_charge(
              line['quantity'] as int,
              line['rate_cents'] as int,
            ) !=
            line['amount_cents']) {
          _fail(
            'A utility or rent charge does not match its quantity and rate.',
          );
        }
        final reads = tables['readings']!
            .where((r) => r['invoice_id'] == row['id'] && r['kind'] == kind)
            .toList();
        if (mode == 'metered') {
          if (row['status'] == 'final' && reads.length != 1) {
            _fail('A finalized bill is missing a meter reading.');
          }
          if (reads.isEmpty &&
              (line['quantity'] != 0 || line['amount_cents'] != 0)) {
            _fail('An incomplete reading has a charge.');
          }
          if (reads.isNotEmpty &&
              (reads.single['current_value'] as int) -
                      (reads.single['previous_value'] as int) !=
                  line['quantity']) {
            _fail('A meter consumption does not match the billed quantity.');
          }
        } else if (reads.isNotEmpty) {
          _fail(
            'A fixed or shared charge contains an unexpected meter reading.',
          );
        }
      }
    }
    for (final reading in tables['readings']!) {
      _period(reading['period'] as String);
      final invoice = tables['invoices']!
          .where((i) => i['id'] == reading['invoice_id'])
          .single;
      if (reading['room_id'] != invoice['room_id'] ||
          reading['period'] != invoice['period']) {
        _fail('A meter reading is linked to the wrong bill.');
      }
      if (invoice['status'] == 'final') {
        final previous = await db.rawQuery(
          '''SELECT r.current_value FROM readings r JOIN invoices i ON i.id=r.invoice_id
          WHERE r.room_id=? AND r.kind=? AND r.period<? AND i.status='final' ORDER BY r.period DESC LIMIT 1''',
          [reading['room_id'], reading['kind'], reading['period']],
        );
        if (previous.isNotEmpty &&
            previous.first['current_value'] != reading['previous_value']) {
          _fail('The backup has a broken meter reading sequence.');
        }
      }
    }
    for (final payment in tables['payments']!) {
      _date(payment['date'] as String);
      if (payment['reversed_at'] != null &&
          DateTime.tryParse(payment['reversed_at'] as String) == null) {
        _fail('A payment reversal has an invalid timestamp.');
      }
      final allocations = tables['allocations']!
          .where((a) => a['payment_id'] == payment['id'])
          .toList();
      if (allocations.isEmpty ||
          allocations.fold<int>(
                0,
                (sum, a) => sum + (a['amount_cents'] as int),
              ) !=
              payment['amount_cents']) {
        _fail('A payment does not match its allocations.');
      }
    }
    for (final invoice in tables['invoices']!) {
      final allocations = tables['allocations']!.where(
        (a) => a['invoice_id'] == invoice['id'],
      );
      if (allocations.isNotEmpty && invoice['status'] != 'final') {
        _fail('A draft invoice has payment allocations.');
      }
      if (await _paid(db, invoice['id'] as int) >
          (invoice['total_cents'] as int)) {
        _fail('A bill is overpaid in this backup.');
      }
    }
    final depositBalances = <int, int>{};
    for (final deposit in [
      ...tables['deposits']!,
    ]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int))) {
      _date(deposit['date'] as String);
      final id = deposit['tenancy_id'] as int;
      final tenancy = tables['tenancies']!.where((t) => t['id'] == id).single;
      if ((deposit['date'] as String).compareTo(tenancy['move_in'] as String) <
          0) {
        _fail('A deposit predates move-in.');
      }
      if (deposit['kind'] != 'received' && tenancy['move_out'] == null) {
        _fail('A deposit was settled without a move-out record.');
      }
      final balance =
          (depositBalances[id] ?? 0) +
          (deposit['kind'] == 'received' ? 1 : -1) *
              (deposit['amount_cents'] as int);
      if (balance < 0 || balance > _maximum) {
        _fail('The backup contains an invalid security deposit balance.');
      }
      depositBalances[id] = balance;
    }
    for (final entry in tables['settings']!) {
      if ((entry['key'] as String).isEmpty) _fail('A settings key is empty.');
      if (entry['key'] == 'meter_day') {
        _dueDay(int.tryParse(entry['value'] as String) ?? 0);
      }
      if (['dark_mode', 'reminders'].contains(entry['key']) &&
          !['true', 'false'].contains(entry['value'])) {
        _fail('A settings value is invalid.');
      }
    }
    for (final audit in tables['audit']!) {
      if (DateTime.tryParse(audit['created_at'] as String) == null) {
        _fail('An audit timestamp is invalid.');
      }
    }
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      _fail('The backup contains broken record references.');
    }
  }

  Future<void> restoreData(Map<String, dynamic> backup) async {
    // Clone before awaiting so callers cannot change a backup between validation and restoration.
    final copy = jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;
    await validateBackup(copy);
    final tables = _decodeBackup(copy);
    await _db.transaction((tx) async {
      await tx.update('restore_guard', {'enabled': 1}, where: 'id=1');
      for (final table in _tables.reversed) {
        await tx.delete(table);
      }
      await _insertTables(tx, tables);
      await _validateLedger(tx, tables);
      for (final entry in defaults.entries) {
        await tx.insert('settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await tx.update('restore_guard', {'enabled': 0}, where: 'id=1');
      await _audit(
        tx,
        'restored',
        'backup',
        0,
        'Validated backup from ${copy['created_at']} restored by explicit user action.',
      );
    });
  }
}
