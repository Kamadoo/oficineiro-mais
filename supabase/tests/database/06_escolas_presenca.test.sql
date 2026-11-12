begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values
  ('Aaa', 'Aaa - Escola com localização', 'CS1', -20.0050033, -43.8462843, 150),
  ('Bbb', 'Bbb - Escola sem localização', 'CS1', null, null, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000f1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of.b@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, 'oficineiro', e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro A', 'of.a', 'Aaa'),
               ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro B', 'of.b', 'Bbb')) x(id, nome, usuario, sig)
  join public.escolas e on e.sigla = x.sig;

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.minha_escola()), 0, 'sem o autenticador, não recebe a escola');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select is((select sigla from public.minha_escola()), 'Aaa', 'o oficineiro recebe a própria escola');
select is((select raio_m::int from public.minha_escola()), 150, 'com o raio cadastrado');
select is((public.marcar_presenca('entrada', -20.0051, -43.8463, 10) ->> 'aceita'), 'true', 'dentro do raio: entrada aceita');
select ok((select distancia_inicio_m from public.presencas) < 150, 'a distância fica gravada');
select throws_ok($$select public.marcar_presenca('entrada', -20.0051, -43.8463, 10)$$, '22023', null, 'não registra a entrada duas vezes');
reset role;

delete from public.presencas;
select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select is((public.marcar_presenca('entrada', -19.98, -43.84, 10) ->> 'motivo'), 'Fora do raio da escola', 'longe da escola: entrada não aceita');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
set local role authenticated;
select is((select sigla from public.minha_escola()), 'Bbb', 'outro oficineiro recebe a escola dele');
select is((public.marcar_presenca('entrada', -20.0051, -43.8463, 10) ->> 'motivo'), 'Escola sem localização cadastrada', 'escola sem localização: entrada não aceita');
select is((select count(*)::int from public.presencas), 0, 'tentativa recusada não cria presença');
select is((select count(*)::int from public.minha_escola() where sigla = 'Aaa'), 0, 'não recebe a escola de outra pessoa');
reset role;

select is((select count(*)::int from public.presenca_tentativas), 2, 'as duas tentativas recusadas ficam guardadas');

select * from finish();
rollback;
