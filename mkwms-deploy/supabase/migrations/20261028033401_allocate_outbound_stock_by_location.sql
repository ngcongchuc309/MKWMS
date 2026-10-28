create or replace function public.approve_outbound_order(target_order uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare order_row public.outbound_orders%rowtype; line_row record; stock_row public.stock_balances%rowtype; new_delivery_id uuid; new_delivery_code text; remaining_qty integer; allocated_qty integer; first_allocation boolean;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
 if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can approve outbound orders'; end if;
 select * into order_row from public.outbound_orders where id=target_order for update;
 if not found then raise exception 'Outbound order not found'; end if;
 if order_row.status<>'pending_approval' then raise exception 'Outbound order is not pending approval'; end if;
 if not public.can_access_warehouse(order_row.warehouse_id) then raise exception 'Warehouse access denied'; end if;
 for line_row in select l.id,l.product_id,l.requested_quantity,l.location_code,l.lot_code from public.outbound_order_lines l where l.outbound_order_id=target_order order by l.product_id,l.location_code,l.lot_code for update loop
  remaining_qty:=line_row.requested_quantity;
  if nullif(line_row.location_code,'') is not null or nullif(line_row.lot_code,'') is not null then
   select * into stock_row from public.stock_balances s where s.warehouse_id=order_row.warehouse_id and s.product_id=line_row.product_id and s.location_code=line_row.location_code and s.lot_code=line_row.lot_code for update;
   if not found or stock_row.available_quantity<remaining_qty then raise exception 'Insufficient available stock at selected location for product %',line_row.product_id; end if;
   update public.stock_balances set reserved_quantity=reserved_quantity+remaining_qty,updated_at=now() where warehouse_id=order_row.warehouse_id and product_id=line_row.product_id and location_code=line_row.location_code and lot_code=line_row.lot_code;
   update public.outbound_order_lines set reserved_quantity=remaining_qty where id=line_row.id;
  else
   first_allocation:=true;
   for stock_row in select s.* from public.stock_balances s where s.warehouse_id=order_row.warehouse_id and s.product_id=line_row.product_id and s.available_quantity>0 order by s.location_code,s.lot_code for update loop
    exit when remaining_qty=0; allocated_qty:=least(stock_row.available_quantity,remaining_qty);
    update public.stock_balances set reserved_quantity=reserved_quantity+allocated_qty,updated_at=now() where warehouse_id=stock_row.warehouse_id and product_id=stock_row.product_id and location_code=stock_row.location_code and lot_code=stock_row.lot_code;
    if first_allocation then update public.outbound_order_lines set requested_quantity=allocated_qty,reserved_quantity=allocated_qty,location_code=stock_row.location_code,lot_code=stock_row.lot_code where id=line_row.id; first_allocation:=false;
    else insert into public.outbound_order_lines(outbound_order_id,product_id,requested_quantity,reserved_quantity,location_code,lot_code) values(target_order,line_row.product_id,allocated_qty,allocated_qty,stock_row.location_code,stock_row.lot_code); end if;
    remaining_qty:=remaining_qty-allocated_qty;
   end loop;
   if remaining_qty>0 then raise exception 'Insufficient available stock for product %: short %',line_row.product_id,remaining_qty; end if;
  end if;
 end loop;
 update public.outbound_orders set status='approved',approved_by=(select auth.uid()),approved_at=now() where id=target_order;
 if order_row.delivery_required then
  new_delivery_code:='GH-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.delivery_code_seq')::text,6,'0');
  insert into public.delivery_orders(delivery_code,outbound_order_id,delivery_sequence,expected_delivery_date,receiver_name,receiver_phone,delivery_address,created_by) values(new_delivery_code,target_order,1,order_row.expected_delivery_date,order_row.receiver_name,order_row.receiver_phone,order_row.delivery_address,(select auth.uid())) returning id into new_delivery_id;
 end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values((select auth.uid()),'approve','outbound_order',target_order,jsonb_build_object('delivery_order_id',new_delivery_id,'locations_allocated',true));
 return new_delivery_id;
end $$;
revoke all on function public.approve_outbound_order(uuid) from public,anon;
grant execute on function public.approve_outbound_order(uuid) to authenticated;
