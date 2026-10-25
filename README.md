# StockPilot

StockPilot is a responsive retail operations app for small phone and gadget shops.

## Current milestone

This repository currently contains a frontend prototype with fictional demonstration data. It does not yet provide real authentication, a backend, durable business records, or secure multi-user access.

## Requirements

- Node.js 20.19+ or 22.12+
- npm
- Visual Studio Code
- Chrome or another modern browser

Check your versions:

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

## Test on a phone on the same Wi-Fi

1. Start Vite with `npm run dev -- --host 0.0.0.0`.
2. Find your laptop's local IPv4 address.
3. On your phone, connected to the same Wi-Fi, open `http://YOUR-LAPTOP-IP:5173`.
4. If it does not load, check your laptop firewall and Wi-Fi network isolation settings.

Do not expose this development server to public networks.

## Project structure

```text
stockpilot/
├── public/
├── src/
│   ├── components/
│   ├── data/
│   ├── pages/
│   ├── styles/
│   ├── App.tsx
│   └── main.tsx
├── .env.example
├── index.html
├── package.json
└── README.md
```

## Security roadmap

The next stages will integrate Supabase Auth, PostgreSQL Row Level Security, shop membership/roles, protected logo uploads, audit history and tested offline synchronization. The frontend alone must never be treated as a security boundary.
