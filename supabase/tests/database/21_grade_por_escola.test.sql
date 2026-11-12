begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
  values ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.a', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (2026, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática')$$, 'aula na escola antiga');
select throws_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (2026, 1, '07:00', '07:50', 4, 'A', 'R', 'Matific', 'Matemática')$$, '22023', null, 'na mesma escola o horário continua protegido');
reset role;

update public.perfis set escola_id = (select id from public.escolas where sigla = 'Bbb') where usuario = 'of.a';

set local role authenticated;
select is((select count(*)::int from public.grade_aulas), 0, 'na escola nova a grade aparece vazia');
select throws_ok($$select public.enviar_grade(2026::smallint)$$, '22023', null, 'grade vazia na escola nova não pode ser enviada');
select lives_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (2026, 1, '07:00', '07:50', 5, 'B', 'R', 'Matific', 'Matemática')$$, 'na escola nova o mesmo horário fica livre');
select lives_ok($$select public.enviar_grade(2026::smallint)$$, 'grade da escola nova pode ser enviada');
reset role;

select * from finish();
rollback;
