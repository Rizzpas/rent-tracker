These screenshots show the actual Flutter application at 390 × 844 logical pixels,
using an isolated in-memory SQLite database with fictional records created by
`test/preview_test.dart`. The installed application starts with empty records.

The test renderer uses bundled Noto Sans in place of Android's system Roboto.
No application screens or behavior are replaced by mockups.

To regenerate:

```powershell
flutter test test/preview_test.dart --dart-define=EXPORT_PREVIEWS=true
```

- `home.png`: month overview
- `home-details.png`: quick actions and monthly billing summary
- `rooms.png`: tenant and occupancy cards
- `billing.png`: monthly bill worksheet
- `payments.png`: collections and remaining balances
