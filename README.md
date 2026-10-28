# MKWMS

MKWMS is a Vietnamese warehouse management interface for Minh Khanh. It is served as a static site and uses Supabase Auth and the Supabase Data API from the browser.

## Deploy

Import this repository into Vercel with the project root set to the repository root. No build command or build output directory is required. `index.html` is the entry page.

The browser configuration in `mkwms-config.js` contains only the Supabase project URL and publishable key. Never add a Supabase secret or service-role key to this repository.

## First administrator

Create the first account in Supabase Auth. Copy its Auth user UUID, then run the provisioning SQL in `mkwms-deploy/README.md` to add an administrator profile and grant warehouse scope. Users without an active profile and warehouse assignment cannot read operational data.

## Data status

The site reads products, warehouses, stock, partners, inbound orders, outbound orders, and delivery orders from Supabase after sign-in. Excel product imports are written after validation and explicit confirmation. Outbound approval is handled by a database RPC that reserves available stock and creates the associated delivery order atomically.

The existing legacy table `public."DS Hàng hoá"` remains unchanged. Product master fields were copied from 228 complete rows; old stock quantities were not loaded into warehouse balances because the source data has no warehouse or location identity. Load a verified opening balance before approving outbound orders.

Inbound receipt posting, outbound issue posting, inventory adjustment, user administration, and reports still need their production workflows wired to the database.
