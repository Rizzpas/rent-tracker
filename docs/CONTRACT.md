# Upa Renta — Shared Implementation Contract

- **Package & Application ID**: Dart package `upa_renta`; Android `applicationId` / `namespace` `ph.uparenta.upa_renta`; display name **Upa Renta**; default SQLite database `upa_renta.db`.
- **Units & Timezone**: All monetary amounts are integer centavos (`₱1.00 = 100`). All meter readings are integer thousandths (`1.000 = 1000`). All dates are ISO `YYYY-MM-DD` and billing periods `YYYY-MM` in `Asia/Manila` (`UTC+08:00`, no DST) via `lib/services/local_time.dart`.
- **Due-Date Schedules**: `tenancies.due_day` stores `1..31`, where `5`, `15`, `30` represent those calendar days (clamped to Feb 28/29 in February) and `31` represents **End of month** (`31` on 31-day months, `30` on Apr/Jun/Sep/Nov, `29` in leap Feb, `28` in common Feb) via `dueDateForPeriod(period, dueDay)`.

## Data & Repository (`lib/data/`)

- `AppData` (`lib/data/models.dart`) maintains an auto-refreshing `O(1)` lookup index for primary keys and foreign-key groups (`room`, `tenant`, `tenancy`, `invoice`, `payment`, `linesForInvoice`, `readingsForInvoice`, `allocationsForInvoice`, `allocationsForPayment`, `depositsForTenancy`, `tenanciesForRoom`, `invoicesForPeriod`, `activeTenancy`, `paid`, `balance`, `depositBalance`).
- `RentalRepository` (`lib/data/repository.dart`):
  - `open({DatabaseFactory? factory, String? path})`
  - `load()`, `close()`
  - `saveRoom(Row values)`, `archiveRoom(int id)`
  - `assignTenant({...})`, `updateTenant({...})`, `moveOut(int tenancyId, String date)`
  - `saveDraft({required int tenancyId, required String period, String? dueDate, ...})` — auto-resolves `dueDate` via `dueDateForPeriod(period, tenancy['due_day'])` when omitted
  - `finalizeInvoice(int id)`
  - `recordPayment({required int invoiceId, required int amountCents, required String date, required String method, required String requestId, ...})`
  - `reversePayment(int id, String reason)`
  - `settleDeposit({...})`
  - `saveSettings(Map<String, String> values)` — `meter_day` supports `1..31`
  - `exportData()`, `validateBackup(Map<String, dynamic> backup)`, `restoreData(Map<String, dynamic> backup)` — emits `format: 'upa-renta-backup'` and accepts legacy `'bahay-rent-backup'`.

## Services (`lib/services/`)

- `local_time.dart`: `manilaNow`, `manilaToday`, `isoDate`, `billingPeriod`, `daysInMonth`, `clampDayToMonth`, `dueDateForPeriod`, `endOfMonthForPeriod`, `isEndOfMonthDueDay`, `ordinalDay`, `dueDayLabel`, `formatPeriodLabel`, `formatIsoDateLabel`, `manilaCollectionWeek`, `isDueThisWeek`, `isOverdueDate`, `formatManilaTimestamp`.
- `documents.dart`: `peso`, `DocumentService.select`, `csv`, `statement`, `receipt`, `report`, `exportCsv`, `statementBytes`, `receiptBytes`.
- `reminders.dart`: `ReminderPlatform`, `AndroidReminderPlatform`, `ReminderService.initialize`, `requestPermission`, `areNotificationsEnabled`, `sendTestNotification`, `reschedule`, `plan`.
- `backup.dart`: `BackupService.encode`, `decode` (supports `'upa-renta-file'` and legacy `'bahay-rent-file'`), `exportBackup`, `exportSafetyCopy`, `importBackup`, `askPassword`.
- `app_lock.dart`: `LockService` and `AppLock`.

## UI (`lib/app.dart`, `lib/ui/`)

- `UpaRentaApp` (`lib/app.dart`): Instantiates only the active destination tab, exposes a persistent 1-tap `Collect` button in the top bar for `CollectionsScreen`, uses `showUpaMonthPicker` for billing periods, and renders zero `BackdropFilter` blur layers for 60 FPS performance on low-end Android devices.
- `collections_page.dart`: `CollectionsSchedule`, `CollectionsScreen`, `CollectionsView`, `openCollectionsDay` — `< 3` taps to list who is due this week, record full payment, and open a PDF receipt.
- `date_picker.dart`: `DateInput`, `DueDaySelector`, `UpaDatePickerSheet`, `showUpaDatePicker`, `showUpaMonthPicker`.
