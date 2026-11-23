grant usage on schema privado to anon;

alter function public.verificar_documento(text) set schema privado;

revoke all on function privado.verificar_documento(text) from public, anon, authenticated;
grant execute on function privado.verificar_documento(text) to anon, authenticated;

create function public.verificar_documento(p_codigo text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.verificar_documento(p_codigo) $$;

revoke all on function public.verificar_documento(text) from public, anon, authenticated;
grant execute on function public.verificar_documento(text) to anon, authenticated;
