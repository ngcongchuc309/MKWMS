# MKWMS

Minh Khanh Warehouse Management System (MKWMS) is a static Vietnamese warehouse web app using Supabase Auth and the Supabase Data API in the browser. It contains no price or monetary fields. The browser config contains only the Supabase project URL and publishable key; never add a secret or service-role key.

## Current workflows

- Product and partner management, multi-warehouse stock lookup, reservation and availability.
- Inbound orders: atomic draft or submit, locked after submission, approval, partial receipt batches and posted stock movements.
- Outbound orders: draft, submit, stock reservation on approval, automatic delivery creation, partial issue and posted stock movements.
- Delivery scheduling, carrier/driver details, delivery attempts, received quantities, retry orders and private file uploads for delivery proof and inbound documents.
- Stock transfers, count adjustments with approval, opening-balance Excel preview/validation/confirmation, and controlled stock reversal with a reason.
- Role and warehouse-scope administration for existing Supabase Auth users; audit log and Excel reports.

Order headers and item lines are created atomically; delivery details and attempt status are saved together. Database functions validate roles, warehouse scope, availability and quantities transactionally. Posted movement rows are append-only. A reversal creates a new audited movement; it never edits or deletes the original. See `mkwms-deploy/README.md` for the applied database migration list and initial setup notes.

## Deploy

Import the GitHub repository into Vercel with the project root set to the repository root. This is a static site: no build command or output directory is required. Pushes to `main` trigger the production deployment.

## Access setup

Create or invite accounts in Supabase Auth, then use the MKWMS **Người dùng & phân quyền** page to assign the profile role and warehouse scope. An administrator must already be provisioned for the first login. Users without an active profile cannot enter the app.
