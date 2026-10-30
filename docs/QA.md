# Verification record

Verified on 31 October 2026 (Asia/Manila), using Flutter 3.47.9, Dart 3.13.7, JDK 17, Android SDK 36, and a Windows host.

## Automated checks

`flutter analyze`: no issues found.

`flutter test`: 50 tests passed.

The optional screenshot harness (`test/preview_test.dart`) is skipped during the regular test suite. Its separate export run also passes; see `deliverables/screenshots/README.md` for reproduction instructions. Screenshot records are isolated test fixtures and are not included in the installed app.

| Area | Evidence |
| --- | --- |
| SQLite / financial integrity | 32 regression tests: empty first dataset; precise decimal parsing and overflow rejection; overlapping tenancy guards; metered/fixed/shared utilities; once-only centavo rounding; initial meter baseline and cross-tenant carry-forward; chronological finalization; immutable finalized rates; duplicate bill prevention; concurrent idempotent payment submissions; partial/multiple payments; reversals; separate deposit ledger; limits and failed-operation rollback; complete validated restore; invalid restore preservation; database close/reopen persistence. |
| Offline documents / backup / security | 10 tests: real PDF statement and receipt generation using bundled fonts; billing month versus cash receipt dates; room/tenant-filtered payment allocations; exclusive move-out occupancy; CSV escaping; AES-GCM round trip, wrong password and tamper rejection; plaintext backup checksum; secure PIN hashing and throttling; overdue partial, draft and meter reminder plans. |
| User flows | 4 widget tests: fresh shell and all five destinations; room creation; partial payment entry; tenant assignment → initial/current meter readings → discount → draft → confirmed finalization. Reads/writes use real SQLite through the desktop FFI driver. |
| Small-screen layouts | 4 populated page tests at 360 logical pixels and 1.3× text scale: Home, Rooms, Billing, Payments. The fresh-shell flow also checks all five destinations with larger text. |

The billing user-flow fixture verifies 34.567 kWh × ₱12.50 = ₱432.09 and 4.125 m³ × ₱35.00 = ₱144.38, with a separate ₱4,500 deposit and a ₱50 discount.

## Android artifact checks

The release APK is built and signed with a persistent local RSA release key. `apksigner verify` confirms APK Signature Scheme v2. `aapt dump badging` confirms package `ph.bahay.bahay_rent`, version 1.0.0, minimum Android API 24, and target API 36. The package includes ARM 32-bit, ARM 64-bit, and x86-64 binaries.

`aapt dump permissions` confirms there is **no INTERNET permission** in the release APK. The main manifest disables Android automatic backup and configures local-notification boot restoration, notification permission, and biometric access. Notification icon resources are explicitly retained for resource-shrunk release builds.

## Device checks still required

No physical Android phone was connected. An API 30 Android emulator was provisioned and two software-rendering boot attempts were made; it remained offline on this host, which has hardware virtualization disabled. No successful device installation or reboot test is claimed.

On the target phone, complete this acceptance checklist before relying on the app for the sole copy of property records:

1. Install the APK. Disable Wi-Fi and mobile data. Launch it for the first time; confirm no account or network prompt is required.
2. Add a room and tenant, generate and finalize a meter bill, and record partial and full payments. Check the resulting balances and PDF documents.
3. Force-stop/reopen the app and reboot the phone. Confirm records and totals persist.
4. Save PDFs and CSVs to a chosen folder; open them offline. Exercise printing and Android sharing with the phone's installed applications/services.
5. Export plaintext and password-protected backups outside app storage. Add a test record, then restore each backup. Check the explicit replacement confirmation and financial totals; export the pre-restore safety copy if needed.
6. Enable notifications, grant permission, and check due, overdue, draft and meter reminders. Reboot and verify pending schedules. Check Android battery restrictions if reminders are delayed.
7. Enable a PIN, test an incorrect PIN, relaunch the app, and test background relocking. If supported, enable and test biometric unlock.
8. Move a tenant out, refund or deduct their deposit with notes, and assign a new tenant. Confirm the outgoing tenant's bills and payments remain in history.

## Deliberate limits

- One invoice per room per billing month; there is no automatic rent proration. An incoming tenant cannot receive a second invoice for an already-finalized room/month. Review turnover agreements before finalizing that month's bill.
- A shared utility is the room's manually allocated share of the master charge, not an automatic allocation among tenants.
- SQLite uses Android private app storage. The optional app PIN does not encrypt the SQLite file. External encrypted backups provide separate password protection.
- Device print services, share destinations, biometrics, file pickers, and notification delivery have platform-specific behavior and are covered by the device checklist above.
