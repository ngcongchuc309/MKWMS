-- Only drafts may be edited. Submitting is an allowed draft -> pending transition.
drop policy if exists "authorized update draft inbound" on public.inbound_orders;
create policy "authorized update draft inbound" on public.inbound_orders for update to authenticated
  using (status='draft' and public.current_user_role() in ('admin','warehouse_manager','warehouse_staff') and public.can_access_warehouse(warehouse_id))
  with check (status in ('draft','pending_approval') and public.can_access_warehouse(warehouse_id));
drop policy if exists "add inbound lines to editable order" on public.inbound_order_lines;
create policy "add inbound lines to editable order" on public.inbound_order_lines for insert to authenticated
  with check (exists (select 1 from public.inbound_orders o where o.id=inbound_order_id and o.status='draft' and public.can_access_warehouse(o.warehouse_id)));

drop policy if exists "authorized update draft outbound" on public.outbound_orders;
create policy "authorized update draft outbound" on public.outbound_orders for update to authenticated
  using (status='draft' and public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','sales') and public.can_access_warehouse(warehouse_id))
  with check (status in ('draft','pending_approval') and public.can_access_warehouse(warehouse_id));
drop policy if exists "add outbound lines to editable order" on public.outbound_order_lines;
create policy "add outbound lines to editable order" on public.outbound_order_lines for insert to authenticated
  with check (exists (select 1 from public.outbound_orders o where o.id=outbound_order_id and o.status='draft' and public.can_access_warehouse(o.warehouse_id)));

-- Ensure records created through the table API follow the same essential business rules.
create or replace function public.validate_mkwms_order_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare partner_row public.partners%rowtype;
begin
  if not exists (select 1 from public.warehouses w where w.id=new.warehouse_id and w.active and public.can_access_warehouse(w.id)) then
    raise exception 'Active warehouse access required';
  end if;
  if tg_table_name='inbound_orders' then
    if new.delivery_on is null or nullif(trim(new.receiver_name),'') is null or nullif(trim(new.receiver_phone),'') is null then
      raise exception 'Inbound delivery date, receiver name and phone are required';
    end if;
    if new.inbound_type in ('supplier','return') then
      select * into partner_row from public.partners p where p.id=new.supplier_id and p.active;
      if not found or not (partner_row.partner_type='both' or partner_row.partner_type=case when new.inbound_type='return' then 'customer' else 'supplier' end) then
        raise exception 'Select an active partner matching the inbound type';
      end if;
    end if;
  elsif new.outbound_type='sale' then
    select * into partner_row from public.partners p where p.id=new.partner_id and p.active and p.partner_type in ('customer','both');
    if not found then raise exception 'Select an active customer'; end if;
    if new.shipping_method='delivery' and (new.expected_delivery_date is null or nullif(trim(new.receiver_name),'') is null or nullif(trim(new.receiver_phone),'') is null or nullif(trim(new.delivery_address),'') is null) then
      raise exception 'Expected delivery date, receiver name, phone and address are required';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.validate_mkwms_order_insert() from public,anon,authenticated;
drop trigger if exists validate_inbound_order_insert on public.inbound_orders;
create trigger validate_inbound_order_insert before insert on public.inbound_orders
  for each row execute function public.validate_mkwms_order_insert();
drop trigger if exists validate_outbound_order_insert on public.outbound_orders;
create trigger validate_outbound_order_insert before insert on public.outbound_orders
  for each row execute function public.validate_mkwms_order_insert();

create or replace function public.validate_mkwms_order_line_product()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (select 1 from public.products p where p.id=new.product_id and p.active) then
    raise exception 'Order lines must reference an active product';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_mkwms_order_line_product() from public,anon,authenticated;
drop trigger if exists validate_inbound_order_line_product on public.inbound_order_lines;
create trigger validate_inbound_order_line_product before insert on public.inbound_order_lines
  for each row execute function public.validate_mkwms_order_line_product();
drop trigger if exists validate_outbound_order_line_product on public.outbound_order_lines;
create trigger validate_outbound_order_line_product before insert on public.outbound_order_lines
  for each row execute function public.validate_mkwms_order_line_product();

-- Insert the document as a draft, add all lines, then submit within the same RPC transaction.
create or replace function public.create_inbound_order_with_lines(
  p_document_code text,p_inbound_type text,p_supplier_id uuid,p_warehouse_id uuid,p_created_on date,
  p_delivery_on date,p_receiver_name text,p_receiver_phone text,p_submit_for_approval boolean,p_lines jsonb
)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare new_order_id uuid; role_name text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  role_name:=coalesce(public.current_user_role(),'');
  if role_name not in ('admin','warehouse_manager','warehouse_staff') then raise exception 'Role cannot create inbound orders'; end if;
  if p_inbound_type not in ('supplier','return','other') then raise exception 'Invalid inbound type'; end if;
  if nullif(trim(coalesce(p_document_code,'')),'') is null then raise exception 'Document code is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Inbound order must contain at least one item'; end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity integer,location_code text,lot_code text)
    where x.product_id is null or x.quantity is null or x.quantity<=0 or not exists(select 1 from public.products p where p.id=x.product_id and p.active)) then
    raise exception 'Every line must reference an active product and a positive quantity';
  end if;
  insert into public.inbound_orders(document_code,inbound_type,supplier_id,warehouse_id,status,created_on,delivery_on,receiver_name,receiver_phone,created_by)
  values(trim(p_document_code),p_inbound_type,p_supplier_id,p_warehouse_id,'draft',coalesce(p_created_on,current_date),p_delivery_on,trim(coalesce(p_receiver_name,'')),trim(coalesce(p_receiver_phone,'')),(select auth.uid()))
  returning id into new_order_id;
  insert into public.inbound_order_lines(inbound_order_id,product_id,expected_quantity,location_code,lot_code)
  select new_order_id,x.product_id,x.quantity,coalesce(x.location_code,''),coalesce(x.lot_code,'')
  from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity integer,location_code text,lot_code text);
  if coalesce(p_submit_for_approval,false) then update public.inbound_orders set status='pending_approval' where id=new_order_id; end if;
  return new_order_id;
end;
$$;

create or replace function public.create_outbound_order_with_lines(
  p_document_code text,p_outbound_type text,p_partner_id uuid,p_partner_name text,p_warehouse_id uuid,
  p_shipping_method text,p_expected_delivery_date date,p_receiver_name text,p_receiver_phone text,
  p_delivery_address text,p_created_on date,p_submit_for_approval boolean,p_lines jsonb
)
returns uuid
language plpgsql security invoker set search_path = ''
as $$
declare new_order_id uuid; role_name text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  role_name:=coalesce(public.current_user_role(),'');
  if role_name not in ('admin','warehouse_manager','warehouse_staff','sales') then raise exception 'Role cannot create outbound orders'; end if;
  if p_outbound_type not in ('sale','internal','other') then raise exception 'Invalid outbound type'; end if;
  if p_shipping_method not in ('delivery','pickup') then raise exception 'Invalid shipping method'; end if;
  if nullif(trim(coalesce(p_document_code,'')),'') is null then raise exception 'Document code is required'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Outbound order must contain at least one item'; end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity integer,location_code text,lot_code text)
    where x.product_id is null or x.quantity is null or x.quantity<=0 or not exists(select 1 from public.products p where p.id=x.product_id and p.active)) then
    raise exception 'Every line must reference an active product and a positive quantity';
  end if;
  insert into public.outbound_orders(document_code,outbound_type,partner_id,partner_name,warehouse_id,shipping_method,expected_delivery_date,receiver_name,receiver_phone,delivery_address,status,created_on,created_by)
  values(trim(p_document_code),p_outbound_type,p_partner_id,trim(coalesce(p_partner_name,'')),p_warehouse_id,p_shipping_method,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then p_expected_delivery_date else null end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_receiver_name,'')) else '' end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_receiver_phone,'')) else '' end,
    case when p_outbound_type='sale' and p_shipping_method='delivery' then trim(coalesce(p_delivery_address,'')) else '' end,
    'draft',coalesce(p_created_on,current_date),(select auth.uid())) returning id into new_order_id;
  insert into public.outbound_order_lines(outbound_order_id,product_id,requested_quantity,location_code,lot_code)
  select new_order_id,x.product_id,x.quantity,coalesce(x.location_code,''),coalesce(x.lot_code,'')
  from jsonb_to_recordset(p_lines) as x(product_id uuid,quantity integer,location_code text,lot_code text);
  if coalesce(p_submit_for_approval,false) then update public.outbound_orders set status='pending_approval' where id=new_order_id; end if;
  return new_order_id;
end;
$$;
