begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into public.carteiras values ('JL1', 'JL1 - Teste'), ('JL2', 'JL2 - Teste') on conflict do nothing;
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jla', 'Jla - Escola Leitura A', 'JL1'),
  ('Jlb', 'Jlb - Escola Leitura B', 'JL2');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000c1a01', 'jl.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a02', 'jl.analista@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a03', 'jl.direcao@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a04', 'jl.inativo@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha, ativo) values
  ('00000000-0000-0000-0000-0000000c1a01', 'Gerente Leitura', 'gerente', null, null, false, true),
  ('00000000-0000-0000-0000-0000000c1a02', 'Analista Leitura', 'analista', null, 'JL1', false, true),
  ('00000000-0000-0000-0000-0000000c1a03', 'Direcao Leitura', 'direcao', (select id from public.escolas where sigla = 'Jla'), null, false, true),
  ('00000000-0000-0000-0000-0000000c1a04', 'Analista Inativo', 'analista', null, 'JL1', false, false);
insert into public.jornada_pessoas (escola_id, nome, tipo, dias_sem_acesso, dias_acesso, base_ref)
select e.id, 'Pessoa ' || e.sigla || g, 'A', 1, 3, date '2026-11-20'
  from public.escolas e, generate_series(1, 3) g
 where e.sigla in ('Jla', 'Jlb');

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;
create function pg_temp.vistos() returns int language sql as $$
  select count(*)::int from public.jornada_pessoas where base_ref = '2026-11-20' and nome like 'Pessoa Jl%';
$$;
grant execute on function pg_temp.vistos() to authenticated;

select ok(not has_function_privilege('anon', 'privado.escolas_da_jornada()', 'EXECUTE'), 'visitante não lista escolas da jornada');
select ok((select qual like '%escolas_da_jornada%' from pg_policies where tablename = 'jornada_pessoas' and policyname = 'jornada_ler'),
          'leitura usa a lista de escolas calculada uma vez');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c1a01');
select is(pg_temp.vistos(), 6, 'gerente vê todas as escolas');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a02');
select is(pg_temp.vistos(), 3, 'analista vê só a sua carteira');
select is((select count(*)::int from public.jornada_pessoas where nome like 'Pessoa Jlb%'), 0, 'analista não vê outra carteira');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a02', 'aal1');
select is(pg_temp.vistos(), 0, 'sem segundo fator não vê a base');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a03');
select is(pg_temp.vistos(), 0, 'direção não vê a base de acessos');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a04');
select is(pg_temp.vistos(), 0, 'perfil inativo não vê a base');
select pg_temp.como('00000000-0000-0000-0000-0000000c1aff');
select is(pg_temp.vistos(), 0, 'usuário sem perfil não vê a base');
reset role;

select * from finish();
rollback;
