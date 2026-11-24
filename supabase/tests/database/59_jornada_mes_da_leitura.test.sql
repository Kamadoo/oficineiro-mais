begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into public.carteiras values ('JM1', 'JM1 - Teste') on conflict do nothing;
insert into public.escolas (sigla, nome, carteira_id) values ('Jma', 'Jma - Escola Mes A', 'JM1');
insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, primeiro_acesso, base_ref)
select e.id, v.nome, v.tipo, v.ano, v.sem, v.dias, v.primeiro::date, date '2027-01-15'
  from public.escolas e,
       (values ('Aluno Ritmo', 'A', 5, 2, 30, '2026-06-01'),
               ('Aluno Mes Passado', 'A', 5, 20, 50, '2026-06-01'),
               ('Professor Novo', 'P', 0, 1, 5, '2027-01-03'),
               ('Professor Meta', 'P', 0, 0, 7, '2027-01-02'),
               ('Aluno Nunca', 'A', 5, -1, 0, null)) as v (nome, tipo, ano, sem, dias, primeiro)
 where e.sigla = 'Jma';

create function pg_temp.resumo(p_tipo text default null) returns text language sql as $$
  select sum(r.n)::int || '/' || sum(r.nv)::int || '/' || sum(r.sr)::int || '/' || sum(r.en)::int
    from public.jornada_resumo_mensal() r
   where r.escola_id = (select id from public.escolas where sigla = 'Jma')
     and (p_tipo is null or r.tipo = p_tipo);
$$;

select is(pg_temp.resumo(), '5/1/1/2', 'criados, nunca acessou, sem uso no mês e engajados no mês da leitura');
select is(pg_temp.resumo('A'), '3/1/1/1', 'aluno engajado com 2 acessos estimados na metade do mês; o do mês anterior fica sem uso');
select is(pg_temp.resumo('P'), '2/0/0/1', 'professor com primeiro acesso no mês conta os dias exatos contra a meta proporcional');
select ok(not has_function_privilege('anon', 'public.jornada_resumo_mensal()', 'EXECUTE'), 'visitante não lê o resumo mensal');

select * from finish();
rollback;
