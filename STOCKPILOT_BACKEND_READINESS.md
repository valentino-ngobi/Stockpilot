# StockPilot backend-readiness assessment

## Executive summary

StockPilot is a React, TypeScript, and Vite browser application. Its core workflows currently persist JSON records in browser LocalStorage. This is suitable for a local prototype, not a multi-shop SaaS or the authoritative storage for real financial operations.

The current UI contains useful validation and guarded-write checks, but they run in a client that users control. They cannot provide authorization, atomic transactions across records, durable backups, or reliable concurrent updates. Do not treat this frontend as production-ready until a server-backed data layer and the release gates below are implemented.

## Current application state

- **Core browser-local workflows:** inventory and stock movement, sales, purchase drafts and receiving, supplier/customer credit, daily closing, shop settings, and reference exchange-rate snapshots.
- **Reporting:** Overview and Operations derive metrics from locally saved inventory and transaction records. Reports exclude records with invalid amounts, unknown currencies, unknown costs, unsupported payment methods, or unavailable rates and display incompleteness notices.
- **Prototype sections:** custody, repairs, team/branches, and other demonstration screens are not a complete server-backed implementation.
- **Persistence boundary:** data is isolated to one browser profile and device. LocalStorage can be cleared or lost, is not a backup, and does not synchronize across users or devices.
- **Authentication and authorization:** the Supabase Auth and shop/branch migration is applied and its local RLS suite passed 42/42 assertions. Hosted/production RLS and browser-based authentication flows remain unverified. Prototype mode remains unauthenticated; frontend visibility is not an access-control boundary.
- **Testing:** Vitest covers shared financial-value, currency snapshot, conversion, payment-method, and Auth-service behavior. Page-level and multi-tab transaction behavior still needs broader automated coverage.

## Phase 2, Milestone 1 status

The repository now contains a local Supabase configuration, one identity/tenant migration, and a pgTAP suite for shop isolation, branch scope, membership changes, anonymous denial, and onboarding. The React app supports email registration/login, session restoration/logout, shop creation, authorized shop and branch selection, owner-created branches, and owner-scoped member role/branch assignment when Supabase is configured.

This is a locally verified identity foundation, not production backend readiness. Supabase CLI 3.2.0 reported the local project target, and `supabase migration list` showed migration `202611190001` applied. `supabase test db` passed 42/42 pgTAP assertions against `127.0.0.1:54322`. No hosted project was created or connected. The 44/44 frontend tests exercise service calls and configuration mode only; browser-based registration, login, session restoration, and hosted RLS remain unverified.

The local database, Auth, REST, Storage, Realtime, Studio, Kong, Analytics, and Edge Runtime containers were running; Docker reported most as healthy. Supabase CLI status marked `imgproxy` and `pooler` stopped, and Docker reported the `vector` container restarting. These ancillary services were not required by this identity/tenant migration or pgTAP run. The initial test attempts exposed a data-modifying CTE placement error and two invalid `IS NULL` assertions against `RETURNS void` RPCs; the test SQL was corrected, then all 42 assertions passed. No database reset was used.

Repository verification on 2026-11-19: `npm test` passed 44/44 tests, `npx tsc -b --pretty false` passed, `npm run build` passed with Vite 6.4.6, and `git diff --check` passed. Local database results do not verify a hosted production configuration or browser-based Auth flows.

The supported roles are `owner`, `manager`, `sales_staff`, and `inventory_staff`. Managers and staff are branch-scoped; owners can view and manage all active branches in their shop. Only owners can create branches, assign registered accounts to roles/branches, or suspend non-owner memberships. Owner transfer and email invitations are not implemented; membership assignment currently uses the target user's registered account UUID. Since business tables are not part of this milestone, role-specific access to sales versus inventory operations still needs to be enforced in those later table policies.

### Approved business rules for later milestones

The product owner has approved these domain rules. They guide later schema and transaction design, but are deliberately not implemented in the identity/tenant migration:

- A business can operate multiple branches.
- Customer sales must support full, partial, and multiple payments.
- Accessory inventory uses weighted-average costing, with separate cost pools per currency.
- Staff must explicitly select a customer-credit sale; the system must not infer credit from an unpaid balance.

No sales, payment, inventory, purchase, supplier/customer credit, accounting, or closing tables are part of Milestone 1. Final definitions for refunds, payment allocation, rounding, and accessory cost-layer transitions remain to be confirmed before those migrations.

When both `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` are absent, the existing LocalStorage workflows remain available in a visible unauthenticated prototype mode. Partial/invalid configuration fails closed. When configured, the Auth/tenant UI is separate and does not expose the still-LocalStorage financial workflows. No automatic migration or LocalStorage record changes occur.

Browser configuration rejects Supabase secret keys and legacy JWT keys whose role claim is `service_role`; Vite startup/build also stops before bundling them. Only a publishable or legacy anon key belongs in the Vite environment.

Local development uses `supabase start` and `supabase test db`. The checked-in config and migration were exercised with CLI 3.2.0. `supabase db reset` is destructive to local database state and was not used. Auth email confirmations are disabled only in the checked-in local config to simplify local development; production confirmation and redirect settings must be configured separately.

## Current reliability safeguards

The frontend includes top-level storage-read validation, explicit unavailable states, last-known-good refresh behavior, validation for several financial fields, and expected-raw comparisons before selected writes. Sales and purchase receiving attempt guarded rollback if sequential LocalStorage writes fail. Supplier credit supports legacy records with no `payments` property while rejecting malformed present payment arrays. Daily Closing blocks duplicate dates in its current view and checks for cross-tab changes before saving.

These are defensive UI safeguards only. LocalStorage compare-then-write is not atomic; another tab can write between a check and a write. Multi-key operations can also be interrupted, and rollback itself can fail. The backend must enforce the same business rules transactionally.

## Recommended backend foundation

Use PostgreSQL as the authoritative relational store, with Supabase Auth/PostgreSQL as a possible managed implementation. Keep the React client as an untrusted interface; all authorization and financial invariants must be enforced by trusted server-side code, database constraints, policies, and transactions.

Suggested core entities (final schema should follow domain discovery and migration tests):

1. Verify the prepared `user_profiles`, `shops`, `shop_memberships`, `branches`, and `branch_memberships` foundation before exposing financial APIs.
2. `products` — shared catalog fields for accessories and product descriptions.
3. `inventory_units` — serialized device identifiers and current ownership/location/status.
4. `inventory_balances` or `stock_lots` — non-serialized accessory quantities and weighted-average cost pools separated by currency.
5. `inventory_movements` — append-only receiving, sale, transfer, custody, repair, adjustment, and return events.
6. `sales` and `sale_lines` — transaction date, sale currency, discounts, totals, and item-level quantities/prices/cost snapshots.
7. `sale_payments` — one or more payments per sale, each with amount, currency, method, status, and timestamp. This supports full, partial, and multiple payments without pretending a whole sale was received in one method.
8. `purchases` and `purchase_lines` — invoice currency, item quantities/costs, initial payment, supplier references, and receipt status.
9. `supplier_accounts`, `customer_accounts`, and `credit_payments` — principal, payments, outstanding balance derivation, and currency per account. Customer credit must be explicitly selected by staff.
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
2. Run and review the prepared Auth, shop, membership, branch, and RLS migrations/tests locally; resolve policy findings before exposing financial APIs.
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
