import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upa_renta/services/backup.dart';

void main() {
  test('plain backup uses upa-renta-file format and verifies SHA-256', () async {
    final payload = <String, dynamic>{
      'format': 'upa-renta-backup',
      'version': 1,
      'tables': {
        'rooms': [
          {'id': 1, 'name': 'Sampaguita'},
        ],
      },
    };
    final bytes = await BackupService.encode(payload);
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(envelope['format'], 'upa-renta-file');
    expect(envelope['encrypted'], isFalse);
    expect(await BackupService.decode(bytes), payload);
  });

  test('encrypted backup decodes legacy bahay-rent-file AAD seamlessly', () async {
    final payload = <String, dynamic>{
      'format': 'bahay-rent-backup',
      'version': 1,
      'tables': {'rooms': <Object>[]},
    };
    final plain = utf8.encode(jsonEncode(payload));
    final salt = List<int>.filled(16, 7);
    final nonce = List<int>.filled(12, 9);
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: BackupService.iterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: 'LegacyPassword123',
      nonce: salt,
    );
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode('bahay-rent-encrypted:1'),
    );
    final legacyEnvelope = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'bahay-rent-file',
          'version': 1,
          'encrypted': true,
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': BackupService.iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
    final decoded = await BackupService.decode(
      legacyEnvelope,
      password: 'LegacyPassword123',
    );
    expect(decoded, payload);
  });

  testWidgets('askPassword validates length and confirmation match', (
    tester,
  ) async {
    String? returned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                returned = await BackupService.askPassword(
                  context,
                  title: 'Protect backup',
                  description: 'Enter password',
                  confirm: true,
                );
              },
              child: const Text('Ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'StrongPass88');
    await tester.enterText(fields.at(1), 'Different88');
    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'StrongPass88');
    await tester.tap(find.text('Use password'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(returned, 'StrongPass88');
  });
}
