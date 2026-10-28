-- The browser can only move an editable outbound order between draft and pending approval.
-- Approval is performed by the guarded RPC, which also reserves inventory transactionally.
revoke update on public.outbound_orders from authenticated;
grant update (status) on public.outbound_orders to authenticated;
