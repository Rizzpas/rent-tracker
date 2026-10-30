# Shared implementation contract

All amounts integer centavos; all readings integer thousandths. Dates ISO YYYY-MM-DD; billing periods YYYY-MM. All code uses data/models.dart Row and AppData.

Repository in lib/data/repository.dart: RentalRepository.open({DatabaseFactory? factory, String? path}); Future<AppData> load(); Future<void> close().

Tables (each id INTEGER PK unless settings):
- rooms: name, rent_cents, electricity_mode ('metered','fixed','shared'), electricity_rate (centavos per unit or fixed charge), water_mode, water_rate, notes, archived (0/1)
- tenants: name, phone, notes
- tenancies: room_id, tenant_id, move_in, move_out nullable, rent_cents, due_day
- readings: room_id, kind ('electricity'/'water'), period, previous_value, current_value, invoice_id
- invoices: tenancy_id, room_id, period, due_date, status ('draft'/'final'), total_cents, reference, created_at, finalized_at nullable
- lines: invoice_id, kind ('rent'/'electricity'/'water'/'adjustment'), description, quantity (thousandths), rate_cents, amount_cents
- payments: date, amount_cents, method ('Cash'/'GCash'/'Bank transfer'/'Other'), reference, notes, request_id unique, reversed_at nullable, reversal_reason nullable
- allocations: payment_id, invoice_id, amount_cents
- deposits: tenancy_id, kind ('received'/'refund'/'deduction'), amount_cents, date, notes
- audit: action, entity, entity_id, detail, created_at
- settings: key,value text

Repository methods (all async):
Future<int> saveRoom(Row values) (id optional; validate all fields)
Future<void> archiveRoom(int id)
Future<int> assignTenant({required int roomId, required String name, required String phone, required String moveIn, required int rentCents, required int depositCents, required int dueDay, String notes = ''}) returns tenancy id
Future<void> updateTenant({required int tenancyId, required String name, required String phone, required int rentCents, required int dueDay, String notes = ''})
Future<void> moveOut(int tenancyId, String date)
Future<int> saveDraft({required int tenancyId, required String period, required String dueDate, int? electricityCurrent, int? waterCurrent, int adjustmentCents = 0, String adjustmentNote = '', int? electricitySharedCents, int? waterSharedCents})
Future<void> finalizeInvoice(int id)
Future<int> recordPayment({required int invoiceId, required int amountCents, required String date, required String method, required String requestId, String reference = '', String notes = ''})
Future<void> reversePayment(int id, String reason)
Future<void> settleDeposit({required int tenancyId, required String kind, required int amountCents, required String date, required String notes})
Future<void> saveSettings(Map<String,String> values)
Future<Map<String,dynamic>> exportData()
Future<void> validateBackup(Map<String,dynamic> backup)
Future<void> restoreData(Map<String,dynamic> backup) (atomic replace only after full validation; UI must explicitly confirm)

Settings defaults: property_name='My rental property', property_address='', owner_name='', dark_mode='false', reminders='false', meter_day='25', last_backup=''.

UI pages lib/ui: HomePage, RoomsPage, BillingPage, PaymentsPage take ({required AppData data, required RentalRepository repository, required VoidCallback onChanged, required String period}); HomePage also required ValueChanged<int> onNavigate. Root owns selected period and shell. MorePage in lib/ui/more_page.dart has same arguments. Root provides refresh after mutation. Services own services/documents.dart, backup.dart, app_lock.dart, reminders.dart. MorePage can import shared lib/ui/common.dart from UI agent (keep self-contained until available).

Services public contracts: DocumentService.statement(AppData data,int invoiceId), receipt(AppData data,int paymentId), report(AppData data,{String? period,int? year,int? roomId,int? tenantId}), exportCsv(AppData data,{String? period,int? year,int? roomId,int? tenantId}) each Future<void> opens action UI via printing/share or device save. BackupService.exportBackup(repository,{String? password}), importBackup(repository,BuildContext context,{String? password}) Future<bool>. AppLock widget wraps child and repository optional. ReminderService.initialize(), reschedule(AppData data), requestPermission() Future<bool>. These contracts may be extended; notify root and UI agent.

Repository implementation notes:
- `lines.mode` also snapshots `rent`, `metered`, `fixed`, `shared`, or `adjustment`.
- `saveDraft` also takes optional `int? electricityPrevious, int? waterPrevious` for the initial installed-meter baseline. After the first finalized reading, the last finalized current reading is authoritative across tenants.
- There is one invoice per room and billing month. A replacement tenant cannot receive a second invoice for the same room/month. Mid-month proration must be reviewed manually through adjustments on the month's draft before finalization.
- A metered draft may omit current readings, but cannot be finalized until all required readings are entered. Finalization must proceed in month order. A stale later draft must be saved again after an earlier bill is finalized.
- Security deposit refunds/deductions require a move-out record and explanatory notes; rent payments remain separate. `settleDeposit` also supports `kind: received` for later deposits.
- Backup envelope: `{format: 'bahay-rent-backup', version: 1, created_at: ISO, tables: {...}}`; settings are `{key,value}` rows. Validation uses a separate SQLite candidate before atomic restoration, preserving all existing records on failure.
