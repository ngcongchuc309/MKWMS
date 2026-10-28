drop trigger if exists audit_order_documents on public.order_documents;
create trigger audit_order_documents after insert on public.order_documents for each row execute function public.write_audit_row();
