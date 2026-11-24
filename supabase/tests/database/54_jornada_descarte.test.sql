begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into public.carteiras values ('JD1', 'JD1 - Teste'), ('JD2', 'JD2 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jda', 'Jda - Escola Descarte A', 'JD1'),
  ('Jdb', 'Jdb - Escola Descarte B', 'JD2');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000007a1', 'jd.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000007a2', 'jd.coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000007a3', 'jd.analista@exemplo.test'),
  ('00000000-0000-0000-0000-0000000007a4', 'jd.direcao@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha) values
  ('00000000-0000-0000-0000-0000000007a1', 'Gerente Descarte', 'gerente', null, null, false),
  ('00000000-0000-0000-0000-0000000007a2', 'Coord Descarte', 'coordenador', null, null, false),
  ('00000000-0000-0000-0000-0000000007a3', 'Analista Descarte', 'analista', null, 'JD1', false),
  ('00000000-0000-0000-0000-0000000007a4', 'Direcao Descarte', 'direcao', (select id from public.escolas where sigla = 'Jda'), null, false);

create function pg_temp.como(p_uid uuid, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
create function pg_temp.esc(p_sigla text) returns smallint language sql as $$
  select id from public.escolas where sigla = p_sigla;
$$;
grant execute on function pg_temp.esc(text) to authenticated;

select ok(not has_table_privilege('authenticated', 'public.jornada_sugestao_descarte', 'INSERT'), 'descarte sem gravação direta');
select ok(not has_function_privilege('anon', 'public.descartar_sugestao_visita(smallint, text, text)', 'EXECUTE'),
          'visitante não descarta sugestão');

select pg_temp.como('00000000-0000-0000-0000-0000000007a3');
set local role authenticated;
select ok(public.descartar_sugestao_visita(pg_temp.esc('Jda'), 'visita_recente') > 0, 'analista descarta sugestão da carteira');
select throws_ok($$ select public.descartar_sugestao_visita(pg_temp.esc('Jdb'), 'escola_fechada') $$, '42501', null,
                 'analista não descarta fora da carteira');
select throws_ok($$ select public.descartar_sugestao_visita(pg_temp.esc('Jda'), 'qualquer') $$, '22023', null, 'motivo inválido recusado');
select throws_ok($$ select public.descartar_sugestao_visita(pg_temp.esc('Jda'), 'outro', ' ') $$, '22023', null,
                 'motivo outro exige detalhe');
select ok(public.descartar_sugestao_visita(pg_temp.esc('Jda'), 'outro', 'Direção pediu nova data') > 0, 'motivo outro com detalhe aceito');
select is((select count(*)::int from public.jornada_sugestao_descarte), 2, 'analista lê os descartes da carteira');
reset role;

select is((select autor_nome from public.jornada_sugestao_descarte order by id limit 1), 'Analista Descarte', 'descarte guarda o autor');

select pg_temp.como('00000000-0000-0000-0000-0000000007a1');
set local role authenticated;
select ok(public.descartar_sugestao_visita(pg_temp.esc('Jdb'), 'acao_a_distancia') > 0, 'gerente descarta em qualquer escola');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000007a2');
set local role authenticated;
select throws_ok($$ select public.descartar_sugestao_visita(pg_temp.esc('Jda'), 'visita_recente') $$, '42501', null,
                 'coordenador não descarta');
select is((select count(*)::int from public.jornada_sugestao_descarte), 3, 'coordenador lê todos os descartes');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000007a4');
set local role authenticated;
select is((select count(*)::int from public.jornada_sugestao_descarte), 0, 'direção não lê descartes');
reset role;

select * from finish();
rollback;
