begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into public.carteiras values ('CV1', 'CV1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Cva', 'Cva - Escola Novidades', 'CV1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000e0a01', 'of.nov@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000e0b01', 'ger.nov@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000e0a01', 'Ofic Novidades', 'oficineiro', (select id from public.escolas where sigla = 'Cva'), 'of.nov', false);
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000e0b01', 'Gerente Novidades', 'gerente', 'ger.nov', false);
create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;
create temp table base_aud as select count(*)::int n from auditoria.eventos;

set local role anon;
select throws_ok($$select public.minha_novidade_vista()$$, '42501', null, 'sem login não lê a novidade vista');
select throws_ok($$select public.marcar_novidade_vista(3)$$, '42501', null, 'sem login não marca novidade');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000e0b01', 'aal1');
set local role authenticated;
select throws_ok($$select public.marcar_novidade_vista(3)$$, '42501', null, 'gerente sem autenticador não marca novidade');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000e0a01');
set local role authenticated;
select is(public.minha_novidade_vista(), null, 'conta nova ainda não viu novidade');
select is(public.marcar_novidade_vista(5), 5, 'marca a última novidade vista');
select is(public.minha_novidade_vista(), 5, 'lê a última novidade vista');
select is(public.marcar_novidade_vista(3), 5, 'novidade mais antiga não volta o marcador');
select is(public.marcar_novidade_vista(8), 8, 'novidade mais nova avança o marcador');
select throws_ok($$select public.marcar_novidade_vista(0)$$, '22023', null, 'número zero é recusado');
select throws_ok($$select public.marcar_novidade_vista(null)$$, '22023', null, 'número vazio é recusado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000e0b01');
set local role authenticated;
select is(public.minha_novidade_vista(), null, 'novidade vista de um não vale para outro');
reset role;

select is((select preferencias from privado.conta_extras where usuario_id = '00000000-0000-0000-0000-0000000e0a01'), '{}'::jsonb,
          'marcar novidade não mexe nas preferências');
select is((select count(*)::int from auditoria.eventos) - (select n from base_aud), 0, 'novidades vistas não enchem a auditoria');

select * from finish();
rollback;
