-- Short compatibility window for the currently deployed client, which creates
-- an outbound header as pending before inserting its lines in a second request.
-- Only the creator may finish that initial insert, and only for 30 seconds.
drop policy if exists "add outbound lines to editable order" on public.outbound_order_lines;
create policy "add outbound lines to editable order" on public.outbound_order_lines for insert to authenticated
  with check (exists (
    select 1 from public.outbound_orders o
    where o.id=outbound_order_id and public.can_access_warehouse(o.warehouse_id)
      and (o.status='draft' or (
        o.status='pending_approval' and o.created_by=(select auth.uid())
        and o.created_at >= now()-interval '30 seconds'
      ))
  ));
