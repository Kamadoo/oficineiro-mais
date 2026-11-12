begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false);
create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select public.definir_raio_escola((select id from public.escolas), 300::smallint)$$, '42501', null, 'oficineiro não muda o raio');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1', 'aal1');
set local role authenticated;
select throws_ok($$select public.definir_raio_escola((select id from public.escolas), 300::smallint)$$, '42501', null, 'coordenador sem autenticador não muda o raio');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select throws_ok($$select public.definir_raio_escola((select id from public.escolas), 900::smallint)$$, '22023', null, 'raio fora do limite é recusado');
select lives_ok($$select public.definir_raio_escola((select id from public.escolas), 200::smallint)$$, 'coordenador muda o raio');
reset role;
select is((select raio_m::int from public.escolas), 200, 'raio gravado');

select * from finish();
rollback;
