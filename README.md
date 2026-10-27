# StockPilot (working name)

A responsive frontend prototype for small phone and gadget retailers. The public brand name is still being reviewed.

## Current milestone

This project includes a dashboard, a serialized device inventory prototype, browser camera barcode/QR scanning, and demo UI flows for sales/POS, custody, repairs, daily closing, reports, supplier credit/customer layaway, team/branches, and settings.

**Important:** these are frontend prototypes with fictional demonstration data. They are not a production-ready retail system. Records are kept in page state and disappear when the page refreshes. There is no live authentication, database, real role enforcement, actual payment processing, PDF/WhatsApp/SMS delivery, verified model catalogue, OCR for printed text, PWA/offline sync, or production audit trail yet.

## Requirements

- Node.js 20.19+ or 22.12+
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

The updated project archive has not been build-verified in this environment because dependency installation timed out. Run the build locally and share any error output so we can fix it.

## Camera scanner

The inventory scanner uses `@zxing/browser` to read supported barcodes and QR codes using a camera. The user must grant camera permission. Browsers generally require HTTPS or a trusted local context such as `http://localhost`; plain HTTP over a laptop's local Wi-Fi IP may block camera access. The scanner does not read plain printed IMEI text (OCR) or prove that a device is genuine. Manual entry remains available.

Model identification is optional. A model/part-number field accepts values such as `MG6C4AH/A`, but a real catalogue lookup is not connected yet. Users can manually enter model details if a code is unavailable, unknown, or the internet is slow.

## MVP roadmap

1. Serialized IMEI intake and inventory view.
2. Camera barcode/QR scanning and quick checkout.
3. PDF receipts and WhatsApp/SMS sharing.
4. Daily sales and profit reporting.

The screens for the six core modules are scaffolds to help define and test the workflows. They need persistent data and business rules before real shop use.

## Security and data correctness roadmap

- Supabase Auth + PostgreSQL Row Level Security and shop membership.
- Backend-enforced owner/admin/attendant permissions; never rely on frontend hiding alone for cost-price protection.
- Device-level unique identifier constraints and a full identifier history.
- Append-only audit events and server-side transaction rules.
- Branch transfers with request, in-transit and received states.
- Supplier payable and customer installment ledgers.
- Tested local persistence and offline synchronization with idempotency/conflict handling.
- Private storage for shop logos and server-side subscription plan enforcement.

Do not enter real customer details, real IMEIs or financial data into this demo. Use fictional identifiers while testing.
