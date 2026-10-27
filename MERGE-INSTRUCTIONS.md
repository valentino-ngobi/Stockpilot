# Merge these StockPilot updates into your existing repository

This update is intended for the existing StockPilot folder already open in VS Code. Do not create a new GitHub repository and do not replace your entire project with a second copy.

## Files to copy/replace

Copy the files from this update into the root of your existing project folder, preserving the folder paths. Replace matching files and add the new file:

- `package.json` (updated to include the camera barcode/QR scanner dependency)
- `README.md` (updated project status and roadmap)
- `src/App.tsx` (connects the module screens)
- `src/components/Sidebar.tsx` (adds Suppliers & credit navigation)
- `src/components/CameraScanner.tsx` (new camera scanner component)
- `src/pages/Inventory.tsx` (expanded inventory intake and scanner workflow)
- `src/pages/Operations.tsx` (new demo screens for sales, custody, repairs, closing, reports, supplier/customer credit, team/branches and settings)
- `src/styles/index.css` (scanner, inventory and module styles)

No other original source files need to be replaced by this update.

## Safe merge steps

1. In VS Code terminal, from the existing project folder, run `git status`.
2. If you have uncommitted changes, save or commit them before copying these files.
3. Extract this update ZIP to a temporary folder.
4. Copy the listed files from the extracted folder into your existing project, keeping the same relative paths. Approve replacement only for the listed matching files.
5. In your existing project terminal, run:

   ```bash
   npm install
   npm run dev
   ```

6. Test the Inventory scanner and visit each navigation item. Then run:

   ```bash
   npm run build
   git status
   ```

7. Review the changed files, then commit and push to your existing GitHub repository:

   ```bash
   git add package.json README.md src/App.tsx src/components/Sidebar.tsx src/components/CameraScanner.tsx src/pages/Inventory.tsx src/pages/Operations.tsx src/styles/index.css
   git commit -m "Expand inventory scanning and core module prototypes"
   git push
   ```

## Important limitations

This is a frontend prototype, not a complete backend implementation. Most module forms add fictional records only to the current page session. They do not persist after refresh and do not send payments, PDFs, WhatsApp messages, or SMS. Role enforcement, database constraints, secure audit logs, real catalogue lookup, OCR, PWA/offline storage and sync must be implemented and tested in later stages.
