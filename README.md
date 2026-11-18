# StockPilot (working name)

A responsive frontend prototype for small phone and gadget retailers. The public brand name is still being reviewed.

## Current milestone

This project includes a dashboard, serialized device and accessory inventory, browser camera barcode/QR scanning, and working browser-local flows for sales/POS, purchases, supplier credit/customer receivables, daily closing, reports, and settings. Custody, repairs, team/branches, and some navigation screens remain demonstrations.

**Important:** StockPilot is not a production-ready retail system. Core inventory, sales, purchases, supplier-credit, settings, exchange-rate, and closing records are persisted in this browser's LocalStorage and normally remain after refresh. Other screens still use demonstration data or page state. Clearing browser data, changing browsers, or losing this device can lose locally stored records. LocalStorage does not provide a backend, reliable multi-device synchronization, atomic multi-record transactions, or strong multi-user concurrency control.

There is no live authentication, server-enforced role authorization, actual payment processing, PDF/WhatsApp/SMS delivery, verified model catalogue, OCR for printed text, reliable offline synchronization, or production audit trail yet. Do not use this prototype as the only copy of real shop, customer, IMEI, or financial data.

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

- Supabase Auth + PostgreSQL Row Level Security and shop membership.
- Backend-enforced owner/admin/attendant permissions; never rely on frontend hiding alone for cost-price protection.
- Device-level unique identifier constraints and a full identifier history.
- Append-only audit events and server-side transaction rules.
- Branch transfers with request, in-transit and received states.
- Supplier payable and customer installment ledgers.
- Tested local persistence and offline synchronization with idempotency/conflict handling.
- Private storage for shop logos and server-side subscription plan enforcement.

Do not enter real customer details, real IMEIs or financial data into this demo. Use fictional identifiers while testing.
