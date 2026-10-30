# Build an Offline Rental Management and Billing Mobile Application

## 1. Project Overview

Develop a fully functional, offline-first mobile application for a landlady who manages a small rental property in the Philippines.

The application's primary purpose is to track tenant information, calculate monthly house rent, electricity and water bills, record payments, and monitor outstanding balances.

**The application must work entirely offline.** It must not depend on an internet connection, cloud database, hosted backend, or external API for its core functionality.

### Target User
A non-technical landlady who primarily uses an Android smartphone.

### Technical Requirements
- Framework: Flutter (Dart)
- Database: SQLite with persistent local storage
- Architecture: Offline-first, with no required backend
- Target platform: Android
- Currency: Philippine Peso (₱)
- Timezone: Asia/Manila
- Design: Modern, minimal, mobile-first
- Navigation: Simple and intuitive
- Data persistence: All records must survive normal app restarts and device reboots.

## 2. Home Dashboard

Create a dashboard that provides a clear overview of rental operations.

Display:
- Total rental rooms
- Occupied and vacant rooms
- Expected monthly billing amount
- Total payments collected
- Total outstanding balance
- Number of paid, partially paid, and unpaid bills
- Overdue balances
- Upcoming payment deadlines

Include a room-by-room monthly payment summary and quick actions for recording payments, entering meter readings, and generating bills.

Allow switching between billing months.

Distinguish payments received during a selected month from charges billed for that month.

## 3. Room and Tenant Management

Allow the landlady to add, edit, and manage rooms.

Each room should contain:
- Room number or name
- Monthly rental price
- Occupancy status
- Assigned tenant
- Utility billing configuration
- Optional notes

Tenant records should contain:
- Full name
- Contact number
- Assigned room
- Move-in date
- Move-out date, if applicable
- Agreed monthly rental rate
- Security deposit paid
- Payment due date
- Optional notes

Support moving tenants out and assigning new tenants without deleting historical records.

Prevent invalid or overlapping active room assignments.

## 4. Monthly Billing

Implement automatic monthly billing calculations.

Each monthly bill must include:

**House Rent**
- Fixed monthly rent based on the tenant's agreement
- Configurable adjustments and discounts

**Electricity**
- Previous meter reading
- Current meter reading
- Automatically calculated kWh consumption
- Configurable rate per kWh
- Automatically calculated electricity bill

**Water**
- Previous meter reading
- Current meter reading
- Automatically calculated consumption
- Configurable rate per cubic meter

Support fixed and shared utility charges as alternative billing modes.

Automatically use the last valid meter reading as the next period's previous reading.

Allow the landlady to review all room readings in one monthly billing worksheet.

Prevent invalid readings and duplicate bills.

Support draft and finalized invoices. Finalized bills must preserve the rates and amounts applied at the time of billing.

## 5. Payment Management

Allow payments to be recorded completely offline.

Support:
- Full payments
- Partial payments
- Multiple payments for the same bill
- Cash payments
- GCash payments
- Bank transfers
- Other payment methods
- Payment dates
- Optional reference numbers
- Optional payment notes

Automatically calculate and update the remaining balance.

Display payment statuses:
- Paid
- Partial
- Unpaid
- Overdue

Outstanding partial payments should also be flagged as overdue when their due date passes.

Preserve every payment in a transaction history.

Provide a safe correction and reversal mechanism for incorrectly recorded transactions.

## 6. Previous Balances and Security Deposits

Automatically track outstanding balances from previous months.

Show these separately from the current month's new charges, and avoid counting previous balances twice.

Track security deposits separately from rent collection.

Support deposit refunds and authorized deductions when tenants move out.

## 7. Offline Billing Statements and Receipts

Generate billing statements and payment receipts directly on the device.

Each document should include:
- Property information
- Tenant name
- Room number
- Billing period
- Rent and utility breakdown
- Payment information
- Outstanding balance
- Due date
- Document reference number

Support:
- Offline PDF generation
- Saving PDFs to the device
- Printing through available device print services
- Sharing through the Android share menu

Generating, viewing, and saving documents must work without internet access.

Sending documents through online applications such as Messenger may require connectivity.

## 8. Offline Reminders

Implement local reminders for:
- Upcoming due dates
- Overdue bills
- Monthly meter reading schedules
- Bills awaiting finalization

Use Android local notifications where supported and permitted.

Do not require cloud notification services.

## 9. Reports and History

Provide monthly and yearly summaries.

Include:
- Total rent billed
- Total electricity billed
- Total water billed
- Actual payments collected
- Outstanding balances
- Occupancy records
- Historical bills and payments

Allow the landlady to filter reports by month, year, room, and tenant.

Support offline CSV and PDF exports.

## 10. Backup and Restore

Because this is an offline application, data protection is essential.

Implement:
- Manual database backup
- Exporting backups to a user-selected file location
- Importing and restoring backups
- Backup file validation
- Confirmation before replacing existing records
- Optional encrypted backups protected by a password
- Clear backup dates and restore instructions

Ensure that exported backups contain all necessary tenant, billing, payment, and configuration records.

The application must never silently erase existing records during restoration.

Do not rely solely on internal app storage for backups.

## 11. App Security

Implement:
- Optional PIN or biometric lock
- Secure local storage of sensitive credentials
- Input validation
- Protection against accidental deletions
- Confirmation dialogs for critical actions
- Audit records for financial corrections
- Appropriate local database protection

The app must remain usable without creating an online account.

## 12. User Interface and Experience

Design specifically for a non-technical person.

Use five primary navigation sections:

1. Home
2. Rooms & Tenants
3. Monthly Billing
4. Payments
5. More (History, Reports, Settings, Backup)

Requirements:
- Large, readable text
- Large buttons and touch targets
- Clearly labeled input fields
- Simple, easy-to-understand language
- Consistent typography and spacing
- Clear status indicators
- Minimal unnecessary steps
- Helpful error messages
- Confirmation before destructive operations
- Smooth Android navigation
- Light theme by default
- Optional dark mode

The app should make it possible to record a payment or enter a meter reading in just a few simple steps.

## 13. Data and Calculation Integrity

Use a properly structured SQLite database.

Keep rooms, tenants, tenancy records, utility readings, invoices, invoice line items, payments, payment allocations, deposits, and adjustments appropriately separated.

Use precise monetary calculations to avoid floating-point inaccuracies.

Ensure that:
- Bills cannot be duplicated accidentally.
- Payment records cannot be duplicated through repeated taps.
- Partial payments correctly reduce outstanding balances.
- Previous balances remain accurate across billing periods.
- Historic finalized bills are not altered by new rates.
- Tenant move-outs preserve historical data.
- The database remains usable after normal application restarts.
- Backup restoration reproduces financial totals correctly.

Use database transactions for multi-step financial updates.

## 14. Offline Requirements and Testing

All primary application functions must work with Wi-Fi and mobile data disabled.

Test:
- First launch without internet
- Room creation
- Tenant creation
- Meter reading entry
- Monthly bill generation
- Full and partial payments
- Balance carry-forward
- Receipt generation
- CSV and PDF exports
- App restart and device reboot
- Backup and restore
- Tenant move-out and reassignment
- Local reminders

Do not implement features that secretly depend on an online service.

## 15. Development Phases

**Phase 1 — Foundation:** Flutter application, local SQLite database, navigation, settings, room management, and tenant management.

**Phase 2 — Billing:** Meter readings, utility calculations, monthly bills, and balances.

**Phase 3 — Payments:** Payment records, partial payments, history, and receipts.

**Phase 4 — Management:** Dashboard, reports, local reminders, and backup/restore.

**Phase 5 — Quality Assurance:** Offline testing, financial accuracy, performance, usability, and final Android application packaging.

## Expected Output

Deliver a working, installable Android mobile application that enables a landlady to manage her rental property's tenants, monthly rent, electricity and water bills, payments, and historical records entirely offline.

Prioritize reliability, accurate financial calculations, simple navigation, and secure local data storage over unnecessary advanced functionality.