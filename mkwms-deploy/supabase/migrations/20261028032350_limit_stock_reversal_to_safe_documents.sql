alter table public.stock_adjustments drop constraint if exists stock_adjustments_status_check;
alter table public.stock_adjustments add constraint stock_adjustments_status_check check (status in ('pending_approval','posted','cancelled','reversed'));
create or replace function public.reverse_inventory_transaction(original_source_type text, original_source_id uuid, reversal_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_reversal uuid; m record; b public.stock_balances%rowtype;
begin
 if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
 if coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager') then raise exception 'Only an administrator or warehouse manager can reverse a posted transaction'; end if;
 if nullif(trim(reversal_reason),'') is null then raise exception 'A reversal reason is required'; end if;
 if original_source_type not in ('stock_adjustment','stock_transfer','opening_balance') then raise exception 'Inbound receipts and outbound issues must be corrected through an approved stock adjustment'; end if;
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
 if original_source_type='stock_transfer' then update public.stock_transfers set status='reversed' where id=original_source_id; end if;
 if original_source_type='stock_adjustment' then update public.stock_adjustments set status='reversed' where id=original_source_id; end if;
 insert into public.audit_log(actor_id,action,entity_type,entity_id,details) values((select auth.uid()),'reverse','inventory_transaction',v_reversal,jsonb_build_object('source_type',original_source_type,'source_id',original_source_id,'reason',trim(reversal_reason)));
 return v_reversal;
end $$;
revoke all on function public.reverse_inventory_transaction(text,uuid,text) from public,anon;
grant execute on function public.reverse_inventory_transaction(text,uuid,text) to authenticated;
