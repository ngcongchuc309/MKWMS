# MKWMS deployment setup

This folder contains the Supabase database migrations for MKWMS. All migrations in this folder have been applied to the connected project. The core migration copies complete product-master fields from the existing `public."DS Hàng hoá"` table into `public.products`. It leaves the original table and all its rows untouched. Follow-up migrations revoke API execution of the project's internal `rls_auto_enable()` utility and reserve available stock transactionally when an outbound order is approved.

The legacy table contains 231 rows: 228 have SKU, name, and unit values that can be copied into the new product master; 221 have numeric stock quantities, while 7 have blank or non-numeric quantities. Because the legacy table does not identify the warehouse/location for its stock quantities, the migration does not copy those quantities into operational stock balances. The current website is still a browser demo and does not yet read or write these tables.

## Supabase setup

1. The connected Supabase project is `cstllaucehmhqoxdygdo` in `ap-northeast-1`. The migrations are already applied there.
2. Create the first user in Supabase Auth. Then add that user's profile and warehouse access in SQL Editor, replacing the UUID with the Auth user's ID:

```sql
insert into public.profiles(user_id, full_name, role)
values ('AUTH_USER_UUID', 'Minh Khanh Admin', 'admin');

insert into public.user_warehouses(user_id, warehouse_id)
select 'AUTH_USER_UUID', id from public.warehouses;
```

4. Create other users through Supabase Auth. Assign each a profile role and the appropriate rows in `user_warehouses`.

## Vercel setup

The website is static, so Vercel can serve `outputs/index.html` directly. The login and data client are in `outputs/mkwms-supabase.js` and `outputs/mkwms-config.js`. The browser config contains only the public Supabase URL and publishable key. Never place a Supabase secret/service-role key in browser code or a public deployment.

The migration enables Row Level Security and restricts data access to authenticated users and role/warehouse policies. Supabase requires both grants and RLS policies for exposed tables; this migration revokes broad client grants and adds table-specific access.

## Still required before production deployment

- Upload the site files to the intended empty GitHub repository and create a separate Vercel project; the existing `mkwms2` project is linked to an unrelated Java repository.
- Create the first user in Supabase Auth, then provision their `admin` profile and warehouse scope with the SQL above.
- Initial-stock import/adjustment workflow and posting receipts/issues are not yet wired to the frontend. Outbound approval checks and reserves existing stock, so it will reject an order while no stock balance exists.

The migration includes products, partners, warehouses, stock balances, inbound/outbound orders, delivery orders, inventory movements, audit logs, and an approval RPC that creates the first delivery order when a delivery-required outbound order is approved.
