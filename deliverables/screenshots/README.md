These screenshots show the actual **Upa Renta** Flutter application at 390 × 844 logical pixels,
using an isolated in-memory SQLite database with fictional records created by
`test/preview_test.dart`. The installed application starts with empty records.

The test renderer uses bundled Noto Sans in place of Android's system Roboto.
No application screens or behavior are replaced by mockups.

To regenerate:

```powershell
flutter test test/preview_test.dart --dart-define=EXPORT_PREVIEWS=true
```

- `home.png`: dashboard overview, Collections Day banner, and top `Collect` button
- `collections.png`: Collections Day screen (`< 3` taps to record payment & generate receipt)
- `home-details.png`: quick actions and room-by-room summary
- `rooms.png`: room cards, tenant agreements, and due-date schedules
- `billing.png`: monthly billing worksheet
- `payments.png`: collections ledger, 1-tap receipt icons, and remaining balances
- `more.png`: backups, reports, local reminders, test notification, and security settings
