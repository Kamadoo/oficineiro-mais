begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a0', 'adm@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a0', 'Administração TI', 'administrador', 'adm.ti', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.eventos(p_acao text) returns bigint language sql security definer as $$
  select count(*) from auditoria.eventos where acao = p_acao;
$$;
grant execute on function pg_temp.eventos(text) to authenticated;
create function pg_temp.ultimo(p_acao text) returns jsonb language sql security definer as $$
  select detalhes from auditoria.eventos where acao = p_acao order by id desc limit 1;
$$;
grant execute on function pg_temp.ultimo(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select lives_ok($$select public.registrar_atividade('EXPORTACAO', '{"tela":"Minhas atividades","arquivo":"atividades-2026-10","linhas":12,"formato":"Excel","senha":"x"}')$$, 'oficineiro registra exportação');
select is(pg_temp.eventos('EXPORTACAO'), 1::bigint, 'exportação gravada uma vez');
select ok(not (pg_temp.ultimo('EXPORTACAO') ? 'senha'), 'campos desconhecidos são descartados');
select is((pg_temp.ultimo('EXPORTACAO') ->> 'linhas')::int, 12, 'quantidade de linhas guardada');
select lives_ok($$select public.registrar_atividade('EXPORTACAO', '{"tela":"Minhas atividades","arquivo":"atividades-2026-10","linhas":12,"formato":"Excel"}')$$, 'repetição imediata é aceita');
select is(pg_temp.eventos('EXPORTACAO'), 1::bigint, 'repetição idêntica em menos de um minuto não polui o registro');
select lives_ok($$select public.registrar_atividade('CONSULTA', '{"tela":"Teste","descricao":"CPF 529.982.247-25 e 52998224725"}')$$, 'consulta registrada');
select ok(pg_temp.ultimo('CONSULTA') ->> 'descricao' !~ '\d{3}\.?\d{3}\.?\d{3}-?\d{2}', 'números de CPF nunca entram no registro');
select lives_ok($$select public.registrar_atividade('PRESENCA_RECUSADA', '{"evento":"inicio","motivo":"a presença deste dia já foi iniciada","distancia_m":35}')$$, 'tentativa recusada registrada');
select throws_ok($$select public.registrar_atividade('INSERT', '{}')$$, '22023', null, 'tipos fora da lista são recusados');
select throws_ok($$select * from public.admin_atividades()$$, '42501', null, 'só o administrador consulta as atividades');

reset role;
insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m)
  values ('00000000-0000-0000-0000-0000000000f1', (select id from public.escolas where sigla = 'Aaa'), current_date, now() - interval '3 hours', 35);
update public.presencas set fim = now(), distancia_fim_m = 20 where oficineiro_id = '00000000-0000-0000-0000-0000000000f1';

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
update public.presencas set conferencia_status = 'conferida' where oficineiro_id = '00000000-0000-0000-0000-0000000000f1';
select pg_temp.como(null);
reset role;
select set_config('request.jwt.claims', '', true);

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'auth' and table_name = 'users' and column_name = 'last_sign_in_at') then
    alter table auth.users add column last_sign_in_at timestamptz;
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'fsm_registrar_acesso' and tgrelid = 'auth.users'::regclass) then
    create trigger fsm_registrar_acesso after update of last_sign_in_at on auth.users
      for each row execute function auditoria.trigger_acesso();
  end if;
end $$;
update auth.users set last_sign_in_at = now() where id = '00000000-0000-0000-0000-0000000000f1';
update auth.users set last_sign_in_at = now() + interval '1 second' where id = '00000000-0000-0000-0000-0000000000f1';
select is(pg_temp.eventos('ACESSO'), 1::bigint, 'entrada no site gravada sem repetir em seguida');
select is((select usuario_id::text || ' ' || papel from auditoria.eventos where acao = 'ACESSO'), '00000000-0000-0000-0000-0000000000f1 oficineiro', 'entrada gravada em nome da pessoa');
update auth.users set last_sign_in_at = now() where id = '00000000-0000-0000-0000-0000000000a0';
select is(pg_temp.eventos('ACESSO'), 2::bigint, 'cada pessoa tem a própria entrada');

select pg_temp.como('00000000-0000-0000-0000-0000000000a0');
set local role authenticated;
select is((select evento from public.admin_atividades(p_usuario => '00000000-0000-0000-0000-0000000000f1', p_categoria => 'acesso')), 'acesso', 'filtro de entradas no site');
select is((select count(*) from public.admin_atividades(p_usuario => '00000000-0000-0000-0000-0000000000f1', p_categoria => 'presenca')), 2::bigint, 'entrada e saída da presença aparecem');
select is((select escola || ' / ' || alvo_nome from public.admin_atividades(p_categoria => 'presenca') where evento = 'entrada'), 'Aaa - Escola A / Oficineiro F', 'entrada traz escola e pessoa');
select is((select (detalhes -> 'distancia_fim_m' ->> 'para')::int from public.admin_atividades(p_categoria => 'presenca') where evento = 'saida'), 20, 'saída traz a distância');
select is((select nome || ' / ' || alvo_nome from public.admin_atividades(p_categoria => 'conferencia')), 'Coordenação / Oficineiro F', 'conferência da coordenação aparece com quem conferiu e de quem');
select is((select count(*) from public.admin_atividades(p_categoria => 'recusa')), 1::bigint, 'tentativas recusadas aparecem');
select is((select count(*) from public.admin_atividades(p_categoria => 'exportacao')), 1::bigint, 'exportações aparecem');
select is((select count(*) from public.admin_atividades(p_categoria => 'consulta')), 1::bigint, 'consultas aparecem');
select is((select count(*) from public.admin_atividades(p_desde => current_date + 1)), 0::bigint, 'filtro de período respeitado');
select throws_ok($$select * from public.admin_atividades(p_categoria => 'tudo')$$, '22023', null, 'categoria inválida recusada');
reset role;

select * from finish();
rollback;
