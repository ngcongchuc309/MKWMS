-- Controlled opening balance import and reversal for posted inventory movements.
alter table public.delivery_order_lines drop constraint if exists delivery_order_lines_delivery_order_id_outbound_order_line_id_key;
create table if not exists public.opening_balance_batches (id uuid primary key, created_by uuid not null references public.profiles(user_id), created_at timestamptz not null default now());
create table if not exists public.inventory_reversal_batches (id uuid primary key default gen_random_uuid(), original_source_type text not null, original_source_id uuid not null, reason text not null, created_by uuid not null references public.profiles(user_id), created_at timestamptz not null default now(), unique(original_source_type,original_source_id));
alter table public.opening_balance_batches enable row level security;
alter table public.inventory_reversal_batches enable row level security;
create policy opening_balance_batches_read on public.opening_balance_batches for select to authenticated using (public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','accounting'));
create policy inventory_reversal_batches_read on public.inventory_reversal_batches for select to authenticated using (public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','accounting'));
revoke all on public.opening_balance_batches,public.inventory_reversal_batches from anon,authenticated;
create or replace function public.import_opening_balances(idempotency_key uuid, opening_rows jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare item jsonb; v_product uuid; v_warehouse uuid; v_sku text; v_code text; v_loc text; v_lot text; v_qty integer;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
 if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can import opening balances'; end if;
 if idempotency_key is null or jsonb_typeof(opening_rows)<>'array' or jsonb_array_length(opening_rows)=0 then raise exception 'Opening balance batch and rows are required'; end if;
 insert into public.opening_balance_batches(id,created_by) values(idempotency_key,(select auth.uid())) on conflict(id) do nothing;
 if not found then if exists(select 1 from public.opening_balance_batches where id=idempotency_key and created_by=(select auth.uid())) then return jsonb_build_object('duplicate',true); end if; raise exception 'Idempotency key already used'; end if;
 for item in select value from jsonb_array_elements(opening_rows) loop
  v_sku:=trim(coalesce(item->>'sku','')); v_code:=trim(coalesce(item->>'warehouse_code','')); v_loc:=coalesce(item->>'location_code',''); v_lot:=coalesce(item->>'lot_code',''); v_qty:=(item->>'quantity')::integer;
  if v_qty<=0 then raise exception 'Opening quantity must be a positive integer'; end if;
  select id into v_product from public.products where lower(sku)=lower(v_sku) and active;
  if not found then raise exception 'Unknown or inactive SKU: %',v_sku; end if;
  select id into v_warehouse from public.warehouses where lower(code)=lower(v_code) and active;
  if not found then raise exception 'Unknown or inactive warehouse: %',v_code; end if;
  if not public.can_access_warehouse(v_warehouse) then raise exception 'Warehouse access denied'; end if;
  if exists(select 1 from public.stock_balances where warehouse_id=v_warehouse and product_id=v_product and location_code=v_loc and lot_code=v_lot) then raise exception 'Opening balance location already exists for SKU % in warehouse %',v_sku,v_code; end if;
  insert into public.stock_balances(warehouse_id,product_id,location_code,lot_code,on_hand_quantity,reserved_quantity,updated_at) values(v_warehouse,v_product,v_loc,v_lot,v_qty,0,now());
  insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by) values(v_warehouse,v_product,'inbound',v_qty,'opening_balance',idempotency_key,v_loc,v_lot,(select auth.uid()));
 end loop;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values((select auth.uid()),'import_opening_balances','opening_balance_batch',idempotency_key,jsonb_build_object('rows',jsonb_array_length(opening_rows)));
 return jsonb_build_object('duplicate',false,'batch_id',idempotency_key);
end $$;
create or replace function public.reverse_inventory_transaction(original_source_type text, original_source_id uuid, reversal_reason text) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_reversal uuid; m record; b public.stock_balances%rowtype;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
 if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can reverse a posted transaction'; end if;
 if nullif(trim(reversal_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 if original_source_type not in ('inbound_receipt','outbound_issue','stock_adjustment','stock_transfer','opening_balance') then raise exception 'Unsupported transaction source'; end if;
 if exists(select 1 from public.inventory_reversal_batches r where r.original_source_type=reverse_inventory_transaction.original_source_type and r.original_source_id=reverse_inventory_transaction.original_source_id) then raise exception 'This transaction has already been reversed'; end if;
 if not exists(select 1 from public.inventory_movements where source_type=original_source_type and source_id=original_source_id) then raise exception 'Posted transaction not found'; end if;
 if exists(select 1 from public.inventory_movements src where src.source_type=original_source_type and src.source_id=original_source_id and not public.can_access_warehouse(src.warehouse_id)) then raise exception 'Warehouse access denied'; end if;
 insert into public.inventory_reversal_batches(original_source_type,original_source_id,reason,created_by) values(original_source_type,original_source_id,trim(reversal_reason),(select auth.uid())) returning id into v_reversal;
 for m in select warehouse_id,product_id,location_code,lot_code,sum(quantity_delta)::integer as delta from public.inventory_movements where source_type=original_source_type and source_id=original_source_id group by warehouse_id,product_id,location_code,lot_code order by warehouse_id,product_id,location_code,lot_code loop
  select * into b from public.stock_balances where warehouse_id=m.warehouse_id and product_id=m.product_id and location_code=m.location_code and lot_code=m.lot_code for update;
  if not found or b.on_hand_quantity-m.delta < b.reserved_quantity then raise exception 'Cannot reverse: remaining stock is reserved or insufficient'; end if;
  update public.stock_balances set on_hand_quantity=on_hand_quantity-m.delta,updated_at=now() where warehouse_id=m.warehouse_id and product_id=m.product_id and location_code=m.location_code and lot_code=m.lot_code;
  insert into public.inventory_movements(warehouse_id,product_id,movement_type,quantity_delta,source_type,source_id,location_code,lot_code,created_by) values(m.warehouse_id,m.product_id,'reversal',-m.delta,'reversal',v_reversal,m.location_code,m.lot_code,(select auth.uid()));
 end loop;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values((select auth.uid()),'reverse','inventory_transaction',v_reversal,jsonb_build_object('source_type',original_source_type,'source_id',original_source_id,'reason',trim(reversal_reason)));
 return v_reversal;
end $$;
revoke all on function public.import_opening_balances(uuid,jsonb) from public,anon;
revoke all on function public.reverse_inventory_transaction(text,uuid,text) from public,anon;
grant execute on function public.import_opening_balances(uuid,jsonb) to authenticated;
grant execute on function public.reverse_inventory_transaction(text,uuid,text) to authenticated;
