create table if not exists public.visitas_agenda (
  id            bigint generated always as identity primary key,
  analista_id   uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  data          date not null,
  hora          time,
  origem        text not null check (origem in ('relatorio', 'mapa_calor', 'demanda', 'gerencia')),
  tipo          text check (length(tipo) <= 80),
  foco          text check (length(foco) <= 120),
  orientacao    text check (length(orientacao) <= 1000),
  status        text not null default 'agendada' check (status in ('agendada', 'realizada', 'cancelada')),
  criada_por    uuid references public.perfis (id),
  criada_em     timestamptz not null default now(),
  cancelada_por uuid references public.perfis (id),
  cancelada_em  timestamptz,
  visita_id     bigint references public.visitas (id) on delete set null
);
create index if not exists visitas_agenda_analista on public.visitas_agenda (analista_id, data);
create index if not exists visitas_agenda_escola on public.visitas_agenda (escola_id, data);
alter table public.visitas_agenda enable row level security;
revoke all on public.visitas_agenda from anon, authenticated;
grant select on public.visitas_agenda to authenticated;
drop policy if exists visitas_agenda_ler on public.visitas_agenda;
create policy visitas_agenda_ler on public.visitas_agenda for select to authenticated
  using (
    (select privado.acesso_ok())
    and ((select privado.papel_atual()) in ('gerente', 'coordenador')
         or ((select privado.papel_atual()) = 'analista' and analista_id = (select auth.uid())))
  );
drop trigger if exists auditoria on public.visitas_agenda;
create trigger auditoria after insert or update or delete on public.visitas_agenda
  for each row execute function auditoria.trigger_linha();

create or replace function privado.agendar_visita(
  p_analista uuid, p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_a public.perfis; v_e public.escolas; v_id bigint;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('gerente', 'coordenador') then perform privado.negar(); end if;
  select * into v_a from public.perfis where id = p_analista;
  if v_a.id is null or v_a.papel <> 'analista' or not v_a.ativo then perform privado.invalido('escolha um analista ativo'); end if;
  select * into v_e from public.escolas where id = p_escola;
  if v_e.id is null or v_e.ativa is false then perform privado.invalido('escolha uma escola ativa'); end if;
  if v_e.carteira_id is distinct from v_a.carteira_id then
    perform privado.invalido('esta escola não é da carteira deste analista');
  end if;
  if p_data is null or p_data < privado.hoje() or p_data > privado.hoje() + 180 then
    perform privado.invalido('escolha uma data entre hoje e os próximos 6 meses');
  end if;
  if extract(isodow from p_data) > 5 then perform privado.invalido('escolha um dia útil'); end if;
  if coalesce(p_origem, '') not in ('relatorio', 'mapa_calor', 'demanda', 'gerencia') then
    perform privado.invalido('origem da visita inválida');
  end if;
  if exists (select 1 from public.visitas_agenda
              where analista_id = p_analista and escola_id = p_escola and data = p_data and status = 'agendada') then
    perform privado.invalido('este analista já tem visita agendada nesta escola neste dia');
  end if;
  insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, orientacao, criada_por)
  values (p_analista, p_escola, p_data, p_hora, p_origem,
          nullif(left(trim(coalesce(p_tipo, '')), 80), ''),
          nullif(left(trim(coalesce(p_foco, '')), 120), ''),
          nullif(left(trim(coalesce(p_orientacao, '')), 1000), ''),
          auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.cancelar_visita_agenda(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('gerente', 'coordenador') then perform privado.negar(); end if;
  update public.visitas_agenda
     set status = 'cancelada', cancelada_por = auth.uid(), cancelada_em = now()
   where id = p_id and status = 'agendada';
  if not found then perform privado.invalido('visita não encontrada ou já concluída'); end if;
end;
$$;

create or replace function public.agendar_visita(
  p_analista uuid, p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.agendar_visita(p_analista, p_escola, p_data, p_hora, p_origem, p_tipo, p_foco, p_orientacao) $$;

create or replace function public.cancelar_visita_agenda(p_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select privado.cancelar_visita_agenda(p_id) $$;

revoke all on function
  privado.agendar_visita(uuid, smallint, date, time, text, text, text, text), privado.cancelar_visita_agenda(bigint),
  public.agendar_visita(uuid, smallint, date, time, text, text, text, text), public.cancelar_visita_agenda(bigint)
  from public, anon;
grant execute on function
  privado.agendar_visita(uuid, smallint, date, time, text, text, text, text), privado.cancelar_visita_agenda(bigint),
  public.agendar_visita(uuid, smallint, date, time, text, text, text, text), public.cancelar_visita_agenda(bigint)
  to authenticated;
