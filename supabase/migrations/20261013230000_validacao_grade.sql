create table if not exists public.grade_envios (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  ano_letivo    smallint not null check (ano_letivo between 2024 and 2100),
  status        text not null default 'enviada' check (status in ('enviada', 'validada', 'devolvida', 'alterada')),
  enviado_em    timestamptz not null default now(),
  decidido_por  uuid references public.perfis (id),
  decidido_em   timestamptz,
  comentario    text check (length(comentario) <= 500),
  unique (oficineiro_id, ano_letivo)
);
alter table public.grade_envios enable row level security;
revoke all on public.grade_envios from anon, authenticated;
grant select on public.grade_envios to authenticated;

drop policy if exists grade_envios_ler on public.grade_envios;
create policy grade_envios_ler on public.grade_envios for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

drop trigger if exists auditoria on public.grade_envios;
create trigger auditoria after insert or update or delete on public.grade_envios
  for each row execute function auditoria.trigger_linha();

create or replace function privado.enviar_grade(p_ano smallint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_st text;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not exists (select 1 from public.grade_aulas where oficineiro_id = auth.uid() and ano_letivo = p_ano) then
    perform privado.invalido('a grade deste ano ainda não tem aulas');
  end if;
  select status into v_st from public.grade_envios where oficineiro_id = auth.uid() and ano_letivo = p_ano for update;
  if v_st = 'enviada' then perform privado.invalido('a grade já foi enviada e está aguardando o coordenador'); end if;
  if v_st = 'validada' then perform privado.invalido('a grade já foi validada'); end if;
  insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status)
  values (auth.uid(), privado.escola_atual(), p_ano, 'enviada')
  on conflict (oficineiro_id, ano_letivo) do update
     set status = 'enviada', escola_id = excluded.escola_id, enviado_em = now(),
         decidido_por = null, decidido_em = null, comentario = null;
end;
$$;

create or replace function privado.validar_grade(p_oficineiro uuid, p_ano smallint, p_validar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not coalesce(p_validar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique o que o oficineiro precisa ajustar na grade');
  end if;
  update public.grade_envios
     set status = case when p_validar then 'validada' else 'devolvida' end,
         decidido_por = auth.uid(), decidido_em = now(),
         comentario = nullif(left(trim(coalesce(p_comentario, '')), 500), '')
   where oficineiro_id = p_oficineiro and ano_letivo = p_ano and status = 'enviada';
  if not found then perform privado.invalido('não há grade aguardando validação para este oficineiro'); end if;
end;
$$;

create or replace function privado.grade_alterada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare g public.grade_aulas := coalesce(new, old);
begin
  update public.grade_envios
     set status = 'alterada'
   where oficineiro_id = g.oficineiro_id and ano_letivo = g.ano_letivo and status in ('enviada', 'validada');
  return null;
end;
$$;

drop trigger if exists grade_alterada on public.grade_aulas;
create trigger grade_alterada after insert or update or delete on public.grade_aulas
  for each row execute function privado.grade_alterada();

create or replace function public.enviar_grade(p_ano smallint)
returns void language sql security invoker set search_path = ''
as $$ select privado.enviar_grade(p_ano) $$;

create or replace function public.validar_grade(p_oficineiro uuid, p_ano smallint, p_validar boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.validar_grade(p_oficineiro, p_ano, p_validar, p_comentario) $$;

revoke all on function privado.enviar_grade(smallint), privado.validar_grade(uuid, smallint, boolean, text), privado.grade_alterada(),
  public.enviar_grade(smallint), public.validar_grade(uuid, smallint, boolean, text) from public, anon;
grant execute on function privado.enviar_grade(smallint), privado.validar_grade(uuid, smallint, boolean, text),
  public.enviar_grade(smallint), public.validar_grade(uuid, smallint, boolean, text) to authenticated;
