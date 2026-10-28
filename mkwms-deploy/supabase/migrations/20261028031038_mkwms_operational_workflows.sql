-- Transactional inventory workflows for MKWMS.
-- Inventory balances are changed only by database functions; movement rows are append-only.

create table if not exists public.inbound_receipt_batches (
  id uuid primary key,
  inbound_order_id uuid not null references public.inbound_orders(id) on delete restrict,
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now()
);

create table if not exists public.outbound_issue_batches (
  id uuid primary key,
  outbound_order_id uuid not null references public.outbound_orders(id) on delete restrict,
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now()
);

create table if not exists public.delivery_order_lines (
  id uuid primary key default gen_random_uuid(),
  delivery_order_id uuid not null references public.delivery_orders(id) on delete restrict,
  outbound_order_line_id uuid not null references public.outbound_order_lines(id) on delete restrict,
  quantity_delivered integer not null check (quantity_delivered >= 0),
  created_at timestamptz not null default now(),
  unique (delivery_order_id, outbound_order_line_id)
);

create table if not exists public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  document_code text not null unique,
  warehouse_id uuid not null references public.warehouses(id),
  reason text not null,
  status text not null default 'pending_approval' check (status in ('pending_approval','posted','cancelled')),
  created_by uuid not null references public.profiles(user_id),
  approved_by uuid references public.profiles(user_id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  posted_at timestamptz
);

create table if not exists public.stock_adjustment_lines (
  id uuid primary key default gen_random_uuid(),
  adjustment_id uuid not null references public.stock_adjustments(id) on delete restrict,
  product_id uuid not null references public.products(id),
  location_code text not null default '',
  lot_code text not null default '',
  counted_quantity integer not null check (counted_quantity >= 0),
  system_quantity integer,
  quantity_delta integer,
  created_at timestamptz not null default now(),
  unique (adjustment_id, product_id, location_code, lot_code)
);

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  document_code text not null unique,
  from_warehouse_id uuid not null references public.warehouses(id),
  to_warehouse_id uuid not null references public.warehouses(id),
  status text not null default 'posted' check (status in ('posted','reversed')),
  created_by uuid not null references public.profiles(user_id),
  created_at timestamptz not null default now(),
  check (from_warehouse_id <> to_warehouse_id)
);

create table if not exists public.stock_transfer_lines (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.stock_transfers(id) on delete restrict,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  from_location_code text not null default '',
  from_lot_code text not null default '',
  to_location_code text not null default '',
  to_lot_code text not null default '',
  created_at timestamptz not null default now()
);

alter table public.inbound_receipt_batches enable row level security;
alter table public.outbound_issue_batches enable row level security;
alter table public.delivery_order_lines enable row level security;
alter table public.stock_adjustments enable row level security;
alter table public.stock_adjustment_lines enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_lines enable row level security;
revoke all on public.inbound_receipt_batches, public.outbound_issue_batches,
  public.delivery_order_lines, public.stock_adjustments, public.stock_adjustment_lines,
  public.stock_transfers, public.stock_transfer_lines from anon, authenticated;
grant select on public.delivery_order_lines, public.stock_adjustments, public.stock_adjustment_lines,
  public.stock_transfers, public.stock_transfer_lines to authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.user_warehouses to authenticated;
grant insert, update, delete on public.warehouses to authenticated;

create policy "read delivery attempt quantities in warehouse scope" on public.delivery_order_lines
  for select to authenticated using (
    exists (select 1 from public.delivery_orders d join public.outbound_orders o on o.id=d.outbound_order_id
      where d.id=delivery_order_id and public.can_access_warehouse(o.warehouse_id))
  );
create policy "read adjustments in warehouse scope" on public.stock_adjustments
  for select to authenticated using (public.can_access_warehouse(warehouse_id));
create policy "read adjustment lines in warehouse scope" on public.stock_adjustment_lines
  for select to authenticated using (
    exists (select 1 from public.stock_adjustments a where a.id=adjustment_id and public.can_access_warehouse(a.warehouse_id))
  );
create policy "read transfers in warehouse scope" on public.stock_transfers
  for select to authenticated using (public.can_access_warehouse(from_warehouse_id) or public.can_access_warehouse(to_warehouse_id));
create policy "read transfer lines in warehouse scope" on public.stock_transfer_lines
  for select to authenticated using (
    exists (select 1 from public.stock_transfers t where t.id=transfer_id
      and (public.can_access_warehouse(t.from_warehouse_id) or public.can_access_warehouse(t.to_warehouse_id)))
  );

create or replace function public.write_audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  before_row jsonb;
  after_row jsonb;
  changed text[];
  target_id uuid;
begin
  if tg_op = 'INSERT' then
    after_row := to_jsonb(new);
    changed := array(select jsonb_object_keys(after_row));
    target_id := coalesce(nullif(after_row->>'id','')::uuid, nullif(after_row->>'user_id','')::uuid);
  else
    before_row := to_jsonb(old);
    after_row := to_jsonb(new);
    select coalesce(array_agg(k), array[]::text[]) into changed
    from jsonb_object_keys(after_row) as keys(k)
    where after_row->k is distinct from before_row->k;
    target_id := coalesce(nullif(after_row->>'id','')::uuid, nullif(after_row->>'user_id','')::uuid);
  end if;
  insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
  values ((select auth.uid()), lower(tg_op), tg_table_name, target_id,
          jsonb_build_object('changed_fields', changed));
  return new;
end;
$$;
revoke all on function public.write_audit_row() from public, anon, authenticated;

drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles after insert or update on public.profiles for each row execute function public.write_audit_row();
drop trigger if exists audit_warehouses on public.warehouses;
create trigger audit_warehouses after insert or update on public.warehouses for each row execute function public.write_audit_row();
drop trigger if exists audit_products on public.products;
create trigger audit_products after insert or update on public.products for each row execute function public.write_audit_row();
drop trigger if exists audit_partners on public.partners;
create trigger audit_partners after insert or update on public.partners for each row execute function public.write_audit_row();
drop trigger if exists audit_inbound_orders on public.inbound_orders;
create trigger audit_inbound_orders after insert or update on public.inbound_orders for each row execute function public.write_audit_row();
drop trigger if exists audit_outbound_orders on public.outbound_orders;
create trigger audit_outbound_orders after insert or update on public.outbound_orders for each row execute function public.write_audit_row();
drop trigger if exists audit_delivery_orders on public.delivery_orders;
create trigger audit_delivery_orders after insert or update on public.delivery_orders for each row execute function public.write_audit_row();
drop trigger if exists audit_stock_adjustments on public.stock_adjustments;
create trigger audit_stock_adjustments after insert or update on public.stock_adjustments for each row execute function public.write_audit_row();
drop trigger if exists audit_stock_transfers on public.stock_transfers;
create trigger audit_stock_transfers after insert or update on public.stock_transfers for each row execute function public.write_audit_row();

create or replace function public.submit_inbound_order(target_order uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare o public.inbound_orders%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  select * into o from public.inbound_orders where id=target_order for update;
  if not found then raise exception 'Inbound order not found'; end if;
  if o.status <> 'draft' then raise exception 'Only draft inbound orders can be submitted'; end if;
  if not public.can_access_warehouse(o.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  if not exists(select 1 from public.inbound_order_lines where inbound_order_id=target_order) then raise exception 'Inbound order must contain at least one item'; end if;
  update public.inbound_orders set status='pending_approval' where id=target_order;
end;
$$;

create or replace function public.approve_inbound_order(target_order uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare o public.inbound_orders%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can approve inbound orders'; end if;
  select * into o from public.inbound_orders where id=target_order for update;
  if not found then raise exception 'Inbound order not found'; end if;
  if o.status <> 'pending_approval' then raise exception 'Inbound order is not pending approval'; end if;
  if not public.can_access_warehouse(o.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  update public.inbound_orders set status='approved', approved_by=(select auth.uid()), approved_at=now() where id=target_order;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values ((select auth.uid()),'approve','inbound_order',target_order,'{}'::jsonb);
end;
$$;

create or replace function public.post_inbound_receipt(target_order uuid, idempotency_key uuid, receipt_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.inbound_orders%rowtype;
  item jsonb;
  line_row public.inbound_order_lines%rowtype;
  qty integer;
  loc text;
  lot text;
  batch_id uuid := idempotency_key;
  complete boolean;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','warehouse_staff') then raise exception 'Role cannot receive stock'; end if;
  if batch_id is null or jsonb_typeof(receipt_lines) <> 'array' or jsonb_array_length(receipt_lines)=0 then raise exception 'Receipt batch and at least one line are required'; end if;
  select * into o from public.inbound_orders where id=target_order for update;
  if not found then raise exception 'Inbound order not found'; end if;
  if o.status <> 'approved' then raise exception 'Inbound order must be approved before receiving'; end if;
  if not public.can_access_warehouse(o.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  insert into public.inbound_receipt_batches(id,inbound_order_id,created_by)
  values(batch_id,target_order,(select auth.uid())) on conflict (id) do nothing;
  if not found then
    if not exists(select 1 from public.inbound_receipt_batches b where b.id=batch_id and b.inbound_order_id=target_order and b.created_by=(select auth.uid())) then raise exception 'Idempotency key already used'; end if;
    return jsonb_build_object('duplicate',true);
  end if;
  for item in select value from jsonb_array_elements(receipt_lines) loop
    qty := (item->>'quantity')::integer;
    if qty < 0 then raise exception 'Received quantity cannot be negative'; end if;
    if qty=0 then continue; end if;
    select * into line_row from public.inbound_order_lines where id=(item->>'line_id')::uuid and inbound_order_id=target_order for update;
    if not found then raise exception 'Inbound line not found'; end if;
    if coalesce(line_row.received_quantity,0)+qty > line_row.expected_quantity then raise exception 'Received quantity exceeds expected quantity'; end if;
    loc := coalesce(nullif(item->>'location_code',''),line_row.location_code,'');
    lot := coalesce(nullif(item->>'lot_code',''),line_row.lot_code,'');
    update public.inbound_order_lines set received_quantity=coalesce(received_quantity,0)+qty, location_code=loc, lot_code=lot where id=line_row.id;
    insert into public.stock_balances(warehouse_id,product_id,location_code,lot_code,on_hand_quantity,reserved_quantity,updated_at)
    values(o.warehouse_id,line_row.product_id,loc,lot,qty,0,now())
    on conflict(warehouse_id,product_id,location_code,lot_code) do update set on_hand_quantity=public.stock_balances.on_hand_quantity+excluded.on_hand_quantity,updated_at=now();
    insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by)
    values(o.warehouse_id,line_row.product_id,'inbound',qty,'inbound_receipt',batch_id,loc,lot,(select auth.uid()));
  end loop;
  if not exists(select 1 from public.inventory_movements m where m.source_id=batch_id) then raise exception 'Receipt batch contains no positive quantities'; end if;
  select not exists(select 1 from public.inbound_order_lines l where l.inbound_order_id=target_order and coalesce(l.received_quantity,0)<l.expected_quantity) into complete;
  if complete then update public.inbound_orders set status='posted',posted_by=(select auth.uid()),posted_at=now() where id=target_order; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'receive','inbound_order',target_order,jsonb_build_object('batch_id',batch_id,'complete',complete));
  return jsonb_build_object('duplicate',false,'complete',complete,'batch_id',batch_id);
end;
$$;

create or replace function public.post_outbound_issue(target_order uuid, idempotency_key uuid, issue_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.outbound_orders%rowtype;
  item jsonb;
  line_row public.outbound_order_lines%rowtype;
  stock_row public.stock_balances%rowtype;
  qty integer;
  batch_id uuid := idempotency_key;
  complete boolean;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','warehouse_staff') then raise exception 'Role cannot issue stock'; end if;
  if batch_id is null or jsonb_typeof(issue_lines) <> 'array' or jsonb_array_length(issue_lines)=0 then raise exception 'Issue batch and at least one line are required'; end if;
  select * into o from public.outbound_orders where id=target_order for update;
  if not found then raise exception 'Outbound order not found'; end if;
  if o.status <> 'approved' then raise exception 'Outbound order must be approved before issuing'; end if;
  if not public.can_access_warehouse(o.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  insert into public.outbound_issue_batches(id,outbound_order_id,created_by)
  values(batch_id,target_order,(select auth.uid())) on conflict(id) do nothing;
  if not found then
    if not exists(select 1 from public.outbound_issue_batches b where b.id=batch_id and b.outbound_order_id=target_order and b.created_by=(select auth.uid())) then raise exception 'Idempotency key already used'; end if;
    return jsonb_build_object('duplicate',true);
  end if;
  for item in select value from jsonb_array_elements(issue_lines) loop
    qty := (item->>'quantity')::integer;
    if qty <= 0 then raise exception 'Issue quantity must be positive'; end if;
    select * into line_row from public.outbound_order_lines where id=(item->>'line_id')::uuid and outbound_order_id=target_order for update;
    if not found then raise exception 'Outbound line not found'; end if;
    if qty > line_row.reserved_quantity then raise exception 'Issue quantity exceeds reserved quantity'; end if;
    select * into stock_row from public.stock_balances where warehouse_id=o.warehouse_id and product_id=line_row.product_id and location_code=line_row.location_code and lot_code=line_row.lot_code for update;
    if not found or stock_row.on_hand_quantity < qty or stock_row.reserved_quantity < qty then raise exception 'Stock reservation is no longer available'; end if;
    update public.stock_balances set on_hand_quantity=on_hand_quantity-qty,reserved_quantity=reserved_quantity-qty,updated_at=now()
    where warehouse_id=o.warehouse_id and product_id=line_row.product_id and location_code=line_row.location_code and lot_code=line_row.lot_code;
    update public.outbound_order_lines set issued_quantity=issued_quantity+qty,reserved_quantity=reserved_quantity-qty where id=line_row.id;
    insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by)
    values(o.warehouse_id,line_row.product_id,'outbound',-qty,'outbound_issue',batch_id,line_row.location_code,line_row.lot_code,(select auth.uid()));
  end loop;
  select not exists(select 1 from public.outbound_order_lines l where l.outbound_order_id=target_order and l.issued_quantity<l.requested_quantity) into complete;
  if complete then update public.outbound_orders set status='posted',posted_by=(select auth.uid()),posted_at=now() where id=target_order; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'issue','outbound_order',target_order,jsonb_build_object('batch_id',batch_id,'complete',complete));
  return jsonb_build_object('duplicate',false,'complete',complete,'batch_id',batch_id);
end;
$$;

create or replace function public.create_stock_adjustment(target_warehouse uuid, adjustment_code text, adjustment_reason text, adjustment_lines jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare new_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','warehouse_staff') then raise exception 'Role cannot create stock counts'; end if;
  if not public.can_access_warehouse(target_warehouse) then raise exception 'Warehouse access denied'; end if;
  if nullif(trim(adjustment_code),'') is null or nullif(trim(adjustment_reason),'') is null or jsonb_typeof(adjustment_lines)<>'array' or jsonb_array_length(adjustment_lines)=0 then raise exception 'Adjustment code, reason and lines are required'; end if;
  insert into public.stock_adjustments(document_code,warehouse_id,reason,created_by)
  values(trim(adjustment_code),target_warehouse,trim(adjustment_reason),(select auth.uid())) returning id into new_id;
  insert into public.stock_adjustment_lines(adjustment_id,product_id,location_code,lot_code,counted_quantity)
  select new_id,(x->>'product_id')::uuid,coalesce(x->>'location_code',''),coalesce(x->>'lot_code',''),(x->>'counted_quantity')::integer
  from jsonb_array_elements(adjustment_lines) x;
  return new_id;
end;
$$;

create or replace function public.approve_stock_adjustment(target_adjustment uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.stock_adjustments%rowtype;
  l record;
  current_on_hand integer;
  current_reserved integer;
  delta integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can approve adjustments'; end if;
  select * into a from public.stock_adjustments where id=target_adjustment for update;
  if not found then raise exception 'Adjustment not found'; end if;
  if a.status <> 'pending_approval' then raise exception 'Adjustment is not pending approval'; end if;
  if not public.can_access_warehouse(a.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  for l in select * from public.stock_adjustment_lines where adjustment_id=target_adjustment order by product_id,location_code,lot_code for update loop
    select on_hand_quantity,reserved_quantity into current_on_hand,current_reserved from public.stock_balances
    where warehouse_id=a.warehouse_id and product_id=l.product_id and location_code=l.location_code and lot_code=l.lot_code for update;
    if not found then current_on_hand:=0; current_reserved:=0; end if;
    delta:=l.counted_quantity-current_on_hand;
    if l.counted_quantity<current_reserved then raise exception 'Counted quantity is below reserved stock for product %',l.product_id; end if;
    update public.stock_adjustment_lines set system_quantity=current_on_hand,quantity_delta=delta where id=l.id;
    if delta<>0 then
      insert into public.stock_balances(warehouse_id,product_id,location_code,lot_code,on_hand_quantity,reserved_quantity,updated_at)
      values(a.warehouse_id,l.product_id,l.location_code,l.lot_code,l.counted_quantity,0,now())
      on conflict(warehouse_id,product_id,location_code,lot_code) do update set on_hand_quantity=excluded.on_hand_quantity,updated_at=now();
      insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by)
      values(a.warehouse_id,l.product_id,'adjustment',delta,'stock_adjustment',a.id,l.location_code,l.lot_code,(select auth.uid()));
    end if;
  end loop;
  update public.stock_adjustments set status='posted',approved_by=(select auth.uid()),approved_at=now(),posted_at=now() where id=target_adjustment;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'approve_and_post','stock_adjustment',target_adjustment,jsonb_build_object('reason',a.reason));
end;
$$;

create or replace function public.transfer_stock(from_warehouse uuid, to_warehouse uuid, transfer_code text, transfer_lines jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  transfer_id uuid;
  item jsonb;
  qty integer;
  v_product_id uuid;
  from_loc text;
  from_lot text;
  to_loc text;
  to_lot text;
  source_balance public.stock_balances%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can transfer stock'; end if;
  if from_warehouse=to_warehouse or not public.can_access_warehouse(from_warehouse) or not public.can_access_warehouse(to_warehouse) then raise exception 'Source and destination warehouses must be different and accessible'; end if;
  if nullif(trim(transfer_code),'') is null or jsonb_typeof(transfer_lines)<>'array' or jsonb_array_length(transfer_lines)=0 then raise exception 'Transfer code and lines are required'; end if;
  insert into public.stock_transfers(document_code,from_warehouse_id,to_warehouse_id,created_by)
  values(trim(transfer_code),from_warehouse,to_warehouse,(select auth.uid())) returning id into transfer_id;
  for item in select value from jsonb_array_elements(transfer_lines) loop
    v_product_id:=(item->>'product_id')::uuid; qty:=(item->>'quantity')::integer;
    from_loc:=coalesce(item->>'from_location_code',''); from_lot:=coalesce(item->>'from_lot_code','');
    to_loc:=coalesce(item->>'to_location_code',''); to_lot:=coalesce(item->>'to_lot_code','');
    if qty<=0 then raise exception 'Transfer quantity must be positive'; end if;
    select * into source_balance from public.stock_balances where warehouse_id=from_warehouse and product_id=v_product_id and location_code=from_loc and lot_code=from_lot for update;
    if not found or source_balance.available_quantity<qty then raise exception 'Insufficient available stock to transfer product %',v_product_id; end if;
    update public.stock_balances set on_hand_quantity=on_hand_quantity-qty,updated_at=now() where warehouse_id=from_warehouse and product_id=v_product_id and location_code=from_loc and lot_code=from_lot;
    insert into public.stock_balances(warehouse_id,product_id,location_code,lot_code,on_hand_quantity,reserved_quantity,updated_at)
    values(to_warehouse,v_product_id,to_loc,to_lot,qty,0,now())
    on conflict(warehouse_id,product_id,location_code,lot_code) do update set on_hand_quantity=public.stock_balances.on_hand_quantity+excluded.on_hand_quantity,updated_at=now();
    insert into public.stock_transfer_lines(transfer_id,product_id,quantity,from_location_code,from_lot_code,to_location_code,to_lot_code)
    values(transfer_id,v_product_id,qty,from_loc,from_lot,to_loc,to_lot);
    insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by)
    values(from_warehouse,v_product_id,'transfer_out',-qty,'stock_transfer',transfer_id,from_loc,from_lot,(select auth.uid())),
          (to_warehouse,v_product_id,'transfer_in',qty,'stock_transfer',transfer_id,to_loc,to_lot,(select auth.uid()));
  end loop;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'transfer','stock_transfer',transfer_id,jsonb_build_object('from_warehouse',from_warehouse,'to_warehouse',to_warehouse));
  return transfer_id;
end;
$$;

create or replace function public.record_delivery_attempt(target_delivery uuid, next_status text, received_name text, actual_time timestamptz, proof text, delivered_lines jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.delivery_orders%rowtype;
  o public.outbound_orders%rowtype;
  item jsonb;
  line_row public.outbound_order_lines%rowtype;
  qty integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','delivery') then raise exception 'Role cannot update deliveries'; end if;
  if next_status not in ('waiting','in_transit','partial','delivered','failed','overdue') then raise exception 'Invalid delivery status'; end if;
  select * into d from public.delivery_orders where id=target_delivery for update;
  if not found then raise exception 'Delivery order not found'; end if;
  select * into o from public.outbound_orders where id=d.outbound_order_id for update;
  if not public.can_access_warehouse(o.warehouse_id) then raise exception 'Warehouse access denied'; end if;
  if jsonb_typeof(delivered_lines)<>'array' then raise exception 'Delivered lines must be an array'; end if;
  for item in select value from jsonb_array_elements(delivered_lines) loop
    qty:=(item->>'quantity')::integer;
    if qty<0 then raise exception 'Delivered quantity cannot be negative'; end if;
    select * into line_row from public.outbound_order_lines where id=(item->>'line_id')::uuid and outbound_order_id=o.id for update;
    if not found then raise exception 'Outbound line not found'; end if;
    if coalesce(line_row.issued_quantity,0)<1 then raise exception 'An item cannot be delivered before it is issued from the warehouse'; end if;
    if qty>line_row.issued_quantity - coalesce((select sum(dl.quantity_delivered) from public.delivery_order_lines dl join public.delivery_orders od on od.id=dl.delivery_order_id where od.outbound_order_id=o.id and dl.outbound_order_line_id=line_row.id and od.id<>target_delivery),0) then raise exception 'Delivered quantity exceeds the remaining issued quantity'; end if;
    insert into public.delivery_order_lines(delivery_order_id,outbound_order_line_id,quantity_delivered)
    values(target_delivery,line_row.id,qty)
    on conflict(delivery_order_id,outbound_order_line_id) do update set quantity_delivered=excluded.quantity_delivered;
  end loop;
  if next_status='partial' and not exists(select 1 from public.delivery_order_lines where delivery_order_id=target_delivery and quantity_delivered>0) then raise exception 'Partial delivery must record at least one received quantity'; end if;
  if next_status='delivered' and exists(
    select 1 from public.outbound_order_lines l where l.outbound_order_id=o.id and l.issued_quantity >
      coalesce((select sum(dl.quantity_delivered) from public.delivery_order_lines dl join public.delivery_orders dd on dd.id=dl.delivery_order_id where dd.outbound_order_id=o.id and dl.outbound_order_line_id=l.id),0)
  ) then raise exception 'All issued quantities must be received before marking delivery complete'; end if;
  if next_status in ('partial','delivered') and nullif(trim(coalesce(received_name,'')),'') is null then raise exception 'Receiver name is required'; end if;
  update public.delivery_orders set status=next_status,received_by=coalesce(received_name,''),actual_delivery_at=case when next_status in ('partial','delivered','failed') then coalesce(actual_time,now()) else actual_time end,proof_path=coalesce(proof,''),updated_at=now() where id=target_delivery;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'update_delivery','delivery_order',target_delivery,jsonb_build_object('status',next_status));
end;
$$;

create or replace function public.create_delivery_retry(target_delivery uuid, new_expected_date date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare old public.delivery_orders%rowtype; next_id uuid; seq integer; code text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','delivery') then raise exception 'Role cannot schedule delivery retry'; end if;
  select * into old from public.delivery_orders where id=target_delivery for update;
  if not found then raise exception 'Delivery order not found'; end if;
  if old.status not in ('partial','failed','overdue') then raise exception 'A retry can only be created after a partial, failed or overdue attempt'; end if;
  if not exists(select 1 from public.outbound_orders o where o.id=old.outbound_order_id and public.can_access_warehouse(o.warehouse_id)) then raise exception 'Warehouse access denied'; end if;
  select coalesce(max(delivery_sequence),0)+1 into seq from public.delivery_orders where outbound_order_id=old.outbound_order_id;
  code:='GH-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.delivery_code_seq')::text,6,'0');
  insert into public.delivery_orders(delivery_code,outbound_order_id,delivery_sequence,status,expected_delivery_date,receiver_name,receiver_phone,delivery_address,carrier_name,driver_name,driver_phone,vehicle_plate,created_by)
  values(code,old.outbound_order_id,seq,'waiting',coalesce(new_expected_date,old.expected_delivery_date),old.receiver_name,old.receiver_phone,old.delivery_address,old.carrier_name,old.driver_name,old.driver_phone,old.vehicle_plate,(select auth.uid())) returning id into next_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'retry_delivery','delivery_order',next_id,jsonb_build_object('previous_delivery_id',old.id,'sequence',seq));
  return next_id;
end;
$$;

revoke all on function public.submit_inbound_order(uuid) from public,anon;
revoke all on function public.approve_inbound_order(uuid) from public,anon;
revoke all on function public.post_inbound_receipt(uuid,uuid,jsonb) from public,anon;
revoke all on function public.post_outbound_issue(uuid,uuid,jsonb) from public,anon;
revoke all on function public.create_stock_adjustment(uuid,text,text,jsonb) from public,anon;
revoke all on function public.approve_stock_adjustment(uuid) from public,anon;
revoke all on function public.transfer_stock(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.record_delivery_attempt(uuid,text,text,timestamptz,text,jsonb) from public,anon;
revoke all on function public.create_delivery_retry(uuid,date) from public,anon;
grant execute on function public.submit_inbound_order(uuid) to authenticated;
grant execute on function public.approve_inbound_order(uuid) to authenticated;
grant execute on function public.post_inbound_receipt(uuid,uuid,jsonb) to authenticated;
grant execute on function public.post_outbound_issue(uuid,uuid,jsonb) to authenticated;
grant execute on function public.create_stock_adjustment(uuid,text,text,jsonb) to authenticated;
grant execute on function public.approve_stock_adjustment(uuid) to authenticated;
grant execute on function public.transfer_stock(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.record_delivery_attempt(uuid,text,text,timestamptz,text,jsonb) to authenticated;
grant execute on function public.create_delivery_retry(uuid,date) to authenticated;

