select vault.create_secret('sim', 'fsm_ambiente_teste', 'ambiente local');

insert into public.escolas (sigla, nome, endereco, carteira_id) values
  ('Ema', 'Ema - E. M. Morro Alto', 'Rua do Mirante, 60 - Morro Alto', 'CS1')
on conflict (sigla) do nothing;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a001', 'gerente@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a002', 'coordenador@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a003', 'admin@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a004', 'analista@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a005', 'direcao@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a006', 'oficineiro@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a007', 'oficineiro2@exemplo.test');

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000b' || lpad(n::text, 4, '0'))::uuid, 'extra' || n || '@exemplo.test'
from generate_series(1, 49) n;

insert into public.perfis (id, nome, papel, escola_id, carteira_id, turno, trocar_senha) values
  ('00000000-0000-0000-0000-00000000a001', 'Gerente Teste', 'gerente', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a002', 'Coordenadora Teste', 'coordenador', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a003', 'Administrador Teste', 'administrador', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a004', 'Analista Teste', 'analista', null, 'CS1', 'integral', false),
  ('00000000-0000-0000-0000-00000000a005', 'Direção Teste', 'direcao', (select id from public.escolas where sigla = 'Ebv'), null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a006', 'Oficineiro Teste', 'oficineiro', (select id from public.escolas where sigla = 'Ebv'), null, 'manha', false),
  ('00000000-0000-0000-0000-00000000a007', 'Oficineira Dois', 'oficineiro', (select id from public.escolas where sigla = 'Ejp'), null, 'tarde', false);

insert into public.perfis (id, nome, papel, escola_id, carteira_id, turno, trocar_senha)
select ('00000000-0000-0000-0000-0000000b' || lpad(n::text, 4, '0'))::uuid, 'Oficineiro Extra ' || n, 'oficineiro',
       (array(select id from public.escolas where sigla not in ('Ebv', 'Ejp') order by id))[(n - 1) % 9 + 1], null,
       case when n % 2 = 0 then 'tarde' else 'manha' end, false
from generate_series(1, 9) n;

update public.escolas set latitude = -20.0 + id * 0.01, longitude = -43.9 + id * 0.01, raio_m = 200, telefone = '3135410000';

insert into public.feriados (data, nome, tipo) values
  ('2026-11-02', 'Finados', 'feriado'),
  ('2026-11-15', 'Proclamação da República', 'feriado'),
  ('2026-11-20', 'Consciência Negra', 'feriado'),
  ('2026-12-24', 'Recesso de fim de ano', 'recesso')
on conflict do nothing;

insert into public.turmas (escola_id, ano, turma, matriculados)
select e.id, a, t, 20 + a
from public.escolas e, unnest(array[1, 2, 3, 4, 5]) a, unnest(array['A', 'B']) t
where e.sigla in ('Ebv', 'Ejp');

insert into public.grade_aulas (oficineiro_id, escola_id, ano_letivo, dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente, professor, espaco)
select o.id, o.escola_id, 2026, d, h, (time '07:00' + (h - 1) * interval '50 minutes'), (time '07:50' + (h - 1) * interval '50 minutes'),
       ((d + h) % 5) + 1, case when h % 2 = 0 then 'A' else 'B' end, 'R', 'Robótica', 'Matemática', 'Professora Exemplo', 'Laboratório'
from public.perfis o, generate_series(1, 5) d, generate_series(1, 3) h
where o.papel = 'oficineiro';

insert into public.perfis (id, nome, papel, escola_id, carteira_id, turno, trocar_senha)
select ('00000000-0000-0000-0000-0000000b' || lpad(n::text, 4, '0'))::uuid,
       case when n % 4 = 0 then 'Direção Extra ' else 'Oficineiro Novo ' end || n,
       (case when n % 4 = 0 then 'direcao' else 'oficineiro' end)::public.papel,
       (array(select id from public.escolas where sigla <> 'Ebv' order by id))[(n - 1) % 10 + 1], null, 'integral', true
from generate_series(10, 49) n;

insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status, enviado_em)
select id, escola_id, 2026, 'validada', '2026-10-01 10:00-03' from public.perfis where papel = 'oficineiro' and not trocar_senha;

insert into public.aulas_registro (oficineiro_id, escola_id, grade_aula_id, data, horario, inicio, fim, turma, tipo, solucao, presentes, matriculados, situacao, conteudo, componente, atividade, objetivo, engajamento)
select g.oficineiro_id, g.escola_id, g.id, dd::date, g.horario, g.inicio, g.fim, g.ano || 'º ' || g.turma, g.tipo, g.solucao,
       15, 20 + g.ano, case when extract(day from dd) :: int % 7 = 0 then 'Não realizada' else 'Realizada' end,
       'Conteúdo trabalhado em aula', g.componente, 'Atividade prática', 'Sim', 4
from public.grade_aulas g
cross join generate_series(date '2026-10-01', date '2026-11-09', interval '1 day') dd
where extract(isodow from dd) = g.dia_semana and (dd::date < date '2026-11-09' or g.fim <= time '10:00') and dd::date not in (select data from public.feriados);

insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim, distancia_inicio_m, distancia_fim_m)
select o.id, o.escola_id, dd::date, dd + time '07:00' + interval '3 hours', dd + time '15:00' + interval '3 hours', 20, 30
from public.perfis o
cross join generate_series(date '2026-10-01', date '2026-11-06', interval '1 day') dd
where o.papel = 'oficineiro' and not o.trocar_senha and extract(isodow from dd) between 1 and 5 and dd::date not in (select data from public.feriados);

insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, fechado_em)
select id, escola_id, date '2026-10-01', 'fechado', '2026-11-03 10:00-03' from public.perfis where papel = 'oficineiro' and not trocar_senha;

insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, status, criada_por)
select '00000000-0000-0000-0000-00000000a004', e.id, date '2026-11-09' + (row_number() over (order by e.id))::int, time '09:00', 'analista', 'Acompanhamento', 'Alunos', 'agendada', '00000000-0000-0000-0000-00000000a004'
from public.escolas e where e.carteira_id = 'CS1' and e.sigla <> 'Ema';

insert into public.visitas (analista_id, escola_id, data, tipo, subtipo, participantes, solucao, observacao, objetivo, engajamento)
select '00000000-0000-0000-0000-00000000a004', e.id, date '2026-10-20' + (row_number() over (order by e.id))::int, 'Acompanhamento', 'Observação de aula', 'Alunos', 'Robótica', 'Visita de rotina', 'Sim', 4
from public.escolas e where e.carteira_id = 'CS1' and e.sigla <> 'Ema';

insert into public.visitas (analista_id, escola_id, data, tipo, subtipo, participantes, solucao, observacao, objetivo, engajamento)
select '00000000-0000-0000-0000-00000000a004', id, date '2026-11-09', 'Acompanhamento', 'Reunião com a direção', 'Direção', 'Robótica', 'Visita fora da agenda', 'Sim', 3
from public.escolas where sigla = 'Ejp';

insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref)
select e.id, 'Pessoa ' || e.sigla || ' ' || n, case when n % 3 = 0 then 'P' else 'A' end, (n % 9) + 1, n % 40 - 1, n * 2, null, date '2026-11-01'
from public.escolas e, generate_series(1, 12) n
where e.sigla in ('Ejp', 'Esf');

insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref)
select e.id, 'Pessoa ' || e.sigla || ' ' || n, case when n % 3 = 0 then 'P' else 'A' end, (n % 9) + 1, n % 40 - 1, n * 2, null, date '2026-11-01'
from public.escolas e, generate_series(1, 60) n
where e.sigla = 'Ebv';

insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref)
select e.id, 'Pessoa ' || e.sigla || ' ' || n, case when n % 4 = 0 then 'P' else 'A' end, (n % 9) + 1,
       case when n % 10 = 0 then 3 when n % 3 = 0 then -1 else 35 + n end, case when n % 3 = 0 then 0 else n end, null, date '2026-11-01'
from public.escolas e, generate_series(1, 45) n
where e.sigla in ('Ema', 'Ecl', 'Erv');

insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref)
select e.id, 'Pessoa ' || e.sigla || ' ' || n, case when n % 3 = 0 then 'P' else 'A' end, (n % 9) + 1, n % 40 + 2, n, null, date '2026-10-25'
from public.escolas e, generate_series(1, 55) n
where e.sigla = 'Ebv';

select set_config('request.jwt.claims', '{"role":"service_role"}', false);

select public.importar_os(jsonb_build_object(
  'numero', o.numero, 'secretaria', o.secretaria, 'arquivo', o.arquivo, 'recebida_em', o.recebida_em,
  'linhas', (
    select jsonb_agg(jsonb_build_object(
      'seq', n, 'nome', o.prefixo || ' ' || n, 'email', lower(o.secretaria) || '.servidor' || n || '@exemplo.test',
      'cpf', c.cpf, 'matricula', lpad((o.base + n)::text, 6, '0'),
      'cargo', case when n % 3 = 0 then 'Coordenador pedagógico' else 'Professor' end,
      'tipo', case when n % 4 = 0 then 'Contratado' else 'Efetivo' end,
      'lotacao', 'Escola ' || e.sigla, 'escola_sigla', e.sigla, 'carteira_id', e.carteira_id) order by n)
    from generate_series(1, o.quantidade) n
    cross join lateral (
      select e.sigla, e.carteira_id from public.escolas e where e.carteira_id is not null
      order by e.id offset (n % 6) limit 1) e
    cross join lateral (select lpad((o.base * 1000 + n * 7919)::text, 9, '0') as b) b
    cross join lateral (
      select ((sum(substr(b.b, i, 1)::int * (11 - i)) * 10) % 11) % 10 as d1 from generate_series(1, 9) i) d1
    cross join lateral (
      select b.b || d1.d1 || ((sum(substr(b.b || d1.d1, i, 1)::int * (12 - i)) * 10) % 11) % 10 as cpf
      from generate_series(1, 10) i) c)))
from (values
  ('101', 'SEMED', 'os_semed_101_2026.xlsx', '2026-10-20', 'Servidora Exemplo', 18, 310),
  ('007', 'SEMAD', 'os_semad_007_2026.xlsx', '2026-11-04', 'Servidor Exemplo', 8, 420)
) o(numero, secretaria, arquivo, recebida_em, prefixo, quantidade, base);

select set_config('request.jwt.claims', '', false);

update public.onboarding_os set importada_por = '00000000-0000-0000-0000-00000000a001',
  importada_em = (recebida_em + time '10:00') at time zone 'America/Sao_Paulo';

update public.onboarding_itens i
   set status = 'concluido', baixa_data = date '2026-10-28', baixa_forma = 'Acesso criado na plataforma',
       baixa_obs = 'Primeiro acesso acompanhado pela analista', baixa_por = '00000000-0000-0000-0000-00000000a001'
 where i.os_id = 'SEMED-101' and i.id % 2 = 0;

insert into public.presenca_marcacoes (presenca_id, oficineiro_id, tipo, registrado_em, recebido_em, sem_internet,
                                       diferenca_relogio_s, precisao_m, distancia_m, dentro_raio, aparelho)
select p.id, p.oficineiro_id, m.tipo, m.quando, m.quando + make_interval(secs => m.atraso), m.atraso > 0, m.atraso,
       12, case m.tipo when 'entrada' then p.distancia_inicio_m else p.distancia_fim_m end, true, 'aparelho-exemplo-01'
from public.presencas p
cross join lateral (values
  ('entrada', p.inicio,
   case when (p.oficineiro_id = '00000000-0000-0000-0000-00000000a006' and p.data = date '2026-11-04')
          or (p.oficineiro_id = '00000000-0000-0000-0000-00000000a007' and p.data = date '2026-10-29') then 5100 else 0 end),
  ('saida', p.fim,
   case when p.oficineiro_id = '00000000-0000-0000-0000-00000000a007' and p.data = date '2026-11-05' then 2400 else 0 end)
) m(tipo, quando, atraso)
where p.oficineiro_id in ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-00000000a007')
  and p.data >= date '2026-10-27';

insert into public.presenca_ajustes (oficineiro_id, escola_id, data, tipo, entrada, saida, motivo, status, pedido_em,
                                     analisado_por, analisado_em, analise_obs)
select o.id, o.escola_id, a.data, a.tipo, a.entrada, a.saida, a.motivo, a.status, a.pedido, a.por, a.em, a.obs
from public.perfis o
join (values
  ('00000000-0000-0000-0000-00000000a006'::uuid, date '2026-11-05', 'esquecimento', time '07:05', time '15:02',
   'Esqueci de registrar a entrada e a saída por causa da reunião com a direção.', 'em_analise',
   timestamptz '2026-11-05 16:10-03', null::uuid, null::timestamptz, null),
  ('00000000-0000-0000-0000-00000000a006'::uuid, date '2026-10-15', 'falta', null::time, null::time,
   'Consulta médica no período da manhã, com atestado entregue à secretaria.', 'aprovada',
   timestamptz '2026-10-15 18:00-03', '00000000-0000-0000-0000-00000000a005'::uuid, timestamptz '2026-10-16 09:30-03',
   'Atestado conferido.'),
  ('00000000-0000-0000-0000-00000000a007'::uuid, date '2026-10-22', 'fora_raio', time '13:00', time '19:00',
   'A localização do celular indicou fora da escola, mas eu estava no laboratório.', 'recusada',
   timestamptz '2026-10-22 19:30-03', '00000000-0000-0000-0000-00000000a002'::uuid, timestamptz '2026-10-23 11:00-03',
   'Sem confirmação da direção para o horário informado.')
) a(id, data, tipo, entrada, saida, motivo, status, pedido, por, em, obs) on a.id = o.id;

insert into public.presencas_analista (analista_id, escola_id, data, inicio, fim, distancia_inicio_m, distancia_fim_m, observacao)
select v.analista_id, v.escola_id, v.data, (v.data + time '09:00') at time zone 'America/Sao_Paulo',
       (v.data + time '11:15') at time zone 'America/Sao_Paulo', 25, 30, 'Visita registrada na escola'
from public.visitas v
where v.analista_id = '00000000-0000-0000-0000-00000000a004' and v.data < date '2026-11-09';

insert into public.visitas_historico (visita_id, antes, por, em)
select v.id, to_jsonb(v) || jsonb_build_object('observacao', 'Visita de rotina, texto antes da correção', 'engajamento', 3),
       v.analista_id, (v.data + time '17:00') at time zone 'America/Sao_Paulo'
from public.visitas v
where v.analista_id = '00000000-0000-0000-0000-00000000a004'
order by v.data
limit 2;

insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento, texto, por, em)
select a.id, a.oficineiro_id, a.escola_id, h.evento, h.texto, h.por, (a.data + h.hora) at time zone 'America/Sao_Paulo'
from (
  select r.* from public.aulas_registro r
  where r.oficineiro_id = '00000000-0000-0000-0000-00000000a006' and r.situacao = 'Realizada'
  order by r.data desc, r.horario, r.id limit 3
) a
cross join lateral (values
  ('confirmada', null, '00000000-0000-0000-0000-00000000a005'::uuid, time '16:00'),
  ('contestada', 'A turma estava em avaliação neste horário.', '00000000-0000-0000-0000-00000000a005'::uuid, time '16:05'),
  ('corrigida', 'Horário ajustado para o segundo tempo.', '00000000-0000-0000-0000-00000000a006'::uuid, time '17:30')
) h(evento, texto, por, hora)
where h.evento = 'confirmada' or a.id = (
  select r.id from public.aulas_registro r
  where r.oficineiro_id = '00000000-0000-0000-0000-00000000a006' and r.situacao = 'Realizada'
  order by r.data desc, r.horario, r.id limit 1);

insert into public.mudancas_escola (usuario_id, escola_anterior, escola_nova, vale_a_partir, motivo, criado_por, criado_em)
select o.id, o.escola_id,
       (select e.id from public.escolas e where e.id <> o.escola_id and e.carteira_id is not null order by e.id limit 1),
       date '2026-11-16', 'Ampliação de atendimento', '00000000-0000-0000-0000-00000000a002', timestamptz '2026-11-06 14:00-03'
from public.perfis o
where o.id = '00000000-0000-0000-0000-0000000b0001';

insert into public.espelho_assinaturas (oficineiro_id, competencia, assinado_em) values
  ('00000000-0000-0000-0000-00000000a006', date '2026-10-01', timestamptz '2026-11-03 10:00-03');

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
