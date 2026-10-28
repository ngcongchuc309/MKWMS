alter table public.profiles add column if not exists email text not null default '';
update public.profiles p set email=u.email from auth.users u where p.user_id=u.id and p.email='';

create or replace function public.admin_set_user_profile(
  target_user uuid,
  target_full_name text,
  target_role text,
  target_active boolean,
  target_warehouses uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare target_email text;
begin
  if (select auth.uid()) is null or coalesce(public.current_user_role(),'') <> 'admin' then
    raise exception 'Only an administrator can manage user access';
  end if;
  if target_user=(select auth.uid()) then raise exception 'Use another administrator to change your own access'; end if;
  if target_role is null or target_role not in ('admin','warehouse_manager','warehouse_staff','sales','delivery','accounting') then raise exception 'Invalid MKWMS role'; end if;
  if target_active is null then raise exception 'Active status is required'; end if;
  select email into target_email from auth.users where id=target_user;
  if not found then raise exception 'Create or invite this account in Supabase Auth before assigning an MKWMS role'; end if;
  if exists(select 1 from unnest(coalesce(target_warehouses,array[]::uuid[])) as wh(id) left join public.warehouses w on w.id=wh.id where w.id is null or not w.active) then
    raise exception 'One or more selected warehouses do not exist or are inactive';
  end if;
  insert into public.profiles(user_id,email,full_name,role,active)
  values(target_user,coalesce(target_email,''),coalesce(trim(target_full_name),''),target_role,target_active)
  on conflict(user_id) do update set email=excluded.email,full_name=excluded.full_name,role=excluded.role,active=excluded.active,updated_at=now();
  delete from public.user_warehouses where user_id=target_user;
  insert into public.user_warehouses(user_id,warehouse_id)
  select target_user,scope.warehouse_id from unnest(coalesce(target_warehouses,array[]::uuid[])) as scope(warehouse_id)
  on conflict do nothing;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,details)
  values((select auth.uid()),'set_access','profile',target_user,jsonb_build_object('role',target_role,'active',target_active,'warehouse_count',coalesce(cardinality(target_warehouses),0)));
end;
$$;
revoke all on function public.admin_set_user_profile(uuid,text,text,boolean,uuid[]) from public,anon;
grant execute on function public.admin_set_user_profile(uuid,text,text,boolean,uuid[]) to authenticated;
