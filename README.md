# StockPilot (working name)

A responsive frontend prototype for small phone and gadget retailers. The public brand name is still being reviewed.

## Current milestone

This project includes a dashboard, serialized device and accessory inventory, browser camera barcode/QR scanning, and browser-local flows for sales/POS, purchases, supplier credit/customer receivables, daily closing, reports, and settings. Custody, repairs, and some navigation screens remain demonstrations. The repository now includes a first Supabase Auth and shop/branch access foundation, but business records are not yet connected to PostgreSQL.

**Important:** StockPilot is not a production-ready retail system. With Supabase environment values absent, it opens the clearly labeled local prototype: core inventory, sales, purchases, supplier-credit, settings, exchange-rate, and closing records remain in this browser's LocalStorage. With both Supabase values configured, it opens the Auth and shop/branch foundation; financial workflows are intentionally not shown in authenticated mode until they have server-backed implementations. LocalStorage records are not migrated or changed by the Auth foundation. Clearing browser data, changing browsers, or losing this device can lose local records.

The identity migration `202611190001` has been applied to the local Supabase database, and its pgTAP security suite passed **42/42 assertions**. The frontend suite passed **44/44 tests**; TypeScript compilation and the production build passed. Hosted/production RLS and browser-based authentication flows remain unverified. Financial workflows remain LocalStorage-backed and are not connected to PostgreSQL. Actual payment processing, PDF/WhatsApp/SMS delivery, verified model catalogue, OCR for printed text, reliable offline synchronization, and a production audit trail are not implemented. Do not use this prototype as the only copy of real shop, customer, IMEI, or financial data.

## Requirements

- Node.js 22.12+
- npm
- Visual Studio Code
- Chrome or another modern browser

Check versions:

```bash
node --version
npm --version
```

## Install and run

```bash
npm install
npm run dev
```

Open the local URL printed by Vite, usually `http://localhost:5173`.

## Build check

```bash
npm run build
```

## Local Supabase foundation

The Supabase configuration, identity/tenant migration, and pgTAP tests are in `supabase/`. Supabase CLI 3.2.0 reported migration `202611190001` applied to the verified local database, and `supabase test db` passed all 42 assertions. For a fresh disposable local database, install the Supabase CLI using its official instructions, start Docker, then run `supabase start`, `supabase db reset`, and `supabase test db`. The reset command is destructive to that local database; it was not used during this verification.

Copy `.env.example` to an ignored local environment file and use the local API URL and publishable key printed by the CLI. The browser publishable key is not a secret; never put a secret/service-role key in a `VITE_*` variable. Hosted/production RLS and transaction behavior must be verified before production use.

When both variables are absent, StockPilot remains in unauthenticated LocalStorage prototype mode. When configured, it presents the separate Auth and shop/branch foundation; it does not read or write the existing financial LocalStorage records in that mode.

Run the production build after making changes:

```bash
npm run build
```

## Camera scanner

The inventory scanner uses `@zxing/browser` to read supported barcodes and QR codes using a camera. The user must grant camera permission. Browsers generally require HTTPS or a trusted local context such as `http://localhost`; plain HTTP over a laptop's local Wi-Fi IP may block camera access. The scanner does not read plain printed IMEI text (OCR) or prove that a device is genuine. Manual entry remains available.

Model identification is optional. A model/part-number field accepts values such as `MG6C4AH/A`, but a real catalogue lookup is not connected yet. Users can manually enter model details if a code is unavailable, unknown, or the internet is slow.

## MVP roadmap

1. Serialized IMEI intake and inventory view.
2. Camera barcode/QR scanning and quick checkout.
3. PDF receipts and WhatsApp/SMS sharing.
4. Daily sales and profit reporting.

The current browser-local workflows are for development and evaluation only. Validate the business rules and storage behavior before any real shop use.

## Security and data correctness roadmap

- Local shop and branch identity migration and RLS suite verified (42/42 assertions); hosted/production RLS and browser authentication flows remain unverified.
- Backend-enforced owner/admin/attendant permissions; never rely on frontend hiding alone for cost-price protection.
- Device-level unique identifier constraints and a full identifier history.
- Append-only audit events and server-side transaction rules.
- Branch transfers with request, in-transit and received states.
- Supplier payable and customer installment ledgers.
- Tested local persistence and offline synchronization with idempotency/conflict handling.
- Private storage for shop logos and server-side subscription plan enforcement.

Do not enter real customer details, real IMEIs or financial data into this demo. Use fictional identifiers while testing.
