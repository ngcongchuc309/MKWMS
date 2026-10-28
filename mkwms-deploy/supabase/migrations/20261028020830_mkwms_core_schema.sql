-- MKWMS core schema for Supabase Postgres.
-- This migration contains no price or monetary fields.
create extension if not exists pgcrypto;
create sequence if not exists public.delivery_code_seq start with 1;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'warehouse_staff'
    check (role in ('admin','warehouse_manager','warehouse_staff','sales','delivery','accounting')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  address text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.warehouses(code, name) values
  ('BD', 'Kho chính — Bình Dương'),
  ('HN', 'Kho Hà Nội'),
  ('DN', 'Kho Đà Nẵng')
on conflict (code) do nothing;

create table if not exists public.user_warehouses (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  primary key (user_id, warehouse_id)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  category text not null default '',
  brand text not null default '',
  unit text not null,
  package_spec text not null default '',
  minimum_stock integer not null default 0 check (minimum_stock >= 0),
  active boolean not null default true,
  created_by uuid references public.profiles(user_id),
  updated_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Backfill complete product-master rows from the existing legacy sheet.
-- The legacy stock quantity is intentionally left in the source table because
-- that table does not identify a warehouse/location for those quantities.
insert into public.products (sku, name, unit, created_at)
select trim("Mã hàng"), trim("Tên hàng"), trim("Đơn vị tính"), now()
from public."DS Hàng hoá"
where nullif(trim("Mã hàng"), '') is not null
  and nullif(trim("Tên hàng"), '') is not null
  and nullif(trim("Đơn vị tính"), '') is not null
on conflict (sku) do nothing;

create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  partner_code text not null unique,
  partner_type text not null check (partner_type in ('customer','supplier','both')),
  name text not null,
  tax_code text not null default '',
  address text not null default '',
  contact_name text not null default '',
  phone text not null default '',
  email text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inbound_orders (
  id uuid primary key default gen_random_uuid(),
  document_code text not null unique,
  inbound_type text not null check (inbound_type in ('supplier','return','other')),
  supplier_id uuid references public.partners(id),
  warehouse_id uuid not null references public.warehouses(id),
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','posted','cancelled')),
  created_on date not null default current_date,
  delivery_on date,
  receiver_name text not null default '',
  receiver_phone text not null default '',
  notes text not null default '',
  created_by uuid not null references public.profiles(user_id),
  approved_by uuid references public.profiles(user_id),
  posted_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  posted_at timestamptz
);

create table if not exists public.inbound_order_lines (
  id uuid primary key default gen_random_uuid(),
  inbound_order_id uuid not null references public.inbound_orders(id) on delete restrict,
  product_id uuid not null references public.products(id),
  expected_quantity integer not null check (expected_quantity > 0),
  received_quantity integer check (received_quantity is null or received_quantity >= 0),
  location_code text not null default '',
  lot_code text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.outbound_orders (
  id uuid primary key default gen_random_uuid(),
  document_code text not null unique,
  outbound_type text not null check (outbound_type in ('sale','internal','other')),
  partner_id uuid references public.partners(id),
  partner_name text not null default '',
  warehouse_id uuid not null references public.warehouses(id),
  shipping_method text not null default 'delivery' check (shipping_method in ('delivery','pickup')),
  delivery_required boolean generated always as (shipping_method = 'delivery' and outbound_type = 'sale') stored,
  expected_delivery_date date,
  receiver_name text not null default '',
  receiver_phone text not null default '',
  delivery_address text not null default '',
  status text not null default 'draft' check (status in ('draft','pending_approval','approved','posted','cancelled')),
  created_on date not null default current_date,
  notes text not null default '',
  created_by uuid not null references public.profiles(user_id),
  approved_by uuid references public.profiles(user_id),
  posted_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  posted_at timestamptz
);

create table if not exists public.outbound_order_lines (
  id uuid primary key default gen_random_uuid(),
  outbound_order_id uuid not null references public.outbound_orders(id) on delete restrict,
  product_id uuid not null references public.products(id),
  requested_quantity integer not null check (requested_quantity > 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0),
  issued_quantity integer not null default 0 check (issued_quantity >= 0),
  location_code text not null default '',
  lot_code text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.stock_balances (
  warehouse_id uuid not null references public.warehouses(id),
  product_id uuid not null references public.products(id),
  location_code text not null default '',
  lot_code text not null default '',
  on_hand_quantity integer not null default 0 check (on_hand_quantity >= 0),
  reserved_quantity integer not null default 0 check (reserved_quantity >= 0 and reserved_quantity <= on_hand_quantity),
  available_quantity integer generated always as (on_hand_quantity - reserved_quantity) stored,
  updated_at timestamptz not null default now(),
  primary key (warehouse_id, product_id, location_code, lot_code)
);

create table if not exists public.delivery_orders (
  id uuid primary key default gen_random_uuid(),
  delivery_code text not null unique,
  outbound_order_id uuid not null references public.outbound_orders(id) on delete restrict,
  delivery_sequence integer not null default 1 check (delivery_sequence > 0),
  status text not null default 'waiting' check (status in ('waiting','in_transit','partial','delivered','failed','overdue')),
  expected_delivery_date date,
  receiver_name text not null default '',
  receiver_phone text not null default '',
  delivery_address text not null default '',
  carrier_name text not null default '',
  driver_name text not null default '',
  driver_phone text not null default '',
  vehicle_plate text not null default '',
  actual_delivery_at timestamptz,
  received_by text not null default '',
  proof_path text not null default '',
  created_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (outbound_order_id, delivery_sequence)
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.warehouses(id),
  product_id uuid not null references public.products(id),
  movement_type text not null check (movement_type in ('inbound','outbound','transfer_in','transfer_out','adjustment','reversal')),
  quantity_delta integer not null check (quantity_delta <> 0),
  source_type text not null,
  source_id uuid not null,
  location_code text not null default '',
  lot_code text not null default '',
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(user_id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_user_role()
returns text
language sql stable security definer
set search_path = ''
as $$ select p.role from public.profiles p where p.user_id = (select auth.uid()) and p.active $$;

create or replace function public.can_access_warehouse(target_warehouse uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(public.current_user_role() = 'admin', false)
    or exists (
      select 1 from public.user_warehouses uw
      where uw.user_id = (select auth.uid()) and uw.warehouse_id = target_warehouse
    )
$$;

create or replace function public.approve_outbound_order(target_order uuid)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  order_row public.outbound_orders%rowtype;
  new_delivery_id uuid;
  new_delivery_code text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  if coalesce(public.current_user_role(), '') not in ('admin','warehouse_manager') then
    raise exception 'Only an administrator or warehouse manager can approve outbound orders';
  end if;

  select * into order_row
  from public.outbound_orders
  where id = target_order
  for update;

  if not found then raise exception 'Outbound order not found'; end if;
  if order_row.status <> 'pending_approval' then raise exception 'Outbound order is not pending approval'; end if;
  if not public.can_access_warehouse(order_row.warehouse_id) then raise exception 'Warehouse access denied'; end if;

  update public.outbound_orders
  set status = 'approved', approved_by = (select auth.uid()), approved_at = now()
  where id = target_order;

  if order_row.delivery_required then
    new_delivery_code := 'GH-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.delivery_code_seq')::text, 6, '0');

    insert into public.delivery_orders (
      delivery_code, outbound_order_id, delivery_sequence, expected_delivery_date,
      receiver_name, receiver_phone, delivery_address, created_by
    ) values (
      new_delivery_code, target_order, 1, order_row.expected_delivery_date,
      order_row.receiver_name, order_row.receiver_phone, order_row.delivery_address, (select auth.uid())
    ) returning id into new_delivery_id;
  end if;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values ((select auth.uid()), 'approve', 'outbound_order', target_order,
          jsonb_build_object('delivery_order_id', new_delivery_id));
  return new_delivery_id;
end;
$$;

revoke all on function public.current_user_role() from public, anon;
revoke all on function public.can_access_warehouse(uuid) from public, anon;
revoke all on function public.approve_outbound_order(uuid) from public, anon;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.can_access_warehouse(uuid) to authenticated;
grant execute on function public.approve_outbound_order(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['profiles','warehouses','user_warehouses','products','partners','inbound_orders','inbound_order_lines','outbound_orders','outbound_order_lines','stock_balances','delivery_orders','inventory_movements','audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select on public.profiles, public.warehouses, public.user_warehouses, public.products, public.partners,
  public.inbound_orders, public.inbound_order_lines, public.outbound_orders, public.outbound_order_lines,
  public.stock_balances, public.delivery_orders, public.inventory_movements to authenticated;
grant insert, update on public.products, public.partners, public.inbound_orders, public.inbound_order_lines,
  public.outbound_orders, public.outbound_order_lines to authenticated;
grant update (status, expected_delivery_date, receiver_name, receiver_phone, delivery_address,
  carrier_name, driver_name, driver_phone, vehicle_plate, actual_delivery_at, received_by, proof_path, updated_at)
  on public.delivery_orders to authenticated;
grant select on public.audit_log to authenticated;
grant usage, select on sequence public.audit_log_id_seq to authenticated;

create policy "profiles self or admin read" on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or public.current_user_role() = 'admin');
create policy "admin manages profiles" on public.profiles for update to authenticated
  using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');

create policy "warehouse scope read" on public.warehouses for select to authenticated
  using (public.can_access_warehouse(id));
create policy "admin manages warehouses" on public.warehouses for all to authenticated
  using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');
create policy "user reads own warehouse scope" on public.user_warehouses for select to authenticated
  using (user_id = (select auth.uid()) or public.current_user_role() = 'admin');
create policy "admin manages warehouse scope" on public.user_warehouses for all to authenticated
  using (public.current_user_role() = 'admin') with check (public.current_user_role() = 'admin');

create policy "authenticated reads products" on public.products for select to authenticated using (true);
create policy "warehouse roles add products" on public.products for insert to authenticated
  with check (public.current_user_role() in ('admin','warehouse_manager','warehouse_staff'));
create policy "managers update products" on public.products for update to authenticated
  using (public.current_user_role() in ('admin','warehouse_manager'))
  with check (public.current_user_role() in ('admin','warehouse_manager'));

create policy "authenticated reads partners" on public.partners for select to authenticated using (true);
create policy "authorized roles add partners" on public.partners for insert to authenticated
  with check (public.current_user_role() in ('admin','warehouse_manager','sales'));
create policy "authorized roles update partners" on public.partners for update to authenticated
  using (public.current_user_role() in ('admin','warehouse_manager','sales'))
  with check (public.current_user_role() in ('admin','warehouse_manager','sales'));

create policy "read inbound in warehouse scope" on public.inbound_orders for select to authenticated
  using (public.can_access_warehouse(warehouse_id));
create policy "authorized create inbound" on public.inbound_orders for insert to authenticated
  with check (public.current_user_role() in ('admin','warehouse_manager','warehouse_staff') and public.can_access_warehouse(warehouse_id) and created_by = (select auth.uid()));
create policy "authorized update draft inbound" on public.inbound_orders for update to authenticated
  using (status in ('draft','pending_approval') and public.current_user_role() in ('admin','warehouse_manager','warehouse_staff') and public.can_access_warehouse(warehouse_id))
  with check (status in ('draft','pending_approval') and public.can_access_warehouse(warehouse_id));
create policy "read inbound lines by parent" on public.inbound_order_lines for select to authenticated
  using (exists (select 1 from public.inbound_orders o where o.id = inbound_order_id and public.can_access_warehouse(o.warehouse_id)));
create policy "add inbound lines to editable order" on public.inbound_order_lines for insert to authenticated
  with check (exists (select 1 from public.inbound_orders o where o.id = inbound_order_id and o.status in ('draft','pending_approval') and public.can_access_warehouse(o.warehouse_id)));

create policy "read outbound in warehouse scope" on public.outbound_orders for select to authenticated
  using (public.can_access_warehouse(warehouse_id));
create policy "authorized create outbound" on public.outbound_orders for insert to authenticated
  with check (public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','sales') and public.can_access_warehouse(warehouse_id) and created_by = (select auth.uid()));
create policy "authorized update draft outbound" on public.outbound_orders for update to authenticated
  using (status in ('draft','pending_approval') and public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','sales') and public.can_access_warehouse(warehouse_id))
  with check (status in ('draft','pending_approval') and public.can_access_warehouse(warehouse_id));
create policy "read outbound lines by parent" on public.outbound_order_lines for select to authenticated
  using (exists (select 1 from public.outbound_orders o where o.id = outbound_order_id and public.can_access_warehouse(o.warehouse_id)));
create policy "add outbound lines to editable order" on public.outbound_order_lines for insert to authenticated
  with check (exists (select 1 from public.outbound_orders o where o.id = outbound_order_id and o.status in ('draft','pending_approval') and public.can_access_warehouse(o.warehouse_id)));

create policy "read balances in warehouse scope" on public.stock_balances for select to authenticated
  using (public.can_access_warehouse(warehouse_id));
create policy "read deliveries in warehouse scope" on public.delivery_orders for select to authenticated
  using (exists (select 1 from public.outbound_orders o where o.id = outbound_order_id and public.can_access_warehouse(o.warehouse_id)));
create policy "authorized update delivery details" on public.delivery_orders for update to authenticated
  using (public.current_user_role() in ('admin','warehouse_manager','delivery') and exists (select 1 from public.outbound_orders o where o.id = outbound_order_id and public.can_access_warehouse(o.warehouse_id)))
  with check (public.current_user_role() in ('admin','warehouse_manager','delivery'));
create policy "read movements in warehouse scope" on public.inventory_movements for select to authenticated
  using (public.can_access_warehouse(warehouse_id));
create policy "managers read audit log" on public.audit_log for select to authenticated
  using (public.current_user_role() in ('admin','warehouse_manager'));

create index if not exists products_name_idx on public.products using gin (to_tsvector('simple', name));
create index if not exists inbound_orders_status_idx on public.inbound_orders(status, created_at desc);
create index if not exists outbound_orders_status_idx on public.outbound_orders(status, created_at desc);
create index if not exists delivery_orders_date_status_idx on public.delivery_orders(expected_delivery_date, status);
create index if not exists inventory_movements_product_date_idx on public.inventory_movements(product_id, created_at desc);
