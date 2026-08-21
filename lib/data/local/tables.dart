import 'package:drift/drift.dart';

/// Common columns every syncable table carries. Mixed into table definitions.
///
/// - [id] is a client-generated UUID (offline-first: device can create rows
///   without a server round-trip).
/// - [updatedAt] drives last-write-wins conflict resolution.
/// - [isDeleted] is a tombstone so deletes propagate through sync.
/// - [dirty] marks rows with local changes not yet pushed to the server.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get shopId => text()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

class Categories extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  IntColumn get salePrice => integer().withDefault(const Constant(0))();

  /// Per-tier override prices. Null means "use [salePrice]" — a shop that
  /// never sets these keeps ordinary single pricing with no behavior change.
  IntColumn get wholesalePrice => integer().nullable()();
  IntColumn get vipPrice => integer().nullable()();

  /// Caps how many units of this product the public web storefront will
  /// sell, independent of the shop's real [StockLevels] quantity — e.g. a
  /// shop with 20 in-store may want to reserve only 5 for online, keeping
  /// the rest for walk-in customers. Null means "no cap" (storefront just
  /// warns on the real stock count instead, see `low_stock_at_order`).
  /// Unlike the real-stock warning, this cap is hard-enforced: it's a number
  /// the owner set on purpose, not a value that can be stale from sync lag.
  IntColumn get onlineStockLimit => integer().nullable()();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  TextColumn get imagePath => text().nullable()();
  /// Public storage URL of the product photo (shown on the web storefront).
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Denormalized current stock quantity per product. The authoritative ledger
/// is [StockMovements]; this row is the fast-read cached total.
class StockLevels extends Table with SyncColumns {
  TextColumn get productId => text()();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get reorderLevel => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A local-only, per-device cache of open FIFO purchase lots — never synced.
/// Fully derivable by replaying [StockMovements] (the synced source of
/// truth): each purchase/opening/positive-adjustment movement pushes a lot,
/// each sale/return/negative-adjustment consumes oldest-first. Kept as its
/// own table (rather than replayed on every sale) so `finalizeSale` doesn't
/// have to walk a product's entire movement history on every checkout.
///
/// Deliberately NOT a [SyncColumns] table: syncing an absolute per-lot
/// quantity via last-write-wins would repeat the exact anti-pattern
/// [StockLevels] already carries (see its own doc comment) — two devices
/// consuming the same lot concurrently offline would silently lose one
/// side's consumption. Each device instead derives its own lot state from
/// its local copy of the (append-only, conflict-safe) movement ledger.
class StockLots extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get productId => text()();
  IntColumn get remainingQty => integer()();
  IntColumn get unitCost => integer()();
}

class StockMovements extends Table with SyncColumns {
  TextColumn get productId => text()();

  /// purchase | sale | adjustment | return
  TextColumn get type => text()();
  IntColumn get qtyDelta => integer()();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
  TextColumn get refId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A finalized sale. **Append-only** — once written it is never updated, so
/// it can never conflict during sync. Corrections are separate reversal sales.
class Sales extends Table with SyncColumns {
  TextColumn get invoiceNo => text()();
  TextColumn get staffId => text().nullable()();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  IntColumn get changeDue => integer().withDefault(const Constant(0))();

  /// cash | kbzpay | wavepay | ayapay | cbpay | credit | cod
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get finalizedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Where to deliver this sale, carried over from the `Orders` row it was
  /// converted from (`Order.deliveryAddress` + `Order.township` combined) —
  /// null for an ordinary in-store sale. Without this, a converted order's
  /// invoice/receipt loses the delivery address entirely, which the whole
  /// point of printing it (so whoever fulfills the delivery has it) defeats.
  TextColumn get deliveryAddress => text().nullable()();

  /// Set on a refund row, pointing at the sale it reverses. A refund is a
  /// normal append-only [Sales] row with negated subtotal/discount/total/paid
  /// (so it nets out in analytics/reporting with no special-casing) — the
  /// original sale is never mutated. Null on every ordinary sale.
  TextColumn get refundOfSaleId => text().nullable()();

  /// Links to a [Customers] row when the buyer was picked from (or resolved
  /// to) the customer directory. Null on sales predating that directory, or
  /// where the seller just typed a one-off name — `customerName`/`Phone`
  /// above remain the source of truth for what actually printed on the
  /// receipt either way (this is purely an additional lookup key).
  TextColumn get customerId => text().nullable()();

  /// The physical device (`SettingsRepository.deviceId()`) that rang this
  /// sale up — same stable id already used for license activation. Null on
  /// sales predating this column. A raw UUID means nothing to an owner on
  /// its own; see [DeviceLabels] for the friendly name shown on invoices.
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table with SyncColumns {
  TextColumn get saleId => text()();
  TextColumn get productId => text()();

  /// Snapshots of name/price at sale time so history is stable even if the
  /// product is later renamed or repriced.
  TextColumn get nameSnapshot => text()();
  IntColumn get priceSnapshot => integer()();
  IntColumn get qty => integer()();
  IntColumn get lineTotal => integer()();

  /// Total cost of goods sold for this line, FIFO-consumed from
  /// [StockLots] at sale time — mirrors [lineTotal] (a total, not a
  /// per-unit price like [priceSnapshot]) so `lineTotal - costSnapshot` is
  /// the line's exact profit with no rounding. Null on sales predating this
  /// feature, or an invoice-only shop that doesn't track stock — Analytics
  /// falls back to the product's flat cost price for those.
  IntColumn get costSnapshot => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table with SyncColumns {
  TextColumn get saleId => text()();

  /// cash | kbzpay | wavepay | ayapay | cbpay
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  TextColumn get refNo => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A renewal payment the owner recorded locally (KBZPay/Wave/cash). Synced to
/// the server so a human/automation can reconcile it against the license.
class LicensePayments extends Table with SyncColumns {
  TextColumn get licenseKey => text()();

  /// cash | kbzpay | wavepay | ayapay | cbpay
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  TextColumn get refNo => text().nullable()();
  TextColumn get note => text().nullable()();

  /// The shop's own display name (from Shop profile), so the admin console
  /// shows who paid rather than the internal shop id.
  TextColumn get shopName => text().nullable()();
  BoolColumn get reconciled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A customer directory entry — enter a name/phone/address once and reuse it
/// on every future invoice/order instead of retyping. Synced so the same
/// directory shows on every device under the shop. `Sales`/`Orders`/
/// `CreditPayments` link here via a nullable `customerId`, but keep their own
/// `customerName`/`Phone` snapshot too — a directory-entry rename never
/// retroactively changes what already printed on an old receipt.
class Customers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get township => text().nullable()();

  /// retail | wholesale | vip — drives which [Products] price column the
  /// Sell screen applies when this customer is attached to a sale.
  TextColumn get tier => text().withDefault(const Constant('retail'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A supplier the shop buys stock from — same shape as [Customers] (a
/// simple named-entity directory), used by [PurchaseOrders].
class Suppliers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per shop (id == shopId), synced so the admin console can show a
/// shop's name/phone/address without it having published a public
/// Storefront (`Storefronts` is customer-facing and opt-in; this mirrors
/// just the contact fields already collected by `ShopProfileScreen`, whose
/// authoritative local copy stays the existing `AppSettings` KV entries —
/// this table exists purely so admin tooling has something to read).
/// `@DataClassName` avoids colliding with `SettingsRepository`'s existing
/// (unrelated, KV-backed) `ShopProfile` class.
@DataClassName('ShopProfileRow')
class ShopProfiles extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A named money account the shop receives payments into besides cash —
/// KBZPay, WavePay, or any custom one the owner adds — used to track a
/// running balance per account. [openingBalance] is set once at creation
/// (rarely edited after, like [CashSessions.openingAmount]) — the actual
/// running balance is never stored here; it's always derived at read time
/// from [Payments]/[CreditPayments]/[Expenses] rows referencing this
/// account's id (see `computeAccountBalance`), same reasoning
/// `stock_levels.quantity` already follows: a running total must never be
/// a directly-synced absolute-value LWW field.
class PaymentAccounts extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A purchase order placed with a supplier — lightweight tracking (what was
/// ordered, from whom, at what cost), NOT procurement automation (see
/// PROJECT_SPEC.md §1.2). [supplierName] is a snapshot (shown even if the
/// supplier is later renamed/deleted), same convention as [Orders.customerName].
/// `status`: open | received | cancelled. Receiving is all-or-nothing (no
/// partial-per-line receiving) — see `PurchaseOrderRepository.receivePO`,
/// which reuses `InventoryRepository.adjustStock` (the same method a manual
/// restock already calls) rather than any new stock-mutation logic.
class PurchaseOrders extends Table with SyncColumns {
  TextColumn get poNo => text()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get supplierName => text()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get itemsTotal => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get receivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One line of a [PurchaseOrders] row — always tied to a real [Products] row
/// (unlike [OrderItems], which allows a free-text line) since receiving
/// needs a concrete product to restock.
class PurchaseOrderItems extends Table with SyncColumns {
  TextColumn get poId => text()();
  TextColumn get productId => text()();
  TextColumn get nameSnapshot => text()();
  IntColumn get qty => integer()();
  IntColumn get unitCost => integer()();
  IntColumn get lineTotal => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A repayment a customer made against their outstanding credit (အကြွေး).
/// Customers are keyed by [customerName] (the same free-text field carried on
/// [Sales]); a credit sale is a sale with `paymentMethod = 'credit'` where
/// `paid < total`. Outstanding per customer = Σ(credit sale total − paid) −
/// Σ(creditPayments.amount). Synced like every other ledger row.
class CreditPayments extends Table with SyncColumns {
  TextColumn get customerName => text()();

  /// cash | kbzpay | wavepay | ayapay | cbpay
  TextColumn get method => text().withDefault(const Constant('cash'))();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();

  /// Links to a [Customers] row — see the same field on [Sales] for why this
  /// is additional, not a replacement for [customerName].
  TextColumn get customerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A payment the shop made toward a supplier's outstanding balance —
/// Accounts Payable's mirror image of [CreditPayments] (money owed *by*
/// the shop, not *to* it). Owed per supplier = Σ(itemsTotal of that
/// supplier's **received** [PurchaseOrders]) − Σ(supplierPayments.amount).
/// Only received POs count — an `open` PO hasn't actually incurred a debt
/// yet, and a `cancelled` one never will (accrual, matching how
/// [PurchaseOrderRepository.receivePO] is the one real "this happened"
/// event in that lifecycle).
class SupplierPayments extends Table with SyncColumns {
  TextColumn get supplierName => text()();

  /// cash | kbzpay | wavepay | ayapay | cbpay
  TextColumn get method => text().withDefault(const Constant('cash'))();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();

  /// Links to a [Suppliers] row — see [CreditPayments.customerId] for why
  /// this is additional, not a replacement for [supplierName].
  TextColumn get supplierId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One owner capital contribution or drawing — deliberately **separate**
/// from [Expenses] (never summed into it), since a drawing must never
/// silently reduce [AnalyticsSummary.netProfit]/the P&L the way a business
/// expense correctly does. Paid-in capital = Σ(contribution amounts) −
/// Σ(drawing amounts); combined with Retained Earnings (cumulative Net
/// Profit since inception, derived from `AnalyticsRepository.summary()` —
/// not stored here) into Owner's Equity for an eventual Balance Sheet.
class EquityEntries extends Table with SyncColumns {
  /// contribution | drawing
  TextColumn get type => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A social-channel order (Facebook/Viber/TikTok/phone) tracked through a
/// Kanban pipeline **before** it becomes an in-store sale. Unlike [Sales] this
/// row is **mutable** — the [status] moves through the board and items get
/// edited — so it syncs last-write-wins on [updatedAt] like every other table.
///
/// Stock is intentionally NOT touched here: when an order reaches `delivered`
/// it is converted into a [Sales] row via `SalesRepository`, which is the one
/// place that writes the append-only ledger + stock movements. [saleId] links
/// back to that sale once converted.
class Orders extends Table with SyncColumns {
  /// Per-shop, per-day sequential: `ORD-yyyyMMdd-NNN`.
  TextColumn get orderNo => text()();

  /// facebook | viber | tiktok | instagram | phone | other
  TextColumn get channel => text().withDefault(const Constant('facebook'))();

  /// new | confirmed | packed | shipped | delivered | cancelled
  TextColumn get status => text().withDefault(const Constant('new'))();

  TextColumn get customerName => text()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get deliveryAddress => text().nullable()();
  IntColumn get deliveryFee => integer().withDefault(const Constant(0))();

  /// Denormalized Σ(order_items.line_total). Card total = itemsTotal + deliveryFee.
  IntColumn get itemsTotal => integer().withDefault(const Constant(0))();

  /// unpaid | partial | paid
  TextColumn get paymentStatus =>
      text().withDefault(const Constant('unpaid'))();

  /// How the customer intends to pay: transfer (KPay/Wave, usually with a
  /// screenshot) | cod (cash on delivery) | null (manually-created order,
  /// not yet specified). Distinct from [paymentStatus] — a COD order is
  /// legitimately "unpaid" until the courier collects cash at the door,
  /// which is a different shop workflow than reviewing a transfer screenshot.
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Set once the order is converted to an in-store [Sales] row.
  TextColumn get saleId => text().nullable()();

  /// Storage path of a customer-uploaded payment screenshot (storefront
  /// orders). Viewed by the shop via a signed URL.
  TextColumn get paymentProofPath => text().nullable()();

  /// Myanmar township the delivery address is in (free-text key from a fixed
  /// list — see `myanmarTownships`). Lets a shop route/batch by area even
  /// before a real carrier API is wired up.
  TextColumn get township => text().nullable()();

  /// ninja_van | royal_express | other | null (not yet assigned).
  TextColumn get deliveryCarrier => text().nullable()();

  /// Waybill/tracking number. Entered manually today (via the carrier's own
  /// app/site); becomes carrier-API-issued once a real integration lands.
  TextColumn get trackingNumber => text().nullable()();

  /// pending | booked | out_for_delivery | delivered | failed | returned.
  /// Separate from [status] (the Kanban stage) — this tracks the delivery leg
  /// specifically, which can keep moving after the order itself is "shipped".
  TextColumn get deliveryStatus => text().nullable()();

  /// Links to a [Customers] row — see the same field on [Sales] for why this
  /// is additional, not a replacement for [customerName].
  TextColumn get customerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class OrderItems extends Table with SyncColumns {
  TextColumn get orderId => text()();

  /// Nullable: a social order line may be a free-text item not in the catalog.
  TextColumn get productId => text().nullable()();

  /// Snapshots so the order stays stable if the product is later renamed/repriced.
  TextColumn get nameSnapshot => text()();
  IntColumn get priceSnapshot => integer()();
  IntColumn get qty => integer()();
  IntColumn get lineTotal => integer()();

  /// True if, at the moment a storefront guest placed this order, [qty]
  /// exceeded the shop's recorded stock for this product. Orders are never
  /// blocked for this (stock synced to the storefront can lag reality) — it
  /// just flags the line so the owner notices before packing/shipping it.
  BoolColumn get lowStockAtOrder =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A named staff profile the owner sets up so a sale can be attributed to
/// whoever rang it up (`Sales.staffId`) instead of just a shared device PIN.
/// Deliberately lightweight — a name + a PIN, not a real login account (see
/// PROJECT_SPEC §12 for why): no server-side enforcement, just an identity
/// tag. Synced so every device under the shop shows the same staff roster.
class StaffMembers extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get pin => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A shop's non-inventory operating expense (rent, utilities, staff wages,
/// transport, packaging, …). Deliberately separate from restocking cost,
/// which already flows into Analytics as cost-of-goods-sold via
/// [Products.costPrice]/[StockLots] — recording a restock here too would
/// double-count it against gross profit.
///
/// [receiptPhotoPath] is a **local file path only** — never uploaded to
/// Supabase Storage (kept off the ongoing sync/data-cost path on purpose), so
/// it syncs as null to every other device and only ever resolves on the
/// device the photo was taken on. The remote `expenses` table has no column
/// for it at all; see `sync_mappers.dart`.
class Expenses extends Table with SyncColumns {
  /// rent | utilities | wages | transport | packaging | other
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get receiptPhotoPath => text().nullable()();
  /// Which [PaymentAccounts] row this was paid from — null means cash (the
  /// implicit default every expense had before this column existed; see
  /// `computeExpectedCash`'s own doc comment).
  TextColumn get accountId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A cash-drawer session: an owner/cashier declares [openingAmount] at the
/// start of the day (or shift) and, at the end, counts the drawer and
/// records [closingAmount] — the app computes what the drawer *should* hold
/// (opening + cash sales + cash credit-repayments − cash expenses, all
/// within [openedAt, closedAt)) so a mismatch (till shortage/overage) shows
/// up immediately rather than being noticed weeks later. [closedAt] null
/// means the session is still open — only one open session per shop is
/// expected at a time (enforced app-side, not by a DB constraint, so an
/// interrupted close never locks the shop out).
class CashSessions extends Table with SyncColumns {
  DateTimeColumn get openedAt => dateTime()();
  IntColumn get openingAmount => integer()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get closingAmount => integer().nullable()();
  TextColumn get note => text().nullable()();

  /// The device that opened this session (`SettingsRepository.deviceId()`,
  /// same stable id used elsewhere) — a raw UUID means nothing to an owner
  /// on its own; see [DeviceLabels] for the friendly name shown in the UI.
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// An owner-set friendly name for one of the shop's devices (e.g. "Counter
/// A", "Owner's phone"), so a raw device UUID on a [Sales] row can show as
/// something meaningful on an invoice regardless of which device is doing
/// the viewing. Synced (unlike the device id itself, which lives only in
/// this device's own secure storage) — every device needs to see every
/// other device's label, not just its own.
class DeviceLabels extends Table with SyncColumns {
  TextColumn get deviceId => text()();
  TextColumn get label => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A recurring monthly cost (rent, wages, etc.) the owner sets up once so
/// they don't have to retype it every month. Manual quick-fill by default —
/// the owner taps to create a new [Expenses] row from a template, reviewing
/// the amount/date before saving. [active] lets a seasonal cost be paused
/// without losing it, distinct from a real (soft) delete.
///
/// [autoGenerate] opts a template into automatic generation instead —
/// [generationTiming] ('month_start'/'month_end') picks which day of the
/// month it fires on, and [lastGeneratedPeriod] ('YYYY-MM') is stamped after
/// a successful auto-generation so the same month never double-fires (see
/// `RecurringExpenseRepository.generateDueExpenses`).
class RecurringExpenses extends Table with SyncColumns {
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  BoolColumn get autoGenerate =>
      boolean().withDefault(const Constant(false))();
  TextColumn get generationTiming =>
      text().withDefault(const Constant('month_start'))();
  TextColumn get lastGeneratedPeriod => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Simple local key/value store for device-scoped app settings (printer
/// address/connection, paper size, selected language, etc.). Not synced.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Outbox of local mutations awaiting push to Supabase. Drained by SyncEngine.
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityTable => text()();
  TextColumn get rowId => text()();

  /// upsert | delete
  TextColumn get op => text()();

  /// JSON payload of the row at enqueue time.
  TextColumn get payload => text()();
  DateTimeColumn get enqueuedAt =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// The exception message from the most recent failed push attempt, if
  /// any — used for auto-heal classification (RLS / unique) and Support
  /// diagnostics after quarantine (see `SyncEngine._push`).
  TextColumn get lastError => text().nullable()();

  /// Permanently-failing rows are quarantined after [kOutboxStuckThreshold]
  /// attempts so they no longer block branch switch / pending counts.
  /// Local entity data is kept; `sync_force_apply` converges them without
  /// asking the owner to Discard or call Support.
  BoolColumn get quarantined =>
      boolean().withDefault(const Constant(false))();
}
