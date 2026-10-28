-- Keep delivery assignment details and its delivery attempt in one transaction.
create or replace function public.update_delivery_and_record_attempt(
  target_delivery uuid,
  expected_date date,
  carrier text,
  driver text,
  driver_contact text,
  vehicle text,
  next_status text,
  received_name text,
  actual_time timestamptz,
  proof text,
  delivered_lines jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  changed_rows integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','delivery') then
    raise exception 'Role cannot update deliveries';
  end if;

  update public.delivery_orders
  set expected_delivery_date=expected_date,
      carrier_name=trim(coalesce(carrier,'')),
      driver_name=trim(coalesce(driver,'')),
      driver_phone=trim(coalesce(driver_contact,'')),
      vehicle_plate=trim(coalesce(vehicle,'')),
      updated_at=now()
  where id=target_delivery;
  get diagnostics changed_rows=row_count;
  if changed_rows=0 then raise exception 'Delivery order not found or warehouse access denied'; end if;

  perform public.record_delivery_attempt(target_delivery,next_status,received_name,actual_time,proof,delivered_lines);
end;
$$;
revoke all on function public.update_delivery_and_record_attempt(uuid,date,text,text,text,text,text,text,timestamptz,text,jsonb) from public,anon;
grant execute on function public.update_delivery_and_record_attempt(uuid,date,text,text,text,text,text,text,timestamptz,text,jsonb) to authenticated;

-- Admin SELECT is already covered by each table's scoped read policy.
-- Split management policies so a SELECT does not pass through two permissive policies.
drop policy if exists "admin manages warehouses" on public.warehouses;
create policy "admin inserts warehouses" on public.warehouses for insert to authenticated
  with check (public.current_user_role()='admin');
create policy "admin updates warehouses" on public.warehouses for update to authenticated
  using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
create policy "admin deletes warehouses" on public.warehouses for delete to authenticated
  using (public.current_user_role()='admin');

drop policy if exists "admin manages warehouse scope" on public.user_warehouses;
create policy "admin inserts warehouse scope" on public.user_warehouses for insert to authenticated
  with check (public.current_user_role()='admin');
create policy "admin updates warehouse scope" on public.user_warehouses for update to authenticated
  using (public.current_user_role()='admin') with check (public.current_user_role()='admin');
create policy "admin deletes warehouse scope" on public.user_warehouses for delete to authenticated
  using (public.current_user_role()='admin');
