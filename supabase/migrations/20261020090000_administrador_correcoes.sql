create table if not exists public.configuracoes (
  id               smallint primary key default 1 check (id = 1),
  suporte_email    text check (length(suporte_email) <= 120),
  suporte_telefone text check (length(suporte_telefone) <= 20),
  suporte_horario  text check (length(suporte_horario) <= 120),
  atualizado_em    timestamptz not null default now()
);
insert into public.configuracoes (id) values (1) on conflict do nothing;
alter table public.configuracoes enable row level security;
revoke all on public.configuracoes from anon, authenticated;
grant select on public.configuracoes to authenticated;
drop policy if exists configuracoes_ler on public.configuracoes;
create policy configuracoes_ler on public.configuracoes for select to authenticated
  using ((select privado.acesso_ok()));
drop trigger if exists auditoria on public.configuracoes;
create trigger auditoria after insert or update or delete on public.configuracoes
  for each row execute function auditoria.trigger_linha();

create table if not exists public.feriados (
  data      date primary key,
  nome      text not null check (length(nome) between 2 and 80),
  tipo      text not null default 'feriado' check (tipo in ('feriado', 'recesso', 'ponto_facultativo')),
  criado_em timestamptz not null default now()
);
alter table public.feriados enable row level security;
revoke all on public.feriados from anon, authenticated;
grant select on public.feriados to authenticated;
drop policy if exists feriados_ler on public.feriados;
create policy feriados_ler on public.feriados for select to authenticated
  using ((select privado.acesso_ok()));
drop trigger if exists auditoria on public.feriados;
create trigger auditoria after insert or update or delete on public.feriados
  for each row execute function auditoria.trigger_linha();

alter table public.presencas drop constraint if exists presencas_conferencia_check;
alter table public.presencas add constraint presencas_conferencia_check
  check (conferencia in ('Fora do raio', 'Sem encerramento', 'Enviado sem internet', 'Sem localização', 'Escola sem localização',
                         'Lançada pelo administrador'));

create or replace function privado.feriado(p_data date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select to_char(p_data, 'MM-DD') in ('01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '11-20', '12-25')
      or p_data in ('2026-02-16', '2026-02-17', '2026-04-03', '2026-06-04', '2027-02-08', '2027-02-09', '2027-03-26', '2027-05-27')
      or exists (select 1 from public.feriados f where f.data = p_data);
$$;

create or replace function privado.minutos_previstos(p_data date)
returns integer
language sql stable security definer set search_path = ''
as $$ select case when extract(isodow from p_data) between 1 and 5 and not privado.feriado(p_data) then 480 else 0 end $$;

create or replace function privado.enviar_lembrete(p_grade_aula_id bigint, p_data date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  g public.grade_aulas;
  v_ult timestamptz;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() or privado.eh_admin() then perform privado.negar(); end if;
  select * into g from public.grade_aulas where id = p_grade_aula_id;
  if g.id is null or not privado.ve_escola(g.escola_id) then perform privado.negar(); end if;
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('a aula ainda não aconteceu'); end if;
  if date_trunc('month', p_data) <> date_trunc('month', privado.hoje()) then perform privado.invalido('o mês desta aula já terminou e ela não pode mais ser registrada'); end if;
  if g.ano_letivo <> extract(year from p_data) or g.dia_semana <> extract(isodow from p_data) then perform privado.invalido('esta aula não está na grade neste dia'); end if;
  if exists (select 1 from public.aulas_registro r where r.grade_aula_id = g.id and r.data = p_data) then perform privado.invalido('esta aula já foi registrada'); end if;
  select enviado_em into v_ult from public.lembretes_registro where grade_aula_id = g.id and data = p_data;
  if v_ult is not null and v_ult > now() - interval '20 hours' then perform privado.invalido('o lembrete desta aula já foi enviado hoje'); end if;
  insert into public.lembretes_registro as l (oficineiro_id, escola_id, grade_aula_id, data, enviado_por)
  values (g.oficineiro_id, g.escola_id, g.id, p_data, auth.uid())
  on conflict (grade_aula_id, data) do update set enviado_em = now(), enviado_por = auth.uid()
  returning l.enviado_em into v_ult;
  return v_ult;
end;
$$;

create or replace function privado.admin_correcao(p_tabela text, p_registro text, p_motivo text, p_detalhes jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform auditoria.registrar('ADMIN_CORRECAO', p_tabela, p_registro, coalesce(p_detalhes, '{}'::jsonb) || jsonb_build_object('motivo', p_motivo));
end;
$$;
revoke all on function privado.admin_correcao(text, text, text, jsonb) from public, anon, authenticated;

create or replace function privado.admin_salvar_configuracoes(p_email text, p_telefone text, p_horario text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_email text := nullif(trim(coalesce(p_email, '')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), '');
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if v_email is not null and v_email !~ '^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$' then perform privado.invalido('e-mail do suporte inválido'); end if;
  if v_tel is not null and length(v_tel) not between 10 and 11 then perform privado.invalido('telefone do suporte inválido: use DDD e número'); end if;
  update public.configuracoes
     set suporte_email = lower(v_email), suporte_telefone = v_tel,
         suporte_horario = nullif(left(trim(coalesce(p_horario, '')), 120), ''), atualizado_em = now()
   where id = 1;
end;
$$;

create or replace function privado.admin_salvar_feriado(p_data date, p_nome text, p_tipo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_nome text := trim(coalesce(p_nome, ''));
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if p_data is null then perform privado.invalido('escolha a data'); end if;
  if length(v_nome) < 2 or length(v_nome) > 80 then perform privado.invalido('nome: de 2 a 80 caracteres'); end if;
  if coalesce(p_tipo, '') not in ('feriado', 'recesso', 'ponto_facultativo') then perform privado.invalido('tipo inválido'); end if;
  insert into public.feriados (data, nome, tipo) values (p_data, v_nome, p_tipo)
  on conflict (data) do update set nome = excluded.nome, tipo = excluded.tipo;
end;
$$;

create or replace function privado.admin_remover_feriado(p_data date)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  delete from public.feriados where data = p_data;
  if not found then perform privado.invalido('data não encontrada entre os feriados cadastrados'); end if;
end;
$$;

create or replace function privado.admin_consulta(p_usuario uuid, p_competencia date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_ini date := date_trunc('month', coalesce(p_competencia, privado.hoje()))::date;
  v_fim date := (date_trunc('month', coalesce(p_competencia, privado.hoje())) + interval '1 month')::date;
  v_p public.perfis;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  select * into v_p from public.perfis where id = p_usuario;
  if v_p.id is null then perform privado.invalido('conta não encontrada'); end if;
  return jsonb_build_object(
    'perfil', jsonb_build_object('id', v_p.id, 'nome', v_p.nome, 'usuario', v_p.usuario, 'papel', v_p.papel::text,
                                 'escola_id', v_p.escola_id, 'carteira_id', v_p.carteira_id, 'ativo', v_p.ativo,
                                 'jornada_inicio', to_char(v_p.jornada_inicio, 'HH24:MI')),
    'competencia', v_ini,
    'presencas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'data', p.data, 'escola_id', p.escola_id, 'inicio', p.inicio, 'fim', p.fim,
        'conferencia', p.conferencia, 'conferencia_status', p.conferencia_status,
        'trabalhado_min', p.trabalhado_min, 'previsto_min', p.previsto_min,
        'excedente_min', p.excedente_min, 'excedente_status', p.excedente_status,
        'deficit_min', p.deficit_min, 'deficit_status', p.deficit_status,
        'atraso_min', p.atraso_min, 'horario_status', p.horario_status,
        'compensacao_min', p.compensacao_min, 'compensar_em', p.compensar_em) order by p.data)
      from public.presencas p where p.oficineiro_id = v_p.id and p.data >= v_ini and p.data < v_fim), '[]'::jsonb),
    'registros', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'data', r.data, 'inicio', to_char(r.inicio, 'HH24:MI'), 'turma', r.turma, 'componente', r.componente,
        'situacao', r.situacao, 'revisao_status', r.revisao_status, 'revisao_obs', r.revisao_obs) order by r.data, r.inicio)
      from public.aulas_registro r where r.oficineiro_id = v_p.id and r.data >= v_ini and r.data < v_fim), '[]'::jsonb),
    'relatorio', (select jsonb_build_object('id', m.id, 'status', m.status, 'motivo_devolucao', m.motivo_devolucao)
                    from public.relatorios_mensais m where m.oficineiro_id = v_p.id and m.competencia = v_ini),
    'grades', coalesce((select jsonb_agg(jsonb_build_object('ano_letivo', e.ano_letivo, 'status', e.status, 'comentario', e.comentario)
                                         order by e.ano_letivo)
                          from public.grade_envios e where e.oficineiro_id = v_p.id), '[]'::jsonb)
  );
end;
$$;

create or replace function privado.admin_corrigir_presenca(p_id bigint, p_inicio timestamptz, p_fim timestamptz, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.presencas;
  v_motivo text;
  v_data date;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v from public.presencas where id = p_id for update;
  if v.id is null then perform privado.invalido('presença não encontrada'); end if;
  if p_inicio is null then perform privado.invalido('informe o horário de início'); end if;
  v_data := (p_inicio at time zone 'America/Sao_Paulo')::date;
  if v_data <> v.data then perform privado.invalido('o início precisa ficar no mesmo dia da presença'); end if;
  if p_fim is not null and p_fim <= p_inicio then perform privado.invalido('o encerramento precisa ser depois do início'); end if;
  if p_fim is not null and (p_fim at time zone 'America/Sao_Paulo')::date <> v.data then perform privado.invalido('o encerramento precisa ficar no mesmo dia da presença'); end if;
  update public.presencas set inicio = p_inicio, fim = p_fim where id = p_id;
  if p_fim is not null then
    perform privado.calcular_dia(p_id);
  else
    update public.presencas
       set trabalhado_min = null, previsto_min = null, compensacao_min = 0, excedente_min = 0, excedente_status = 'dentro',
           deficit_min = 0, deficit_status = 'dentro'
     where id = p_id;
  end if;
  perform privado.admin_correcao('presencas', p_id::text, v_motivo, jsonb_build_object(
    'inicio', jsonb_build_object('de', v.inicio, 'para', p_inicio),
    'fim', jsonb_build_object('de', v.fim, 'para', p_fim)));
end;
$$;

create or replace function privado.admin_lancar_presenca(p_oficineiro uuid, p_inicio timestamptz, p_fim timestamptz, p_motivo text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_of public.perfis;
  v_motivo text;
  v_data date;
  v_id bigint;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v_of from public.perfis where id = p_oficineiro;
  if v_of.id is null or v_of.papel::text <> 'oficineiro' then perform privado.invalido('escolha uma conta de oficineiro'); end if;
  if p_inicio is null then perform privado.invalido('informe o horário de início'); end if;
  v_data := (p_inicio at time zone 'America/Sao_Paulo')::date;
  if v_data > privado.hoje() then perform privado.invalido('não é possível lançar presença em data futura'); end if;
  if p_fim is not null and p_fim <= p_inicio then perform privado.invalido('o encerramento precisa ser depois do início'); end if;
  if p_fim is not null and (p_fim at time zone 'America/Sao_Paulo')::date <> v_data then perform privado.invalido('o encerramento precisa ficar no mesmo dia'); end if;
  if exists (select 1 from public.presencas where oficineiro_id = v_of.id and data = v_data) then
    perform privado.invalido('já existe presença neste dia: corrija a presença existente');
  end if;
  insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim, conferencia, conferencia_status)
  values (v_of.id, v_of.escola_id, v_data, p_inicio, p_fim, 'Lançada pelo administrador', 'conferida')
  returning id into v_id;
  if p_fim is not null then perform privado.calcular_dia(v_id); end if;
  perform privado.admin_correcao('presencas', v_id::text, v_motivo, jsonb_build_object('lancada', true, 'data', v_data));
  return v_id;
end;
$$;

create or replace function privado.admin_situacao_presenca(p_id bigint, p_campo text, p_valor text, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.presencas;
  v_motivo text;
  v_de text;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v from public.presencas where id = p_id for update;
  if v.id is null then perform privado.invalido('presença não encontrada'); end if;
  if p_campo = 'conferencia' then
    if p_valor not in ('pendente', 'conferida', 'nao_conferida') then perform privado.invalido('situação inválida'); end if;
    v_de := v.conferencia_status;
    update public.presencas set conferencia_status = p_valor where id = p_id;
  elsif p_campo = 'excedente' then
    if p_valor not in ('dentro', 'pendente', 'aguardando', 'autorizado', 'nao') then perform privado.invalido('situação inválida'); end if;
    v_de := v.excedente_status;
    update public.presencas set excedente_status = p_valor where id = p_id;
  elsif p_campo = 'deficit' then
    if p_valor not in ('dentro', 'pendente', 'aguardando', 'autorizado', 'nao') then perform privado.invalido('situação inválida'); end if;
    v_de := v.deficit_status;
    update public.presencas set deficit_status = p_valor where id = p_id;
    if v.compensar_em is not null then perform privado.recalcular_compensacao(v.oficineiro_id, v.compensar_em); end if;
  elsif p_campo = 'horario' then
    if p_valor not in ('dentro', 'pendente', 'aguardando', 'conferido', 'nao') then perform privado.invalido('situação inválida'); end if;
    v_de := v.horario_status;
    update public.presencas set horario_status = p_valor where id = p_id;
  else
    perform privado.invalido('campo inválido');
  end if;
  if v_de = p_valor then perform privado.invalido('a situação já é esta'); end if;
  perform privado.admin_correcao('presencas', p_id::text, v_motivo,
    jsonb_build_object(p_campo || '_status', jsonb_build_object('de', v_de, 'para', p_valor)));
end;
$$;

create or replace function privado.admin_reabrir_mes(p_oficineiro uuid, p_competencia date, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_of public.perfis;
  v_motivo text;
  v_comp date := date_trunc('month', p_competencia)::date;
  v_m public.relatorios_mensais;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v_of from public.perfis where id = p_oficineiro;
  if v_of.id is null or v_of.papel::text <> 'oficineiro' then perform privado.invalido('escolha uma conta de oficineiro'); end if;
  if p_competencia is null or v_comp > date_trunc('month', privado.hoje())::date then perform privado.invalido('escolha um mês que já começou'); end if;
  select * into v_m from public.relatorios_mensais where oficineiro_id = v_of.id and competencia = v_comp for update;
  if v_m.id is not null and v_m.status = 'devolvido' then perform privado.invalido('este mês já está aberto para correção'); end if;
  if v_m.id is null then
    if v_comp = date_trunc('month', privado.hoje())::date then perform privado.invalido('o mês atual já está aberto'); end if;
    insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, motivo_devolucao)
    values (v_of.id, v_of.escola_id, v_comp, 'devolvido', v_motivo);
  else
    update public.relatorios_mensais set status = 'devolvido', motivo_devolucao = v_motivo where id = v_m.id;
  end if;
  perform privado.admin_correcao('relatorios_mensais', v_of.id::text, v_motivo,
    jsonb_build_object('competencia', v_comp, 'status', jsonb_build_object('de', coalesce(v_m.status, 'fechado'), 'para', 'devolvido')));
end;
$$;

create or replace function privado.admin_situacao_grade(p_oficineiro uuid, p_ano smallint, p_status text, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_motivo text;
  v_de text;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  if p_status not in ('enviada', 'validada', 'devolvida', 'alterada') then perform privado.invalido('situação inválida'); end if;
  select status into v_de from public.grade_envios where oficineiro_id = p_oficineiro and ano_letivo = p_ano for update;
  if v_de is null then perform privado.invalido('esta grade ainda não foi enviada'); end if;
  if v_de = p_status then perform privado.invalido('a situação já é esta'); end if;
  update public.grade_envios
     set status = p_status,
         comentario = case when p_status = 'devolvida' then v_motivo else comentario end,
         decidido_em = case when p_status in ('validada', 'devolvida') then now() else decidido_em end
   where oficineiro_id = p_oficineiro and ano_letivo = p_ano;
  perform privado.admin_correcao('grade_envios', p_oficineiro::text, v_motivo,
    jsonb_build_object('ano_letivo', p_ano, 'status', jsonb_build_object('de', v_de, 'para', p_status)));
end;
$$;

create or replace function privado.admin_situacao_registro(p_id bigint, p_status text, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_motivo text;
  v_de text;
  v_novo text := nullif(p_status, '');
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  if v_novo is not null and v_novo not in ('revisado', 'devolvido', 'corrigido', 'anulado') then perform privado.invalido('situação inválida'); end if;
  select revisao_status into v_de from public.aulas_registro where id = p_id for update;
  if not found then perform privado.invalido('registro não encontrado'); end if;
  if v_de is not distinct from v_novo then perform privado.invalido('a situação já é esta'); end if;
  update public.aulas_registro
     set revisao_status = v_novo,
         revisao_obs = case when v_novo in ('devolvido', 'anulado') then v_motivo else revisao_obs end,
         revisado_por = auth.uid(), revisado_em = now()
   where id = p_id;
  perform privado.admin_correcao('aulas_registro', p_id::text, v_motivo,
    jsonb_build_object('revisao_status', jsonb_build_object('de', v_de, 'para', v_novo)));
end;
$$;

create or replace function public.admin_salvar_configuracoes(p_email text, p_telefone text, p_horario text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_salvar_configuracoes(p_email, p_telefone, p_horario) $$;
create or replace function public.admin_salvar_feriado(p_data date, p_nome text, p_tipo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_salvar_feriado(p_data, p_nome, p_tipo) $$;
create or replace function public.admin_remover_feriado(p_data date)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_remover_feriado(p_data) $$;
create or replace function public.admin_consulta(p_usuario uuid, p_competencia date)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.admin_consulta(p_usuario, p_competencia) $$;
create or replace function public.admin_corrigir_presenca(p_id bigint, p_inicio timestamptz, p_fim timestamptz, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_corrigir_presenca(p_id, p_inicio, p_fim, p_motivo) $$;
create or replace function public.admin_lancar_presenca(p_oficineiro uuid, p_inicio timestamptz, p_fim timestamptz, p_motivo text)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.admin_lancar_presenca(p_oficineiro, p_inicio, p_fim, p_motivo) $$;
create or replace function public.admin_situacao_presenca(p_id bigint, p_campo text, p_valor text, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_situacao_presenca(p_id, p_campo, p_valor, p_motivo) $$;
create or replace function public.admin_reabrir_mes(p_oficineiro uuid, p_competencia date, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_reabrir_mes(p_oficineiro, p_competencia, p_motivo) $$;
create or replace function public.admin_situacao_grade(p_oficineiro uuid, p_ano smallint, p_status text, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_situacao_grade(p_oficineiro, p_ano, p_status, p_motivo) $$;
create or replace function public.admin_situacao_registro(p_id bigint, p_status text, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_situacao_registro(p_id, p_status, p_motivo) $$;

revoke all on function
  privado.admin_salvar_configuracoes(text, text, text), privado.admin_salvar_feriado(date, text, text), privado.admin_remover_feriado(date),
  privado.admin_consulta(uuid, date), privado.admin_corrigir_presenca(bigint, timestamptz, timestamptz, text),
  privado.admin_lancar_presenca(uuid, timestamptz, timestamptz, text), privado.admin_situacao_presenca(bigint, text, text, text),
  privado.admin_reabrir_mes(uuid, date, text), privado.admin_situacao_grade(uuid, smallint, text, text),
  privado.admin_situacao_registro(bigint, text, text),
  public.admin_salvar_configuracoes(text, text, text), public.admin_salvar_feriado(date, text, text), public.admin_remover_feriado(date),
  public.admin_consulta(uuid, date), public.admin_corrigir_presenca(bigint, timestamptz, timestamptz, text),
  public.admin_lancar_presenca(uuid, timestamptz, timestamptz, text), public.admin_situacao_presenca(bigint, text, text, text),
  public.admin_reabrir_mes(uuid, date, text), public.admin_situacao_grade(uuid, smallint, text, text),
  public.admin_situacao_registro(bigint, text, text)
  from public, anon;
grant execute on function
  privado.admin_salvar_configuracoes(text, text, text), privado.admin_salvar_feriado(date, text, text), privado.admin_remover_feriado(date),
  privado.admin_consulta(uuid, date), privado.admin_corrigir_presenca(bigint, timestamptz, timestamptz, text),
  privado.admin_lancar_presenca(uuid, timestamptz, timestamptz, text), privado.admin_situacao_presenca(bigint, text, text, text),
  privado.admin_reabrir_mes(uuid, date, text), privado.admin_situacao_grade(uuid, smallint, text, text),
  privado.admin_situacao_registro(bigint, text, text),
  public.admin_salvar_configuracoes(text, text, text), public.admin_salvar_feriado(date, text, text), public.admin_remover_feriado(date),
  public.admin_consulta(uuid, date), public.admin_corrigir_presenca(bigint, timestamptz, timestamptz, text),
  public.admin_lancar_presenca(uuid, timestamptz, timestamptz, text), public.admin_situacao_presenca(bigint, text, text, text),
  public.admin_reabrir_mes(uuid, date, text), public.admin_situacao_grade(uuid, smallint, text, text),
  public.admin_situacao_registro(bigint, text, text)
  to authenticated;
