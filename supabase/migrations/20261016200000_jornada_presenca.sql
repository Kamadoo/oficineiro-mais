alter table public.perfis add column if not exists jornada_inicio time;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'perfis_jornada_opcoes') then
    alter table public.perfis add constraint perfis_jornada_opcoes check (jornada_inicio is null or jornada_inicio in ('07:00', '08:00'));
  end if;
end $$;

grant select (jornada_inicio) on public.perfis to authenticated;

alter table public.presencas
  add column if not exists trabalhado_min        integer check (trabalhado_min >= 0),
  add column if not exists previsto_min          integer check (previsto_min >= 0),
  add column if not exists compensacao_min       integer not null default 0 check (compensacao_min >= 0),
  add column if not exists deficit_min           integer not null default 0 check (deficit_min >= 0),
  add column if not exists deficit_status        text not null default 'dentro' check (deficit_status in ('dentro', 'pendente', 'aguardando', 'autorizado', 'nao')),
  add column if not exists motivo_deficit        text check (length(motivo_deficit) <= 120),
  add column if not exists justificativa_deficit text check (length(justificativa_deficit) <= 1000),
  add column if not exists compensar_em          date,
  add column if not exists deficit_obs           text check (length(deficit_obs) <= 500),
  add column if not exists deficit_decidido_por  uuid references public.perfis (id),
  add column if not exists deficit_decidido_em   timestamptz,
  add column if not exists atraso_min            integer,
  add column if not exists horario_status        text not null default 'dentro' check (horario_status in ('dentro', 'pendente', 'aguardando', 'conferido', 'nao')),
  add column if not exists motivo_horario        text check (length(motivo_horario) <= 120),
  add column if not exists justificativa_horario text check (length(justificativa_horario) <= 1000),
  add column if not exists horario_obs           text check (length(horario_obs) <= 500),
  add column if not exists horario_decidido_por  uuid references public.perfis (id),
  add column if not exists horario_decidido_em   timestamptz;

create table if not exists public.presenca_reaberturas (
  id               bigint generated always as identity primary key,
  presenca_id      bigint not null references public.presencas (id) on delete cascade,
  oficineiro_id    uuid not null references public.perfis (id),
  escola_id        smallint not null references public.escolas (id),
  data             date not null,
  inicio           timestamptz not null,
  fim_anterior     timestamptz not null,
  trabalhado_min   integer,
  reaberto_em      timestamptz not null default now()
);
create index if not exists presenca_reaberturas_escola on public.presenca_reaberturas (escola_id, data);
alter table public.presenca_reaberturas enable row level security;
revoke all on public.presenca_reaberturas from anon, authenticated;
grant select on public.presenca_reaberturas to authenticated;
drop policy if exists reaberturas_ler on public.presenca_reaberturas;
create policy reaberturas_ler on public.presenca_reaberturas for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));
drop trigger if exists auditoria on public.presenca_reaberturas;
create trigger auditoria after insert or update or delete on public.presenca_reaberturas
  for each row execute function auditoria.trigger_linha();

create or replace function privado.feriado(p_data date)
returns boolean
language sql immutable set search_path = ''
as $$
  select to_char(p_data, 'MM-DD') in ('01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '11-20', '12-25')
      or p_data in ('2026-02-16', '2026-02-17', '2026-04-03', '2026-06-04', '2027-02-08', '2027-02-09', '2027-03-26', '2027-05-27');
$$;
revoke all on function privado.feriado(date) from public, anon;
grant execute on function privado.feriado(date) to authenticated;

create or replace function privado.minutos_previstos(p_data date)
returns integer
language sql immutable set search_path = ''
as $$ select case when extract(isodow from p_data) between 1 and 5 and not privado.feriado(p_data) then 480 else 0 end $$;
revoke all on function privado.minutos_previstos(date) from public, anon;
grant execute on function privado.minutos_previstos(date) to authenticated;

create or replace function privado.minutos_trabalhados(p_inicio timestamptz, p_fim timestamptz)
returns integer
language sql immutable set search_path = ''
as $$
  select case when b > 360 then b - 60 else b end
    from (select greatest(0, floor(extract(epoch from (p_fim - p_inicio)) / 60))::int as b) x
$$;
revoke all on function privado.minutos_trabalhados(timestamptz, timestamptz) from public, anon;
grant execute on function privado.minutos_trabalhados(timestamptz, timestamptz) to authenticated;

create or replace function privado.calcular_dia(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_trab integer;
  v_prev integer;
  v_dif integer;
  v_disp integer;
  v_comp integer := 0;
  v_exc integer := 0;
  v_def integer := 0;
begin
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null or v_p.fim is null then return; end if;
  v_trab := privado.minutos_trabalhados(v_p.inicio, v_p.fim);
  v_prev := privado.minutos_previstos(v_p.data);
  v_dif := v_trab - v_prev;
  if v_dif > 15 then
    select coalesce(sum(d.deficit_min), 0) into v_disp
      from public.presencas d
     where d.oficineiro_id = v_p.oficineiro_id and d.compensar_em = v_p.data and d.id <> v_p.id
       and d.deficit_status in ('aguardando', 'autorizado');
    v_comp := least(v_dif, v_disp);
    v_exc := v_dif - v_comp;
    if v_exc <= 15 then v_exc := 0; end if;
  elsif v_dif < -15 then
    v_def := -v_dif;
  end if;
  update public.presencas
     set trabalhado_min = v_trab,
         previsto_min = v_prev,
         compensacao_min = v_comp,
         excedente_min = v_exc,
         excedente_status = case when v_exc = 0 then 'dentro'
                                 when excedente_status in ('aguardando', 'autorizado', 'nao') and excedente_min = v_exc then excedente_status
                                 else 'pendente' end,
         deficit_min = v_def,
         deficit_status = case when v_def = 0 then 'dentro'
                               when deficit_status in ('aguardando', 'autorizado', 'nao') and deficit_min = v_def then deficit_status
                               else 'pendente' end
   where id = v_p.id;
end;
$$;
revoke all on function privado.calcular_dia(bigint) from public, anon, authenticated;

create or replace function privado.situacao_horario(p_atraso integer)
returns text
language sql immutable set search_path = ''
as $$ select case when coalesce(p_atraso, 0) > 15 then 'pendente' else 'dentro' end $$;
revoke all on function privado.situacao_horario(integer) from public, anon, authenticated;

create or replace function privado.registrar_presenca(
  p_evento     text,
  p_lat        double precision,
  p_lng        double precision,
  p_quando     timestamptz default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esc public.escolas;
  v_quando timestamptz := now();
  v_conf text;
  v_dist integer;
  v_data date;
  v_p public.presencas;
  v_entrou boolean;
  v_jor time;
  v_atraso integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim') then perform privado.invalido('evento deve ser inicio ou fim'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_quando is not null then
    if p_quando > now() + interval '2 minutes' or p_quando < now() - interval '24 hours' then
      perform privado.invalido('horário guardado sem internet fora do limite de 24 horas');
    end if;
    v_quando := p_quando;
    v_conf := 'Enviado sem internet';
  end if;

  select * into v_esc from public.escolas where id = privado.escola_atual();
  if p_lat is null then
    v_conf := coalesce(v_conf, 'Sem localização');
  elsif v_esc.latitude is null or v_esc.longitude is null then
    v_conf := coalesce(v_conf, 'Escola sem localização');
  else
    v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
    if v_dist > v_esc.raio_m then v_conf := coalesce(v_conf, 'Fora do raio'); end if;
  end if;
  v_data := (v_quando at time zone 'America/Sao_Paulo')::date;

  if p_evento = 'inicio' then
    select jornada_inicio into v_jor from public.perfis where id = v_uid;
    if v_jor is not null and privado.minutos_previstos(v_data) > 0 then
      v_atraso := (extract(epoch from ((v_quando at time zone 'America/Sao_Paulo')::time - v_jor)) / 60)::int;
    end if;
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, conferencia, atraso_min, horario_status)
    values (v_uid, v_esc.id, v_data, v_quando, v_dist, v_conf, v_atraso, privado.situacao_horario(v_atraso))
    on conflict (oficineiro_id, data) do nothing
    returning * into v_p;
    if v_p.id is null then perform privado.invalido('a presença deste dia já foi iniciada'); end if;
  else
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para encerrar'); end if;
    if v_quando <= v_p.inicio then perform privado.invalido('encerramento antes do início'); end if;
    v_entrou := v_p.entrou_raio_em is null and v_dist is not null and v_dist <= v_esc.raio_m
                and v_p.distancia_inicio_m is not null and v_p.distancia_inicio_m > v_esc.raio_m;
    update public.presencas
       set fim = v_quando,
           distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           entrou_raio_em = case when v_entrou then v_quando else entrou_raio_em end,
           distancia_entrada_m = case when v_entrou then v_dist else distancia_entrada_m end
     where id = v_p.id;
    perform privado.calcular_dia(v_p.id);
    select * into v_p from public.presencas where id = v_p.id;
  end if;

  return jsonb_build_object('id', v_p.id, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status,
                            'entrou_raio_em', v_p.entrou_raio_em, 'atraso_min', v_p.atraso_min, 'horario_status', v_p.horario_status,
                            'trabalhado_min', v_p.trabalhado_min, 'deficit_min', v_p.deficit_min, 'deficit_status', v_p.deficit_status,
                            'compensacao_min', v_p.compensacao_min);
end;
$$;
revoke all on function privado.registrar_presenca(text, double precision, double precision, timestamptz) from public, anon;
grant execute on function privado.registrar_presenca(text, double precision, double precision, timestamptz) to authenticated;

create or replace function privado.justificar_horario(p_id bigint, p_motivo text, p_justificativa text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if v_p.horario_status not in ('pendente', 'aguardando') then perform privado.invalido('o início desta presença não precisa de justificativa'); end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('justificativa precisa de pelo menos 10 caracteres'); end if;
  update public.presencas
     set motivo_horario = left(trim(coalesce(p_motivo, '')), 120),
         justificativa_horario = left(trim(p_justificativa), 1000),
         horario_status = 'aguardando'
   where id = p_id;
end;
$$;

create or replace function privado.justificar_deficit(p_id bigint, p_motivo text, p_justificativa text, p_compensar_em date default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_c bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if v_p.deficit_status not in ('pendente', 'aguardando') then perform privado.invalido('não há horas abaixo de 8h para justificar neste dia'); end if;
  if length(trim(coalesce(p_motivo, ''))) = 0 then perform privado.invalido('escolha o motivo'); end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('justificativa precisa de pelo menos 10 caracteres'); end if;
  if p_compensar_em is not null and (p_compensar_em <= v_p.data or p_compensar_em < privado.hoje() or p_compensar_em > v_p.data + 31) then
    perform privado.invalido('a compensação precisa ser em uma data depois deste dia, de hoje em diante e em até 31 dias');
  end if;
  update public.presencas
     set motivo_deficit = left(trim(p_motivo), 120),
         justificativa_deficit = left(trim(p_justificativa), 1000),
         compensar_em = p_compensar_em,
         deficit_status = 'aguardando'
   where id = p_id;
  if p_compensar_em is not null then
    select id into v_c from public.presencas
     where oficineiro_id = v_p.oficineiro_id and data = p_compensar_em and fim is not null and excedente_status in ('dentro', 'pendente');
    if v_c is not null then perform privado.calcular_dia(v_c); end if;
  end if;
end;
$$;

create or replace function privado.decidir_deficit(p_id bigint, p_aceitar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not coalesce(p_aceitar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a justificativa não foi aceita');
  end if;
  update public.presencas
     set deficit_status = case when p_aceitar then 'autorizado' else 'nao' end,
         deficit_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         deficit_decidido_por = auth.uid(), deficit_decidido_em = now()
   where id = p_id and deficit_status = 'aguardando';
  if not found then perform privado.invalido('não há horas abaixo de 8h aguardando decisão neste registro'); end if;
end;
$$;

create or replace function privado.decidir_horario(p_id bigint, p_conferir boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not coalesce(p_conferir, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que o horário não foi conferido');
  end if;
  update public.presencas
     set horario_status = case when p_conferir then 'conferido' else 'nao' end,
         horario_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         horario_decidido_por = auth.uid(), horario_decidido_em = now()
   where id = p_id and horario_status = 'aguardando';
  if not found then perform privado.invalido('não há horário de início aguardando conferência neste registro'); end if;
end;
$$;

create or replace function privado.reabrir_presenca(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_n integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if v_p.fim is null then perform privado.invalido('esta presença ainda não foi encerrada'); end if;
  if v_p.data <> privado.hoje() then perform privado.invalido('só é possível desfazer o encerramento no mesmo dia'); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if coalesce(v_p.trabalhado_min, privado.minutos_trabalhados(v_p.inicio, v_p.fim)) >= 480 then
    perform privado.invalido('o dia já tem 8 horas ou mais: o encerramento não pode ser desfeito');
  end if;
  select count(*) into v_n from public.presenca_reaberturas where presenca_id = v_p.id;
  if v_n >= 2 then perform privado.invalido('o encerramento deste dia já foi desfeito 2 vezes'); end if;
  insert into public.presenca_reaberturas (presenca_id, oficineiro_id, escola_id, data, inicio, fim_anterior, trabalhado_min)
  values (v_p.id, v_p.oficineiro_id, v_p.escola_id, v_p.data, v_p.inicio, v_p.fim, coalesce(v_p.trabalhado_min, privado.minutos_trabalhados(v_p.inicio, v_p.fim)));
  update public.presencas
     set fim = null, distancia_fim_m = null, trabalhado_min = null, previsto_min = null,
         compensacao_min = 0, excedente_min = 0, excedente_status = 'dentro',
         deficit_min = 0, deficit_status = 'dentro', motivo_deficit = null, justificativa_deficit = null, compensar_em = null
   where id = v_p.id;
end;
$$;

create or replace function privado.definir_jornada(p_usuario uuid, p_inicio time)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  if p_inicio is null or p_inicio not in ('07:00', '08:00') then perform privado.invalido('escolha o horário de trabalho'); end if;
  update public.perfis set jornada_inicio = p_inicio where id = p_usuario and papel = 'oficineiro';
  if not found then perform privado.invalido('o horário de trabalho só vale para contas de oficineiro'); end if;
end;
$$;

create or replace function public.justificar_horario(p_id bigint, p_motivo text, p_justificativa text)
returns void language sql security invoker set search_path = ''
as $$ select privado.justificar_horario(p_id, p_motivo, p_justificativa) $$;
create or replace function public.justificar_deficit(p_id bigint, p_motivo text, p_justificativa text, p_compensar_em date default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.justificar_deficit(p_id, p_motivo, p_justificativa, p_compensar_em) $$;
create or replace function public.decidir_deficit(p_id bigint, p_aceitar boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_deficit(p_id, p_aceitar, p_comentario) $$;
create or replace function public.decidir_horario(p_id bigint, p_conferir boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_horario(p_id, p_conferir, p_comentario) $$;
create or replace function public.reabrir_presenca(p_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select privado.reabrir_presenca(p_id) $$;
create or replace function public.definir_jornada(p_usuario uuid, p_inicio time)
returns void language sql security invoker set search_path = ''
as $$ select privado.definir_jornada(p_usuario, p_inicio) $$;

revoke all on function
  privado.justificar_horario(bigint, text, text), privado.justificar_deficit(bigint, text, text, date), privado.decidir_deficit(bigint, boolean, text),
  privado.decidir_horario(bigint, boolean, text), privado.reabrir_presenca(bigint), privado.definir_jornada(uuid, time),
  public.justificar_horario(bigint, text, text), public.justificar_deficit(bigint, text, text, date), public.decidir_deficit(bigint, boolean, text),
  public.decidir_horario(bigint, boolean, text), public.reabrir_presenca(bigint), public.definir_jornada(uuid, time)
  from public, anon;
grant execute on function
  privado.justificar_horario(bigint, text, text), privado.justificar_deficit(bigint, text, text, date), privado.decidir_deficit(bigint, boolean, text),
  privado.decidir_horario(bigint, boolean, text), privado.reabrir_presenca(bigint), privado.definir_jornada(uuid, time),
  public.justificar_horario(bigint, text, text), public.justificar_deficit(bigint, text, text, date), public.decidir_deficit(bigint, boolean, text),
  public.decidir_horario(bigint, boolean, text), public.reabrir_presenca(bigint), public.definir_jornada(uuid, time)
  to authenticated;

create or replace function privado.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'nome', case when privado.mfa_ok() then p.nome end,
    'usuario', case when privado.mfa_ok() then p.usuario end,
    'escola_id', case when privado.mfa_ok() then p.escola_id end,
    'carteira_id', case when privado.mfa_ok() then p.carteira_id end,
    'jornada_inicio', case when privado.mfa_ok() then to_char(p.jornada_inicio, 'HH24:MI') end,
    'precisa_mfa', not privado.mfa_ok(),
    'precisa_criar_usuario', p.usuario is null,
    'precisa_trocar_senha', p.trocar_senha,
    'acesso_ok', privado.acesso_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;

drop function if exists public.contas_gestao();
drop function if exists privado.contas_gestao();
create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text)
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  perform privado.aplicar_mudancas_escola();
  return query
    select p.id, p.nome, p.usuario, p.papel::text, p.escola_id, p.carteira_id, p.ativo,
           (p.usuario is null or p.trocar_senha), p.criado_em, x.acesso_atual, p.telefone,
           m.escola_nova, m.vale_a_partir, m.motivo, p.id = auth.uid(), to_char(p.jornada_inicio, 'HH24:MI')
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     order by p.nome;
end;
$$;
create or replace function public.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text)
language sql security invoker set search_path = ''
as $$ select * from privado.contas_gestao() $$;
revoke all on function privado.contas_gestao(), public.contas_gestao() from public, anon;
grant execute on function privado.contas_gestao(), public.contas_gestao() to authenticated;

update public.presencas
   set trabalhado_min = privado.minutos_trabalhados(inicio, fim),
       previsto_min = privado.minutos_previstos(data)
 where fim is not null and trabalhado_min is null;
