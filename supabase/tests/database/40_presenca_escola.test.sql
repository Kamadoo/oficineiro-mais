begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of1@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000000d1', 'Direção', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.x', false, null),
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro Um', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.um', false, 'manha'),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro Dois', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.dois', false, 'tarde');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select is((select public.marcar_presenca('entrada', -20.01, -43.8, 10) ->> 'motivo'), 'Fora do raio da escola', 'fora do raio não grava a entrada');
select is((select public.marcar_presenca('entrada', -20.0, -43.8, 900) ->> 'motivo'), 'Localização imprecisa', 'precisão pior que o raio pede nova tentativa');
select is((select count(*)::int from public.presenca_tentativas), 2, 'tentativas recusadas ficam guardadas');
select is((select public.minha_presenca_hoje() ->> 'proxima'), 'entrada', 'sem marcação a próxima é a entrada');
select is((select (public.marcar_presenca('entrada', -20.0, -43.8, 10) ->> 'aceita')::boolean), true, 'entrada dentro do raio');
select throws_ok($$select public.marcar_presenca('retorno_almoco', -20.0, -43.8, 10)$$, '22023', 'esta marcação não é a próxima da sequência',
                 'servidor recusa marcação fora da sequência');
select is((select (public.marcar_presenca('saida_almoco', -20.0, -43.8, 10) ->> 'aceita')::boolean), true, 'saída para almoço');
select is((select public.minha_presenca_hoje() ->> 'proxima'), 'retorno_almoco', 'em almoço a próxima é a volta');
select is((select (public.marcar_presenca('retorno_almoco', -20.0, -43.8, 10) ->> 'aceita')::boolean), true, 'volta do almoço');
select is((select (public.marcar_presenca('saida', -20.0, -43.8, 10) ->> 'aceita')::boolean), true, 'saída');
select is((select jsonb_array_length(public.minha_presenca_hoje() -> 'marcacoes')), 4, 'quatro marcações no dia');
select throws_ok($$select public.marcar_presenca('entrada', -20.0, -43.8, 10)$$, '22023', 'a jornada de hoje já foi encerrada',
                 'não abre outra jornada no mesmo dia');
select throws_ok($$select public.decidir_ajuste(1, true)$$, '42501', null, 'oficineiro não aprova solicitação');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
set local role authenticated;
select throws_ok($$select public.solicitar_ajuste('esquecimento', privado.hoje() + 1, '07:00', null, null, '15:00', 'Esqueci de marcar')$$,
                 '22023', 'escolha uma data até hoje', 'data futura não é aceita');
select throws_ok($$select public.solicitar_ajuste('esquecimento', privado.hoje(), '07:00', '11:00', '12:00', '16:30', 'Esqueci de marcar')$$,
                 '22023', 'com estes horários o dia passa de 8 horas trabalhadas', 'servidor recusa ajuste acima de 8 horas');
select lives_ok($$select public.solicitar_ajuste('esquecimento', privado.hoje(), '07:00', '11:00', '12:00', '16:00', 'Esqueci de marcar o dia')$$,
                'solicita ajuste com os quatro horários');
select throws_ok($$select public.solicitar_ajuste('falta', privado.hoje(), null, null, null, null, 'Consulta médica')$$,
                 '22023', 'já existe uma solicitação em análise para este dia', 'uma solicitação em análise por dia');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select throws_ok($$select public.decidir_ajuste((select id from public.presenca_ajustes limit 1), true)$$, '42501', null,
                 'coordenação acompanha, mas não decide o ajuste');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select throws_ok($$select public.decidir_ajuste((select id from public.presenca_ajustes limit 1), false, '')$$, '22023',
                 'explique por que a solicitação foi recusada', 'recusa pede explicação');
select lives_ok($$select public.decidir_ajuste((select id from public.presenca_ajustes limit 1), true)$$, 'direção aprova o ajuste');
select is((select situacao from public.painel_presenca() where nome = 'Oficineiro Um'), 'encerrado', 'direção vê a jornada encerrada no painel');
reset role;

select is((select trabalhado_min from public.presencas where oficineiro_id = '00000000-0000-0000-0000-0000000000f2'), 480,
          'ajuste aprovado recalcula o dia');

select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
set local role authenticated;
select lives_ok($$select public.assinar_espelho(privado.hoje())$$, 'oficineiro assina o espelho');
reset role;

select is((select concat_ws(' ', least(privado.trabalhado_dia(p), 480), greatest(0, privado.trabalhado_dia(p) - 480))
             from (select jsonb_populate_record(null::public.presencas, jsonb_build_object('inicio', '2026-11-03 07:28-03',
                    'pausa_inicio', '2026-11-03 11:32-03', 'pausa_fim', '2026-11-03 12:31-03', 'fim', '2026-11-03 16:40-03')) as p) x),
          '480 13', 'dia de 8h13 conta 8h00 e deixa 13 min não contabilizados');

select * from finish();
rollback;
