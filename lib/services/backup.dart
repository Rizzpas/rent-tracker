import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'local_time.dart';

/// Storage Access Framework on Android: backups leave the app's private folder.
class BackupService {
  static const maxBytes = 32 * 1024 * 1024;
  static const iterations = 210000;
  static const _aad = 'bahay-rent-encrypted:1';

  static Future<File> _safetyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/before-last-restore.json');
  }

  static Future<bool> hasSafetyCopy() async => (await _safetyFile()).exists();

  static Future<bool> exportSafetyCopy(
    RentalRepository repository, {
    String? password,
  }) async {
    final file = await _safetyFile();
    if (!await file.exists()) {
      throw const FormatException(
        'No pre-restore safety copy has been created yet.',
      );
    }
    final payload =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await repository.validateBackup(payload);
    final bytes = await compute(_encodeBackup, <String, dynamic>{
      'payload': payload,
      'password': password,
    });
    return saveBytes(
      bytes,
      'Bahay-Rent-before-last-restore.brbackup',
      title: 'Save records from before the last restore',
    );
  }

  static Future<bool> exportBackup(
    RentalRepository repository, {
    String? password,
  }) async {
    final payload = await repository.exportData();
    final bytes = await compute(_encodeBackup, <String, dynamic>{
      'payload': payload,
      'password': password,
    });
    final now = manilaNow();
    final saved = await saveBytes(
      bytes,
      'Bahay-Rent-${isoDate(now)}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.brbackup',
      title: 'Save your rental backup',
    );
    if (saved) {
      await repository.saveSettings({
        'last_backup': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return saved;
  }

  static Future<bool> importBackup(
    RentalRepository repository,
    BuildContext context, {
    String? password,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a Bahay Rent backup',
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (picked == null) return false;
    final file = picked.files.single;
    if (file.size > maxBytes) {
      throw const FormatException('This backup is too large (maximum 32 MB).');
    }
    if (file.path == null) {
      throw const FormatException(
        'Please choose a backup saved on this device.',
      );
    }
    final bytes = await File(file.path!).readAsBytes();
    final envelope = _readEnvelope(bytes);
    if (envelope['encrypted'] == true && password == null) {
      if (!context.mounted) return false;
      password = await askPassword(
        context,
        title: 'Unlock backup',
        description: 'Enter the password used when this backup was saved.',
        confirm: false,
      );
      if (password == null) return false;
    }
    final payload = await compute(_decodeBackup, <String, dynamic>{
      'bytes': bytes,
      'password': password,
    });
    await repository.validateBackup(payload);
    final current = await repository.load();
    if (!context.mounted) return false;
    final tables = payload['tables'] as Map;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace records with this backup?'),
        content: SingleChildScrollView(
          child: Text(
            'Backup created: ${formatManilaTimestamp(payload['created_at'] as String)}\n\n'
            '${(tables['rooms'] as List).length} rooms · '
            '${(tables['tenants'] as List).length} tenants\n'
            '${(tables['invoices'] as List).length} bills · '
            '${(tables['payments'] as List).length} payments\n\n'
            'Your current ${current.rooms.length} rooms and '
            '${current.invoices.length} bills will be replaced. '
            'Records added after the backup will no longer appear. '
            'Save a backup of your current records first if you need to keep them. '
            'A temporary safety copy will also be kept on this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Replace records'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    // Fail before replacement if the safety copy cannot be written.
    await (await _safetyFile()).writeAsString(
      jsonEncode(await repository.exportData()),
      flush: true,
    );
    await repository.restoreData(payload);
    return true;
  }

  static Future<bool> saveBytes(
    Uint8List bytes,
    String name, {
    String title = 'Save file',
    List<String>? extensions,
  }) async {
    final destination = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: name,
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
      bytes: bytes,
    );
    if (destination == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(destination).writeAsBytes(bytes, flush: true);
    }
    return true;
  }

  static Future<String?> askPassword(
    BuildContext context, {
    required String title,
    required String description,
    required bool confirm,
  }) async {
    final controller = TextEditingController();
    final confirmation = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(description),
                const SizedBox(height: 20),
                TextFormField(
                  controller: controller,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                  ),
                  validator: (value) => (value ?? '').length < (confirm ? 8 : 1)
                      ? (confirm
                            ? 'Use at least 8 characters.'
                            : 'Enter your password.')
                      : null,
                ),
                if (confirm) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmation,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Repeat password',
                    ),
                    validator: (value) => value != controller.text
                        ? 'The passwords do not match.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text);
              }
            },
            child: Text(confirm ? 'Use password' : 'Unlock'),
          ),
        ],
      ),
    );
    // Dialog animations may still reference the controllers; disposal after frame.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      controller.dispose();
      confirmation.dispose();
    });
    return result;
  }

  @visibleForTesting
  static Future<Uint8List> encode(
    Map<String, dynamic> payload, {
    String? password,
  }) => _encodeBackup({'payload': payload, 'password': password});
  @visibleForTesting
  static Future<Map<String, dynamic>> decode(
    Uint8List bytes, {
    String? password,
  }) => _decodeBackup({'bytes': bytes, 'password': password});
}

Map<String, dynamic> _readEnvelope(Uint8List bytes) {
  if (bytes.length > BackupService.maxBytes) {
    throw const FormatException('This backup is too large (maximum 32 MB).');
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value['format'] != 'bahay-rent-file' ||
        value['version'] != 1 ||
        value['encrypted'] is! bool) {
      throw const FormatException('Not a supported Bahay Rent backup file.');
    }
    return value;
  } on FormatException {
    throw const FormatException('This is not a valid Bahay Rent backup file.');
  }
}

Future<SecretKey> _backupKey(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: BackupService.iterations,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

Future<Uint8List> _encodeBackup(Map<String, dynamic> args) async {
  final payload = args['payload'] as Map<String, dynamic>;
  final password = args['password'] as String?;
  final body = utf8.encode(jsonEncode(payload));
  final envelope = <String, dynamic>{
    'format': 'bahay-rent-file',
    'version': 1,
    'encrypted': password != null,
  };
  if (password == null) {
    envelope['payload'] = payload;
    envelope['sha256'] = base64Encode((await Sha256().hash(body)).bytes);
  } else {
    if (password.length < 8) {
      throw const FormatException(
        'Use a backup password of at least 8 characters.',
      );
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _backupKey(password, salt);
    final secret = await AesGcm.with256bits().encrypt(
      body,
      secretKey: key,
      aad: utf8.encode(BackupService._aad),
    );
    envelope.addAll({
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': BackupService.iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secret.nonce),
      'ciphertext': base64Encode(secret.cipherText),
      'mac': base64Encode(secret.mac.bytes),
    });
  }
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  if (bytes.length > BackupService.maxBytes) {
    throw const FormatException('This backup exceeds the 32 MB limit.');
  }
  return bytes;
}

Future<Map<String, dynamic>> _decodeBackup(Map<String, dynamic> args) async {
  final envelope = _readEnvelope(args['bytes'] as Uint8List);
  if (envelope['encrypted'] == false) {
    final payload = envelope['payload'];
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Backup records are missing.');
    }
    final checksum = base64Encode(
      (await Sha256().hash(utf8.encode(jsonEncode(payload)))).bytes,
    );
    if (checksum != envelope['sha256']) {
      throw const FormatException('This backup was modified or damaged.');
    }
    return payload;
  }
  final password = args['password'] as String?;
  if (password == null) {
    throw const FormatException('A backup password is required.');
  }
  try {
    if (envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        envelope['iterations'] != BackupService.iterations) {
      throw const FormatException('Unsupported backup encryption.');
    }
    final salt = base64Decode(envelope['salt'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final mac = base64Decode(envelope['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid encrypted backup.');
    }
    final key = await _backupKey(password, salt);
    final body = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: key,
      aad: utf8.encode(BackupService._aad),
    );
    final payload = jsonDecode(utf8.decode(body));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup.');
    }
    return payload;
  } catch (_) {
    throw const FormatException(
      'The password is incorrect, or the backup is damaged.',
    );
  }
}
