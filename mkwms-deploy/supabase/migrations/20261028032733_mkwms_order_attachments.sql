insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('mkwms-documents','mkwms-documents',false,20971520,array['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create table if not exists public.order_documents(id uuid primary key default gen_random_uuid(),warehouse_id uuid not null references public.warehouses(id),inbound_order_id uuid references public.inbound_orders(id) on delete restrict,delivery_order_id uuid references public.delivery_orders(id) on delete restrict,file_name text not null,storage_path text not null unique,mime_type text not null default '',file_size bigint not null check(file_size>0),uploaded_by uuid not null references public.profiles(user_id),created_at timestamptz not null default now(),check ((inbound_order_id is not null)::integer+(delivery_order_id is not null)::integer=1));
alter table public.order_documents enable row level security;
grant select,insert on public.order_documents to authenticated;
revoke all on public.order_documents from anon;
create policy order_documents_read on public.order_documents for select to authenticated using (public.can_access_warehouse(warehouse_id));
create policy order_documents_add on public.order_documents for insert to authenticated with check (uploaded_by=(select auth.uid()) and public.can_access_warehouse(warehouse_id) and public.current_user_role() in ('admin','warehouse_manager','warehouse_staff','delivery') and ((inbound_order_id is not null and exists(select 1 from public.inbound_orders i where i.id=inbound_order_id and i.warehouse_id=warehouse_id)) or (delivery_order_id is not null and exists(select 1 from public.delivery_orders d join public.outbound_orders o on o.id=d.outbound_order_id where d.id=delivery_order_id and o.warehouse_id=warehouse_id))));
create or replace function public.can_access_mkwms_storage_path(object_name text, write_access boolean default false) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare wh text; entity text; valid_uuid constant text:='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
 wh:=split_part(object_name,'/',1);entity:=split_part(object_name,'/',2);
 if wh !~ valid_uuid or entity !~ valid_uuid or (select auth.uid()) is null then return false; end if;
 if not public.can_access_warehouse(wh::uuid) then return false; end if;
 if write_access and coalesce(public.current_user_role(),'') not in ('admin','warehouse_manager','warehouse_staff','delivery') then return false; end if;
 return exists(select 1 from public.inbound_orders i where i.id=entity::uuid and i.warehouse_id=wh::uuid) or exists(select 1 from public.delivery_orders d join public.outbound_orders o on o.id=d.outbound_order_id where d.id=entity::uuid and o.warehouse_id=wh::uuid);
end $$;
revoke all on function public.can_access_mkwms_storage_path(text,boolean) from public,anon;
grant execute on function public.can_access_mkwms_storage_path(text,boolean) to authenticated;
create policy mkwms_documents_read on storage.objects for select to authenticated using (bucket_id='mkwms-documents' and public.can_access_mkwms_storage_path(name,false));
create policy mkwms_documents_insert on storage.objects for insert to authenticated with check (bucket_id='mkwms-documents' and public.can_access_mkwms_storage_path(name,true));
