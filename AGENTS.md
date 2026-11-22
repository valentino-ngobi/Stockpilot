# StockPilot repository guidance

## Project and current backend checkpoint

- StockPilot is a React, TypeScript, and Vite application with a Supabase/PostgreSQL backend.
- Committed database migrations currently cover identity and tenant access, inventory valuation and serialized receiving, Pending-FX release, product catalog, branch pricing, transfers, serialized custody, repair jobs, and repair-evidence privacy (through `202611220006`).
- Do not assume database functions are wired into every frontend workflow. Sales/POS, purchases, supplier credit, daily closing, and related financial records remain browser-LocalStorage workflows unless a later change explicitly replaces them. Preserve existing LocalStorage data.
- This is not production-ready. Hosted/production authorization and full browser-auth integration must not be described as verified without fresh evidence.

## Tenant and authorization rules

- PostgreSQL RLS and database authorization are the security boundary; UI visibility and client state are not authorization.
- Scope every operation to the authenticated user's active shop membership and authorized branch. Deny suspended memberships, inactive branches, cross-shop identifiers, and unauthorized staff roles.
- Review every `SECURITY DEFINER` function for a fixed safe `search_path`, explicit authorization, parameter validation, and narrowly granted `EXECUTE` privileges. Qualify database objects.
- Keep direct table privileges least-privileged. Preserve service-role restrictions, append-only audit history, and existing authorization helpers.

## Inventory and financial invariants

- A shop has one configured operating/valuation currency. Inventory valuation uses it; preserve original supplier/tender currency, accepted FX rate, source, timestamp, and converted amount where applicable. Never guess a missing rate or silently default an invalid historical currency.
- Pending-FX stock is unavailable for sale until authorized release. Do not recalculate historical costs when rates change.
- `NULL` cost means unknown; numeric zero is a known cost. Preserve exact decimal arithmetic and weighted-average precision (up to 10 decimal places).
- Preserve stable serialized-device identity and shop-wide normalized identifier uniqueness. Transfers and custody do not create a new device or imply sale/ownership change.
- Financial, stock, custody, and repair mutations must be transactional and idempotent, with immutable audit evidence and reconciliation checks. Do not add valuation or accounting postings to operational workflows without an approved design.

## Migrations, tests, and review

- Add timestamped migrations; do not rewrite committed migrations. Check populated-data compatibility, lock behavior, PostgreSQL 17 compatibility, RLS, grants, and rollback/replay implications.
- Use pgTAP for positive and negative authorization, tenant isolation, accounting/inventory invariants, idempotency, and audit immutability. Use separate-session tests for concurrency claims; do not infer concurrency safety from single-transaction tests.
- Use fictional test data only. Never use real customer information or real IMEI/serial identifiers.
- Before committing code, run the relevant automated tests, `npx tsc -b --pretty false`, `npm run build`, and `git diff --check`; inspect the complete diff and exact staged file list. Do not stage, commit, or push without authorization. Use professional Conventional Commit messages.
- Security reviews must distinguish demonstrated test coverage from assumptions and report remaining limitations.

## Protected database boundaries

- Never connect to, modify, restart, reset, migrate, or test against the protected original database `supabase_db_stockpilot` on port `54322` or the protected older baseline `supabase_db_stockpilotm2test20261120` on port `56322`.
- The only authorized routine database test project is `stockpilotm2repairtest20261122` on loopback port `57322`. Before any database command, explicitly verify the project/container, mounted volume, health, and loopback-only port mapping. Use its verified isolated Supabase work directory, never the repository's default Supabase target.
- Do not reset/drop databases or volumes, stop/recreate containers, change global PostgreSQL roles, grant superuser, or connect to hosted Supabase without separate explicit authorization.
- Never print, commit, or place passwords, tokens, service-role keys, private keys, or credential-bearing connection strings in files or command history.
