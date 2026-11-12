select vault.create_secret('sim', 'fsm_ambiente_teste', 'ambiente local');

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a001', 'gerente@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a002', 'coordenador@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a003', 'admin@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a004', 'analista@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a005', 'direcao@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a006', 'oficineiro@exemplo.test'),
  ('00000000-0000-0000-0000-00000000a007', 'oficineiro2@exemplo.test');

insert into public.perfis (id, nome, papel, escola_id, carteira_id, turno, trocar_senha) values
  ('00000000-0000-0000-0000-00000000a001', 'Gerente Teste', 'gerente', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a002', 'Coordenadora Teste', 'coordenador', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a003', 'Administrador Teste', 'administrador', null, null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a004', 'Analista Teste', 'analista', null, 'CS1', 'integral', false),
  ('00000000-0000-0000-0000-00000000a005', 'Direção Teste', 'direcao', (select id from public.escolas where sigla = 'Ebv'), null, 'integral', false),
  ('00000000-0000-0000-0000-00000000a006', 'Oficineiro Teste', 'oficineiro', (select id from public.escolas where sigla = 'Ebv'), null, 'manha', false),
  ('00000000-0000-0000-0000-00000000a007', 'Oficineira Dois', 'oficineiro', (select id from public.escolas where sigla = 'Ejp'), null, 'tarde', false);

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

insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status, enviado_em)
select id, escola_id, 2026, 'validada', '2026-10-01 10:00-03' from public.perfis where papel = 'oficineiro';

insert into public.aulas_registro (oficineiro_id, escola_id, grade_aula_id, data, horario, inicio, fim, turma, tipo, solucao, presentes, matriculados, situacao, conteudo, componente, atividade, objetivo, engajamento)
select g.oficineiro_id, g.escola_id, g.id, dd::date, g.horario, g.inicio, g.fim, g.ano || 'º ' || g.turma, g.tipo, g.solucao,
       15, 20 + g.ano, case when extract(day from dd) :: int % 7 = 0 then 'Não realizada' else 'Realizada' end,
       'Conteúdo trabalhado em aula', g.componente, 'Atividade prática', 'Sim', 4
from public.grade_aulas g
cross join generate_series(date '2026-10-01', date '2026-11-06', interval '1 day') dd
where extract(isodow from dd) = g.dia_semana and dd::date not in (select data from public.feriados);

insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim, distancia_inicio_m, distancia_fim_m)
select o.id, o.escola_id, dd::date, dd + time '07:00' + interval '3 hours', dd + time '15:00' + interval '3 hours', 20, 30
from public.perfis o
cross join generate_series(date '2026-10-01', date '2026-11-06', interval '1 day') dd
where o.papel = 'oficineiro' and extract(isodow from dd) between 1 and 5 and dd::date not in (select data from public.feriados);

insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, fechado_em)
select id, escola_id, date '2026-10-01', 'fechado', '2026-11-03 10:00-03' from public.perfis where papel = 'oficineiro';

insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, status, criada_por)
select '00000000-0000-0000-0000-00000000a004', e.id, date '2026-11-09' + (row_number() over (order by e.id))::int, time '09:00', 'analista', 'Acompanhamento', 'Alunos', 'agendada', '00000000-0000-0000-0000-00000000a004'
from public.escolas e where e.carteira_id = 'CS1';

insert into public.visitas (analista_id, escola_id, data, tipo, subtipo, participantes, solucao, observacao, objetivo, engajamento)
select '00000000-0000-0000-0000-00000000a004', e.id, date '2026-10-20' + (row_number() over (order by e.id))::int, 'Acompanhamento', 'Observação de aula', 'Alunos', 'Robótica', 'Visita de rotina', 'Sim', 4
from public.escolas e where e.carteira_id = 'CS1';

insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref)
select e.id, 'Pessoa ' || e.sigla || ' ' || n, case when n % 3 = 0 then 'P' else 'A' end, (n % 9) + 1, n % 40 - 1, n * 2, null, date '2026-11-01'
from public.escolas e, generate_series(1, 12) n
where e.carteira_id = 'CS1';

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
