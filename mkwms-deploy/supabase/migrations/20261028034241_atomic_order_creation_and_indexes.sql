-- Create each order and all of its lines in one transaction.
-- SECURITY INVOKER preserves table grants and RLS policies for the signed-in user.
create or replace function public.create_inbound_order_with_lines(
  p_document_code text,
  p_inbound_type text,
  p_supplier_id uuid,
  p_warehouse_id uuid,
  p_created_on date,
  p_delivery_on date,
  p_receiver_name text,
  p_receiver_phone text,
  p_submit_for_approval boolean,
  p_lines jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_order_id uuid;
  role_name text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  role_name := coalesce(public.current_user_role(), '');
  if role_name not in ('admin','warehouse_manager','warehouse_staff') then
    raise exception 'Role cannot create inbound orders';
  end if;
  if p_inbound_type not in ('supplier','return','other') then raise exception 'Invalid inbound type'; end if;
  if nullif(trim(coalesce(p_document_code,'')), '') is null then raise exception 'Document code is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Inbound order must contain at least one item';
  end if;
  if not exists (select 1 from public.warehouses w where w.id=p_warehouse_id and w.active and public.can_access_warehouse(w.id)) then
    raise exception 'Active warehouse access required';
  end if;
  if p_inbound_type in ('supplier','return') and not exists (
    select 1 from public.partners p where p.id=p_supplier_id and p.active
      and (p.partner_type='both' or p.partner_type=case when p_inbound_type='return' then 'customer' else 'supplier' end)
  ) then raise exception 'Select an active supplier or customer matching the inbound type'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid, quantity integer, location_code text, lot_code text)
    where x.product_id is null or x.quantity is null or x.quantity <= 0
      or not exists(select 1 from public.products p where p.id=x.product_id and p.active)
  ) then raise exception 'Every line must reference an active product and a positive quantity'; end if;

  insert into public.inbound_orders(document_code,inbound_type,supplier_id,warehouse_id,status,created_on,delivery_on,receiver_name,receiver_phone,created_by)
  values (trim(p_document_code),p_inbound_type,p_supplier_id,p_warehouse_id,
    case when coalesce(p_submit_for_approval,false) then 'pending_approval' else 'draft' end,
    coalesce(p_created_on,current_date),p_delivery_on,trim(coalesce(p_receiver_name,'')),trim(coalesce(p_receiver_phone,'')),(select auth.uid()))
  returning id into new_order_id;

  insert into public.inbound_order_lines(inbound_order_id,product_id,expected_quantity,location_code,lot_code)
  select new_order_id,x.product_id,x.quantity,coalesce(x.location_code,''),coalesce(x.lot_code,'')
  from jsonb_to_recordset(p_lines) as x(product_id uuid, quantity integer, location_code text, lot_code text);
  return new_order_id;
end;
$$;

create or replace function public.create_outbound_order_with_lines(
  p_document_code text,
  p_outbound_type text,
  p_partner_id uuid,
  p_partner_name text,
  p_warehouse_id uuid,
  p_shipping_method text,
  p_expected_delivery_date date,
  p_receiver_name text,
  p_receiver_phone text,
  p_delivery_address text,
  p_created_on date,
  p_submit_for_approval boolean,
  p_lines jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_order_id uuid;
  role_name text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  role_name := coalesce(public.current_user_role(), '');
  if role_name not in ('admin','warehouse_manager','warehouse_staff','sales') then
    raise exception 'Role cannot create outbound orders';
  end if;
  if p_outbound_type not in ('sale','internal','other') then raise exception 'Invalid outbound type'; end if;
  if p_shipping_method not in ('delivery','pickup') then raise exception 'Invalid shipping method'; end if;
  if nullif(trim(coalesce(p_document_code,'')), '') is null then raise exception 'Document code is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Outbound order must contain at least one item';
  end if;
  if not exists (select 1 from public.warehouses w where w.id=p_warehouse_id and w.active and public.can_access_warehouse(w.id)) then
    raise exception 'Active warehouse access required';
  end if;
  if p_outbound_type='sale' and not exists (
    select 1 from public.partners p where p.id=p_partner_id and p.active and p.partner_type in ('customer','both')
  ) then raise exception 'Select an active customer'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid, quantity integer, location_code text, lot_code text)
    where x.product_id is null or x.quantity is null or x.quantity <= 0
      or not exists(select 1 from public.products p where p.id=x.product_id and p.active)
  ) then raise exception 'Every line must reference an active product and a positive quantity'; end if;

  insert into public.outbound_orders(document_code,outbound_type,partner_id,partner_name,warehouse_id,shipping_method,expected_delivery_date,receiver_name,receiver_phone,delivery_address,status,created_on,created_by)
  values (trim(p_document_code),p_outbound_type,p_partner_id,trim(coalesce(p_partner_name,'')),p_warehouse_id,p_shipping_method,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then p_expected_delivery_date else null end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_receiver_name,'')) else '' end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_receiver_phone,'')) else '' end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_delivery_address,'')) else '' end,
    case when coalesce(p_submit_for_approval,false) then 'pending_approval' else 'draft' end,
    coalesce(p_created_on,current_date),(select auth.uid()))
  returning id into new_order_id;

  insert into public.outbound_order_lines(outbound_order_id,product_id,requested_quantity,location_code,lot_code)
  select new_order_id,x.product_id,x.quantity,coalesce(x.location_code,''),coalesce(x.lot_code,'')
  from jsonb_to_recordset(p_lines) as x(product_id uuid, quantity integer, location_code text, lot_code text);
  return new_order_id;
end;
$$;

revoke all on function public.create_inbound_order_with_lines(text,text,uuid,uuid,date,date,text,text,boolean,jsonb) from public,anon;
revoke all on function public.create_outbound_order_with_lines(text,text,uuid,text,uuid,text,date,text,text,text,date,boolean,jsonb) from public,anon;
grant execute on function public.create_inbound_order_with_lines(text,text,uuid,uuid,date,date,text,text,boolean,jsonb) to authenticated;
grant execute on function public.create_outbound_order_with_lines(text,text,uuid,text,uuid,text,date,text,text,text,date,boolean,jsonb) to authenticated;

-- Retain one unique constraint; a previous migration created the same key twice.
alter table public.delivery_order_lines
  drop constraint if exists delivery_order_lines_delivery_order_id_outbound_order_line_id_k;

-- Index relationship columns used by order, receipt, delivery, and attachment lookups.
create index if not exists inbound_order_lines_order_idx on public.inbound_order_lines(inbound_order_id);
create index if not exists outbound_order_lines_order_idx on public.outbound_order_lines(outbound_order_id);
create index if not exists delivery_order_lines_source_line_idx on public.delivery_order_lines(outbound_order_line_id);
create index if not exists inbound_receipt_batches_order_idx on public.inbound_receipt_batches(inbound_order_id);
create index if not exists outbound_issue_batches_order_idx on public.outbound_issue_batches(outbound_order_id);
create index if not exists delivery_orders_outbound_order_idx on public.delivery_orders(outbound_order_id);
create index if not exists order_documents_inbound_order_idx on public.order_documents(inbound_order_id) where inbound_order_id is not null;
create index if not exists order_documents_delivery_order_idx on public.order_documents(delivery_order_id) where delivery_order_id is not null;
