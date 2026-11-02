# Upa Renta — Product & Technical Requirements

## 1. Project Overview

**Upa Renta** (`upa_renta`) is an offline-first mobile application for landlords managing small residential rental properties in the Philippines. It tracks rooms, tenant agreements, monthly rent, electricity and water bills, payments, receipts, and outstanding balances completely offline on Android phones—including entry-level / low-end devices.

### Core Technical Requirements
- **Framework**: Flutter (Dart)
- **Database**: Local SQLite (`upa_renta.db`) with transactional integrity, secondary indexes, and immutability triggers
- **Architecture**: 100% offline-first (zero `INTERNET` permission in release builds)
- **Target Platform**: Android 7.0+ (API 24–36), optimized for smooth 60 FPS operation on low-RAM / entry-level Android phones
- **Currency**: Philippine Peso (`₱`), exact integer centavos
- **Timezone**: `Asia/Manila` (`UTC+08:00`) for all calendar dates, due-date schedules, collection windows, and notifications

## 2. Asia/Manila Due Dates & Custom Date Pickers

- All dates and billing months operate strictly in `Asia/Manila` (`UTC+08:00`), independent of UTC midnight offsets.
- Tenant agreements and meter reminder schedules support due days `1–31`, with 1-tap presets for:
  - **`5th`** of the month
  - **`15th`** of the month
  - **`30th`** of the month (automatically clamped to Feb 28 in common years and Feb 29 in leap years)
  - **`End of month` (`31`)** (31st on 31-day months, 30th on April/June/September/November, Feb 29 in leap years, and Feb 28 in common years)
- Date and month inputs use Upa Renta's custom thumb-friendly bottom-sheet pickers (`showUpaDatePicker`, `showUpaMonthPicker`, `DateInput`, `DueDaySelector`) rather than stock Material dialogs.

## 3. Collections Day (`< 3 Taps`)

Provide a dedicated **Collections Day** screen reachable in **1 tap** from the persistent `Collect` action in the top app bar (as well as from Home and Payments):
- Lists everyone with a finalized bill **due this week** (`[today, today + 6 days]` in `Asia/Manila`), plus **overdue follow-ups**, **unbilled/draft stays due this week**, and **payments collected today**.
- Provides 1-tap quick payment method selection (`Cash` default, `GCash`, `Bank transfer`, `Other`).
- **Under-3-tap completion**:
  1. Tap **`Collect`** in the top bar.
  2. Tap **`Pay & receipt`** on the tenant's card to record full payment with idempotency protection and immediately open the generated PDF receipt (**2 taps total**), or tap **`Record paid`** followed by **`Receipt`** in the **Collected today** list.

## 4. Home Dashboard, Rooms, Billing & Payments

- **Home**: Displays payments received in the selected month, billed charges, unpaid balances, Collections Day summary banner, occupancy counts, draft/finalized bill counts, room-by-room statuses, overdue alerts, and upcoming deadlines.
- **Rooms & Tenants**: Add/edit/archive rooms, configure metered/fixed/shared electricity and water rates, assign/edit/move out tenants without losing historical records, and track/settle security deposits separately from rent.
- **Monthly Billing**: Enter meter readings (auto-carrying forward the previous finalized reading) or shared charges, apply explained adjustments/discounts, preview charges live, save drafts, and lock finalized bills.
- **Payments**: Record full, partial, or multiple payments per bill, generate offline PDF receipts in 1 tap, and reverse erroneous payments with mandatory audit reasons.

## 5. Offline Documents, Reminders, Security & Backups

- **Documents**: Offline PDF statements, payment receipts, filtered financial reports, and formula-neutralized CSV exports using bundled Noto Sans fonts.
- **Notifications**: Local Android notifications in `Asia/Manila` time with explicit high-importance channel creation, Android 13+ permission handling, boot-completed rescheduling, R8 keep rules, and a 1-tap **Send test notification** verification action.
- **App Security**: Optional 6-digit salted PBKDF2 PIN and biometric unlock with failed-attempt throttling and 30-second background relock.
- **Backups**: Checksummed plaintext and `AES-GCM-256` password-encrypted `.urbackup` files (with backward compatibility for `.brbackup`), full relational/financial validation before restore, and automatic pre-restore safety copies.
- **Low-End Android Optimization & Module Unit Tests**: Zero `BackdropFilter` GPU blurs, `O(1)` indexed `AppData` lookups, lazy list builders, R8 shrinking, 360px @ 1.3× text-scale layout safety, and unit/widget tests covering every module in `lib/`.
