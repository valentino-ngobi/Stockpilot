# StockPilot backend-readiness assessment

## Executive summary

StockPilot is a React, TypeScript, and Vite browser application. Its core workflows currently persist JSON records in browser LocalStorage. This is suitable for a local prototype, not a multi-shop SaaS or the authoritative storage for real financial operations.

The current UI contains useful validation and guarded-write checks, but they run in a client that users control. They cannot provide authorization, atomic transactions across records, durable backups, or reliable concurrent updates. Do not treat this frontend as production-ready until a server-backed data layer and the release gates below are implemented.

## Current application state

- **Core browser-local workflows:** inventory and stock movement, sales, purchase drafts and receiving, supplier/customer credit, daily closing, shop settings, and reference exchange-rate snapshots.
- **Reporting:** Overview and Operations derive metrics from locally saved inventory and transaction records. Reports exclude records with invalid amounts, unknown currencies, unknown costs, unsupported payment methods, or unavailable rates and display incompleteness notices.
- **Prototype sections:** custody, repairs, team/branches, and other demonstration screens are not a complete server-backed implementation.
- **Persistence boundary:** data is isolated to one browser profile and device. LocalStorage can be cleared or lost, is not a backup, and does not synchronize across users or devices.
- **Authentication and authorization:** there is no production authentication or server-enforced shop membership/role model. Frontend visibility is not an access-control boundary.
- **Testing:** Vitest tests cover shared financial-value, currency snapshot, conversion, and payment-method validation. Page-level and multi-tab transaction behavior still needs broader automated coverage.

## Current reliability safeguards

The frontend includes top-level storage-read validation, explicit unavailable states, last-known-good refresh behavior, validation for several financial fields, and expected-raw comparisons before selected writes. Sales and purchase receiving attempt guarded rollback if sequential LocalStorage writes fail. Supplier credit supports legacy records with no `payments` property while rejecting malformed present payment arrays. Daily Closing blocks duplicate dates in its current view and checks for cross-tab changes before saving.

These are defensive UI safeguards only. LocalStorage compare-then-write is not atomic; another tab can write between a check and a write. Multi-key operations can also be interrupted, and rollback itself can fail. The backend must enforce the same business rules transactionally.

## Recommended backend foundation

Use PostgreSQL as the authoritative relational store, with Supabase Auth/PostgreSQL as a possible managed implementation. Keep the React client as an untrusted interface; all authorization and financial invariants must be enforced by trusted server-side code, database constraints, policies, and transactions.

Suggested core entities (final schema should follow domain discovery and migration tests):

1. `shops` and `shop_memberships` — shop ownership, member identity, role, and membership status.
2. `products` — shared catalog fields for accessories and product descriptions.
3. `inventory_units` — serialized device identifiers and current ownership/location/status.
4. `inventory_balances` or `stock_lots` — non-serialized accessory quantities and cost layers.
5. `inventory_movements` — append-only receiving, sale, transfer, custody, repair, adjustment, and return events.
6. `sales` and `sale_lines` — transaction date, sale currency, discounts, totals, and item-level quantities/prices/cost snapshots.
7. `sale_payments` — one or more payments per sale, each with amount, currency, method, status, and timestamp. This enables partial payments without pretending a whole sale was received in one method.
8. `purchases` and `purchase_lines` — invoice currency, item quantities/costs, initial payment, supplier references, and receipt status.
9. `supplier_accounts`, `customer_accounts`, and `credit_payments` — principal, payments, outstanding balance derivation, and currency per account.
10. `cash_movements` and `daily_closings` — opening float, cash receipts, paid-outs, counted cash, and immutable close/reopen or correction events.
11. `exchange_rate_snapshots` — provider, base currency, fetch/update times, rates, and source metadata. A reference rate must remain distinct from settlement amounts.
12. `audit_events` — actor, shop, action, entity, before/after references, request/idempotency key, and timestamp.

Every tenant-owned row should carry a `shop_id`. Use foreign keys, non-negative checks where appropriate, currency-code constraints, unique scoped serialized identifiers, and indexes for shop/date/report queries. Store monetary amounts as integer minor units with an explicit currency and documented scale, or use a rigorously chosen fixed-precision numeric type; do not use binary floating-point for authoritative ledger arithmetic.

## Transactional invariants the backend must enforce

- **Sale:** atomically validate shop membership, item availability, quantity, identifier, sale/payment currency, and amount; record sale lines and payments; decrement or mark inventory sold; append movement and audit events. Require an idempotency key so retries cannot create duplicate sales.
- **Purchase receiving:** atomically change the purchase receipt state, add device/stock-lot inventory, create supplier payable and initial payment entries, and append audit/movement records. A repeated request must not receive the same purchase twice.
- **Payments and credit:** payments must reference an open account/sale/purchase, use an explicit currency, be valid non-negative amounts, and not exceed the permitted outstanding amount. Derive or transactionally maintain balances; do not trust a client-supplied balance.
- **Daily closing:** compute from a stable, server-selected set of posted payments and cash movements for the shop and date. Enforce one active closing per shop/date, record who closed it, and require explicit correction/reopen events rather than silently replacing a saved close.
- **Inventory:** serialize concurrent stock changes through database transactions/locking or equivalent constraints. Never infer unknown historical cost or currency.
- **Reporting:** aggregate posted records in their recorded currencies. Convert only with a documented rate snapshot and visibly distinguish converted estimates from ledger amounts. Exclude/flag unknown values instead of assigning the shop's current currency to old records.
- **Authorization:** enforce shop isolation and roles server-side. Test that users cannot read or mutate another shop's records, including via direct API requests.

## Migration sequence

1. Finalize domain definitions for sale payments, discounts/refunds, accessory cost layers, supplier credit, cash movements, and status transitions before freezing a schema.
2. Implement Auth, shops, memberships, and server-side authorization first; test tenant isolation before exposing financial APIs.
3. Add transaction-safe inventory, sales/payment, purchasing/receiving, credit, and daily-close endpoints. Keep writes behind service functions and idempotency keys.
4. Add schema constraints, audit events, backup/restore procedures, retention rules, observability, and failure recovery.
5. Build an explicit, user-triggered LocalStorage export/import tool. Validate a copy offline, report duplicates and invalid records, preserve original currency/date values, and require the user to resolve unknown values. Never auto-migrate by guessing currencies or costs.
6. Run dual-read or staged shop-by-shop migration only with a tested reconciliation report: record counts, quantities, per-currency sale/purchase totals, payment totals, outstanding balances, and closing totals.
7. Switch reads and writes to the backend only after reconciliation; retain a recoverable export and a documented rollback path. Do not keep LocalStorage as a silent competing source of truth.
8. Add retry/offline queues only after idempotent server writes and explicit conflict semantics exist. Show pending versus confirmed transactions to the user.

## Release gates before real-shop use

- Server-side identity, shop membership, role authorization, and tenant-isolation tests.
- Atomic sale, purchase-receipt, credit-payment, and daily-close transactions with concurrency/idempotency tests.
- Automated tests for currency, rounding, unknown values, discounts, refunds, partial payments, failed requests, and stock conflicts.
- Monitored production backups plus a tested restore and disaster-recovery procedure.
- Secure handling of personal data and device identifiers, audit retention, privacy notice, and access logging.
- Reconciliation and migration tooling that does not alter source data until a reviewed import is confirmed.
- Clear operational policy for exchange rates, offline actions, corrections, and closing reopen/reconciliation.

Until these controls exist, use fictional data only and retain separate backups of any evaluation data.
