# StockPilot stabilization progress

## Baseline

- Active project: `D:\stockpilot` (verified working directory), branch `main`.
- Existing user changes: nine modified files before this assignment: `DailyClosing.tsx`, `Inventory.tsx`, `Operations.tsx`, `Overview.tsx`, `Purchases.tsx`, `Settings.tsx`, `SupplierCredit.tsx`, `sales.tsx`, and `src/utils/currency.ts`. Preserve these changes.
- Baseline `npm run build`: passed.
- Baseline `git diff --check`: passed; Git reported existing LF/CRLF conversion warnings for `Operations.tsx` and `Overview.tsx`.
- No test files or test script were found. `package.json` currently provides `dev`, `build`, and `preview`.
- No browser storage was accessed.

## Inspections completed

- Confirmed client-side React/Vite entry, application navigation, shared UI components, currency utilities, and current LocalStorage usage.
- Reviewed Sales, Inventory, Purchases, Supplier Credit, Daily Closing, Overview, Operations, Settings, and shared currency/sales utilities, including storage reads, refresh behavior, calculations, guarded writes, and snapshot checks.
- Reviewed responsive breakpoints and accessible labels/status roles statically. No browser interaction was used, so visual behavior and assistive-technology behavior were not independently exercised.
- Confirmed the repository still has substantial pre-existing uncommitted changes; no files have been reverted, staged, committed, or pushed.

## Problems found so far

- LocalStorage compare-then-write checks and sequential multi-key writes are not atomic; a tab can still race between a comparison and a write. This cannot be fully resolved in the frontend without a transactional persistence layer.
- Partial customer payments are not supported by Sales/POS. Operations and Daily Closing now explain that their payment-method reports treat the selected method as applying to the full sale amount. Customer receivables in the credit ledger remain a separate workflow.
- Malformed saved row shapes are still not comprehensively validated across every page. The pages validate top-level JSON arrays and key financial fields, but a malformed record may still require manual recovery.
- Supplier-credit payment totals that exceeded a record's principal could previously be shown as a settled zero balance. Shared outstanding-balance validation now treats overpayment as unavailable, excludes that balance from summaries, blocks further payments, and is covered by regression tests.

## Fixes and verification

- Added Vitest and focused shared utility tests for currency/cost, sale amounts, stock quantities, exchange-rate snapshot validation/conversion, and payment methods.
- Added strict finite non-negative financial amount validation and strict safe-integer quantity validation. Formatting no longer converts non-finite values to zero.
- Added date/timestamp and rate-table validation for saved exchange-rate snapshots; converted results that overflow are rejected.
- Operations excludes invalid/unknown sale amounts, currencies, costs, quantities, payment methods, and unavailable conversions from the affected reports. It reports incomplete totals and protects aggregate overflow.
- Daily Closing excludes invalid sale amounts, blocks saving when sale amounts/currencies/payment methods or aggregate totals are invalid, and no longer displays malformed legacy closing amounts as zero.
- Supplier Credit and Purchases now treat invalid principals/payment totals as unavailable rather than zero, retain compatibility with legacy credits missing `payments`, and show excluded amounts.
- Purchase receiving validates the saved item totals, quantities, costs and initial payment before preparing writes. Accessory merging requires valid existing quantities/costs and checks weighted-cost arithmetic before writing.
- Sales validates transaction dates and reports invalid saved sale amounts without assigning an assumed currency. Payment method options are shared and validated.
- Overview and Operations no longer label shop-currency totals using the default currency when saved shop currency settings are invalid.
- README now accurately distinguishes LocalStorage-backed workflows from demo screens. Added `STOCKPILOT_BACKEND_READINESS.md` with proposed backend entities, invariants, migration steps, and production gates.
- Updated the test toolchain to Vitest 4.1.12 and Vite 6.4.6 after the initial audit found critical test-runner and high-severity build-tool dependency advisories. Both versions support the documented Node 20/22 baseline.

## Final verification

- `npm test`: passed, 33 tests across 2 files.
- `npx tsc -b --pretty false`: passed.
- `npm run build`: passed with TypeScript and Vite 6.4.6 (1,817 modules transformed).
- `git diff --check`: passed. Git emitted only LF/CRLF conversion warnings for working-copy files.
- The earlier dependency audit reported 0 production vulnerabilities and 5 high-severity development/build advisories through `picomatch` (GHSA-fc5q-39xc-vjpf), which had no patched release at the time. The audit was not rerun during this final verification.
- Confirmed branch `main`, synchronized with `origin/main` (0 commits ahead, 0 behind). The working tree contains 12 modified tracked files and 5 untracked files; no files are staged.
- No browser LocalStorage was read or changed. Nothing was staged, committed, or pushed.

## Remaining limitations

- Deep validation of every historical record schema is not comprehensive. Malformed row objects may still need manual recovery; no automatic repair or default currency/cost inference is performed.
- Responsive and accessibility review was static; no live browser or screen-reader verification was performed.
- LocalStorage remains single-browser-profile storage with no reliable multi-device sync, authorization, backups, atomic transactions, or server-enforced idempotency. Frontend safeguards reduce common stale-write errors but do not solve these backend requirements.
- Page-level and multi-tab interaction tests remain a follow-up; current automated coverage focuses on shared financial and currency utilities.
