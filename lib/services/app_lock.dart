import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class LockService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final changed = ValueNotifier<int>(0);
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );
  static Future<bool> isEnabled() async =>
      await _storage.read(key: 'pin_record') != null;
  static Future<bool> biometricsEnabled() async =>
      await _storage.read(key: 'biometrics') == 'true';

  static Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const FormatException('Choose a 6-digit PIN.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await compute(_derivePinHash, {
      'pin': pin,
      'salt': base64Encode(salt),
    });
    // Keep salt and hash in one secure-storage write. Interrupted PIN changes
    // must not leave a new salt paired with the previous hash.
    await _storage.write(
      key: 'pin_record',
      value: jsonEncode({
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
      }),
    );
    await _storage.delete(key: 'pin_failures');
    await _storage.delete(key: 'pin_until');
    changed.value++;
  }

  static Future<void> disable() async {
    for (final key in [
      'pin_record',
      'pin_failures',
      'pin_until',
      'biometrics',
    ]) {
      await _storage.delete(key: key);
    }
    changed.value++;
  }

  static Future<void> setBiometrics(bool enabled) async {
    if (enabled) {
      final authentication = LocalAuthentication();
      if (!(await authentication.canCheckBiometrics) ||
          (await authentication.getAvailableBiometrics()).isEmpty) {
        throw const FormatException(
          'Set up a fingerprint or face unlock in your phone settings first.',
        );
      }
    }
    await _storage.write(key: 'biometrics', value: '$enabled');
    changed.value++;
  }

  static Future<bool> verifyPin(String pin) async {
    final until =
        int.tryParse(await _storage.read(key: 'pin_until') ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (until > now) {
      throw FormatException(
        'Please wait ${((until - now) / 1000).ceil()} seconds before trying again.',
      );
    }
    final serialized = await _storage.read(key: 'pin_record');
    if (serialized == null) return false;
    final record = jsonDecode(serialized) as Map<String, dynamic>;
    final stored = record['hash'] as String;
    final salt = record['salt'] as String;
    final actual = await compute(_derivePinHash, {'pin': pin, 'salt': salt});
    final expected = base64Decode(stored);
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < min(actual.length, expected.length); i++) {
      difference |= actual[i] ^ expected[i];
    }
    if (difference == 0) {
      await _storage.delete(key: 'pin_failures');
      await _storage.delete(key: 'pin_until');
      return true;
    }
    final failures =
        (int.tryParse(await _storage.read(key: 'pin_failures') ?? '') ?? 0) + 1;
    await _storage.write(key: 'pin_failures', value: '$failures');
    if (failures >= 5) {
      final seconds = min(1800, 30 * (1 << min(6, failures - 5)));
      await _storage.write(key: 'pin_until', value: '${now + seconds * 1000}');
    }
    return false;
  }

  static Future<bool> authenticateBiometric() async {
    if (!await biometricsEnabled()) return false;
    final result = await LocalAuthentication().authenticate(
      localizedReason: 'Unlock your rental records',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
    if (result) {
      await _storage.delete(key: 'pin_failures');
      await _storage.delete(key: 'pin_until');
    }
    return result;
  }

  static Future<bool> confirmIdentity(BuildContext context) async {
    if (!await isEnabled()) return true;
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _UnlockForm(
                onUnlocked: () => Navigator.pop(dialogContext, true),
                onCancel: () => Navigator.pop(dialogContext, false),
              ),
            ),
          ),
        ) ??
        false;
  }
}

Future<List<int>> _derivePinHash(Map<String, String> values) async {
  final key = await LockService._kdf.deriveKeyFromPassword(
    password: values['pin']!,
    nonce: base64Decode(values['salt']!),
  );
  return key.extractBytes();
}

/// Use in MaterialApp.builder around its Navigator, so lock covers open dialogs.
class AppLock extends StatefulWidget {
  final Widget child;
  const AppLock({super.key, required this.child});
  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool _loading = true, _enabled = false, _locked = false;
  String? _error;
  DateTime? _backgroundAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LockService.changed.addListener(_reload);
    _reload();
  }

  Future<void> _reload() async {
    try {
      final enabled = await LockService.isEnabled();
      if (!mounted) return;
      setState(() {
        if (_loading) _locked = enabled;
        if (!enabled) _locked = false;
        _enabled = enabled;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Your phone could not open secure storage. Restart your phone or try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundAt ??= DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (_enabled &&
          _backgroundAt != null &&
          DateTime.now().difference(_backgroundAt!) >=
              const Duration(seconds: 30)) {
        setState(() => _locked = true);
      }
      _backgroundAt = null;
    }
  }

  @override
  void dispose() {
    LockService.changed.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Offstage(
        offstage: _loading || _locked || _error != null,
        child: widget.child,
      ),
      if (_loading || _locked || _error != null)
        Positioned.fill(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline, size: 48),
                              const SizedBox(height: 24),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _reload,
                                child: const Text('Try again'),
                              ),
                            ],
                          )
                        : _UnlockForm(
                            onUnlocked: () => setState(() => _locked = false),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _UnlockForm extends StatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback? onCancel;
  const _UnlockForm({required this.onUnlocked, this.onCancel});
  @override
  State<_UnlockForm> createState() => _UnlockFormState();
}

class _UnlockFormState extends State<_UnlockForm> {
  final _pin = TextEditingController();
  bool _busy = false, _biometrics = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    LockService.biometricsEnabled()
        .then((enabled) {
          if (mounted) setState(() => _biometrics = enabled);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock({bool biometric = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final success = biometric
          ? await LockService.authenticateBiometric()
          : await LockService.verifyPin(_pin.text);
      if (!mounted) return;
      if (success) {
        widget.onUnlocked();
      } else {
        setState(
          () => _error = biometric
              ? 'Use your PIN to unlock.'
              : 'Incorrect PIN. Please try again.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not unlock. Please try your PIN.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.lock_outline_rounded, size: 56),
      const SizedBox(height: 24),
      Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text(
        'Enter your PIN to open your rental records.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      TextField(
        controller: _pin,
        obscureText: true,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: '6-digit PIN',
          errorText: _error,
        ),
        onSubmitted: (_) => _unlock(),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : () => _unlock(),
          child: Text(_busy ? 'Checking…' : 'Unlock'),
        ),
      ),
      if (_biometrics)
        TextButton.icon(
          onPressed: _busy ? null : () => _unlock(biometric: true),
          icon: const Icon(Icons.fingerprint),
          label: const Text('Use fingerprint or face'),
        ),
      if (widget.onCancel != null)
        TextButton(
          onPressed: _busy ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
    ],
  );
}
