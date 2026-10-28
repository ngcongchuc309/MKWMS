-- Keep the project-owned event-trigger helper private to the database owner.
-- It is not an application RPC and must not be callable through PostgREST.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
