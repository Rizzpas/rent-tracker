# Verification record — Upa Renta

Verified on 3 November 2026 (`Asia/Manila`), using Flutter 3.47.9, Dart 3.13.7, JDK 17, Android SDK 36, and a Windows host.

## Automated checks

- `flutter analyze`: **No issues found.**
- `flutter test`: **93 tests passed** across 16 test suites covering every module in `lib/`.
- Screenshot export harness (`flutter test test/preview_test.dart --dart-define=EXPORT_PREVIEWS=true`): **passed**, exporting all 7 visual screens (`home.png`, `collections.png`, `home-details.png`, `rooms.png`, `billing.png`, `payments.png`, `more.png`) to `deliverables/screenshots/`. Screenshot records are isolated test fixtures and are never included in the installed app.

| Module / Area | Test Suite(s) | Key Verified Invariants |
| --- | --- | --- |
| `Asia/Manila` calendar & due dates (`lib/services/local_time.dart`) | `test/local_time_test.dart` | Explicit `UTC+08:00` conversion independent of host timezone; `5th`, `15th`, `30th`, and `31` (`End of month`) resolution across 31-day months, 30-day months, common February (`2026-02-28`), and leap February (`2028-02-29`); rolling 7-day collection window (`manilaCollectionWeek`, `isDueThisWeek`). |
| O(1) indexed ledger models (`lib/data/models.dart`) | `test/models_test.dart` | Cached O(1) lookups for rooms, tenancies, invoices, lines, balances, deposits, and readings; automatic cache re-indexing when list references change. |
| SQLite repository & triggers (`lib/data/repository.dart`) | `test/repository_test.dart` | 35+ regression checks: empty initial dataset; centavo & thousandth decimal parsing; overlapping tenancy rejection; metered/fixed/shared utilities; once-only centavo rounding; chronological finalization; immutable finalized snapshots; concurrent idempotent `request_id` payment deduplication; reversals; deposit ledger; `upa-renta-backup` export and backward-compatible `bahay-rent-backup` restore; `dueDateForPeriod` resolution for `5`, `15`, `30`, and `31`. |
| Local notifications (`lib/services/reminders.dart`) | `test/reminders_test.dart`, `test/services_test.dart` | High-importance Android channel creation; transient initialization failure recovery; `sendTestNotification` immediate delivery; signature deduplication; 32-notification scheduling cap; `Asia/Manila` 09:00 AM scheduling for due, overdue, draft, and `1..31` meter reminders (including February clamping). |
| Encrypted & plain backups (`lib/services/backup.dart`) | `test/backup_test.dart`, `test/services_test.dart` | `.urbackup` (`upa-renta-file`) + legacy `.brbackup` (`bahay-rent-file`) PBKDF2-HMAC-SHA256 (210,000 iterations) + AES-256-GCM encryption/decryption; SHA-256 plain checksum verification; password confirmation dialog validation. |
| Offline PDF & CSV documents (`lib/services/documents.dart`) | `test/documents_test.dart`, `test/services_test.dart` | Allocation-free `peso()` formatting; offline bundled Noto Sans TTF PDF statement & receipt generation with `Upa Renta · Created offline` footer; CSV injection/formula escaping. |
| App PIN & biometric lock (`lib/services/app_lock.dart`) | `test/app_lock_test.dart`, `test/services_test.dart` | PBKDF2 PIN hashing in secure storage; exponential backoff lockout; 30-second background auto-lock; `AppLockGate` unlock UI with `UpaRentaLogo`. |
| Custom `Asia/Manila` date & month pickers (`lib/ui/date_picker.dart`) | `test/date_picker_test.dart` | Thumb-friendly bottom-sheet calendar (`showUpaDatePicker`) with 1-tap `Today`, `5th`, `15th`, `30th`, and `End of month (28/29/30/31)` presets; `showUpaMonthPicker` 1-tap billing period switcher; `DueDaySelector` preset chips. |
| Collections Day (`<3 taps`) (`lib/ui/collections_page.dart`) | `test/collections_page_test.dart` | `CollectionsSchedule.from` week bucketing; **2-tap** end-to-end collection (`Collect` → `Pay & receipt`) and `Record paid` → `Receipt` flows; `Cash` / `GCash` / `Bank transfer` / `Other` method chips; idempotent payment protection. |
| Core UI shell, components & low-end device smoothness (`lib/app.dart`, `lib/ui/*`) | `test/common_ui_test.dart`, `test/pages_test.dart`, `test/app_flow_test.dart`, `test/ui_layout_test.dart`, `test/preview_seed_test.dart` | Zero `BackdropFilter` GPU blurs anywhere in the widget tree; single active-tab instantiation; lazy `SliverList.builder` / `ListView.builder` rendering; zero layout overflow across Home, Collections Day, Rooms, Billing, Payments, and More on a `360px` screen at `1.3×` text scale. |

## Android release artifact checks

- Deliverable APK: `deliverables/Upa-Renta-1.0.0.apk`
- `SHA-256`: `29bf0c472ee0306b01031de15815f233e182c2c0a9da520630f7bd51e720c760` (`deliverables/SHA256SUMS.txt`)
- Signing: Persistent local 3,072-bit RSA release keystore (`%LOCALAPPDATA%\UpaRenta\signing`). `apksigner verify` confirms **APK Signature Scheme v2 (`true`)**.
- Badging (`aapt dump badging`):
  - Package: `ph.uparenta.upa_renta`
  - Label: `Upa Renta`
  - Version: `1.0.0` (`versionCode='1'`)
  - SDKs: `minSdk 24` (Android 7.0), `targetSdk 36`
  - ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`
  - R8 code shrinking + resource shrinking enabled with ProGuard keep rules (`android/app/proguard-rules.pro`) and resource keep rules (`android/app/src/main/res/raw/keep.xml`) preserving `flutter_local_notifications` receivers and `@drawable/ic_notification`.
- Permissions (`aapt dump permissions`):
  - **Zero `android.permission.INTERNET` permission** in the release APK (strictly offline).
  - Declared permissions: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, and `ph.uparenta.upa_renta.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

## Target phone acceptance checklist

Complete this quick checklist when installing `Upa-Renta-1.0.0.apk` on a physical Android phone:

1. Turn off Wi-Fi and mobile data, install `Upa-Renta-1.0.0.apk`, and launch **Upa Renta**. Confirm the new adaptive emerald-and-gold house-arch icon appears on the home screen and no account or network prompt appears.
2. Add a room and assign a tenant using the **5th**, **15th**, **30th**, or **End of month** due-day chips and custom `Asia/Manila` date picker.
3. Generate and finalize a bill, then tap **Collect** in the top bar to open **Collections Day** and tap **Pay & receipt** (2 taps total) to record payment and generate the offline PDF receipt.
4. Open **More → Local reminders**, enable notifications, and tap **Send test notification** to confirm immediate status-bar notification delivery on the device.
5. Export an encrypted `.urbackup` copy outside app storage and verify restore confirmation and optional 6-digit PIN lock.
