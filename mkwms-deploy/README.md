# Supabase deployment and operations

Project: `cstllaucehmhqoxdygdo` (`ap-northeast-1`). The SQL files in `supabase/migrations/` match the migrations applied to the connected project. They create the operational schema, row-level security, role and warehouse checks, audit logging, order workflows, transactional stock movements, import and reversal RPCs.

## First administrator

Create a user in Supabase Auth, then provision the first administrator and warehouse scopes in the SQL Editor (replace the UUID with that Auth user ID):

```sql
insert into public.profiles(user_id, full_name, role, active)
values ('AUTH_USER_UUID', 'Administrator name', 'admin', true);

insert into public.user_warehouses(user_id, warehouse_id)
select 'AUTH_USER_UUID', id from public.warehouses where active;
```

After the first administrator can log in, create/invite other Auth users and assign their role and warehouse scope in MKWMS. User passwords remain managed by Supabase Auth.

## Operational rules

- Inbound/outbound header and item lines save atomically; submitted orders lock for edits; outbound approval reserves available stock and creates a delivery order in the same database transaction.
- Inbound receipts and outbound issues support partial batches and update stock only when posted. Delivery assignment and attempt status save in one transaction.
- A transfer applies both warehouse sides atomically. Count adjustments are posted after approval.
- Opening balances are imported from the Excel template after preview and explicit confirmation. The RPC rejects occupied stock locations.
- Posted transactions are immutable. Managers can request one controlled reversal with a required reason; reversal is rejected when it would consume reserved/insufficient stock.
- All exposed operational tables use RLS. RPCs require an authenticated user and enforce role/warehouse scope. Do not expose a service-role key.

## Current migrations

- `20261028020830_mkwms_core_schema`
- `20261028021036_revoke_public_rls_utility`
- `20261028021956_reserve_stock_on_outbound_approval`
- `20261028022101_restrict_outbound_client_updates`
- `20261028031038_mkwms_operational_workflows`
- `20261028031236_mkwms_user_administration`
- `20261028031817_mkwms_opening_balances_and_reversals`
- `20261028031927_restore_delivery_attempt_line_uniqueness`
- `20261028032350_limit_stock_reversal_to_safe_documents`
- `20261028032733_mkwms_order_attachments`
- `20261028033200_fix_order_document_warehouse_policy`
- `20261028033256_audit_order_document_uploads`
- `20261028033401_allocate_outbound_stock_by_location`
- `20261028034241_atomic_order_creation_and_indexes`
- `20261028034745_atomic_delivery_and_policy_cleanup`
- `20261028035335_lock_submitted_orders`
- `20261028040749_legacy_client_order_line_window`

## Deployment

Vercel serves the repository root as a static site. There is no build step. Commit and push the changes to `main`; Vercel builds the new production deployment automatically. The Supabase migrations listed above are already applied to the connected project.
