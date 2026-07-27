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
  IntColumn get tax => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  IntColumn get changeDue => integer().withDefault(const Constant(0))();

  /// cash | kbzpay | wavepay | ayapay | cbpay
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get finalizedAt =>
      dateTime().withDefault(currentDateAndTime)();

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

/// Simple local key/value store for device-scoped app settings (printer MAC,
/// paper size, selected language, etc.). Not synced.
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
}
