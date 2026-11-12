alter table public.aulas_registro
  add column if not exists revisao_status text check (revisao_status in ('revisado', 'devolvido', 'corrigido', 'anulado')),
  add column if not exists revisao_obs    text check (length(revisao_obs) <= 500),
  add column if not exists revisado_por   uuid references public.perfis (id),
  add column if not exists revisado_em    timestamptz;

drop policy if exists aulas_alterar on public.aulas_registro;
create policy aulas_alterar on public.aulas_registro for update to authenticated
  using (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and check_direcao is distinct from 'ok'
    and revisao_status is distinct from 'anulado'
    and (privado.mes_editavel(oficineiro_id, data) or revisao_status in ('devolvido', 'corrigido'))
  )
  with check (
    (select privado.acesso_ok())
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and revisao_status is distinct from 'anulado'
    and (privado.mes_editavel(oficineiro_id, data) or revisao_status in ('devolvido', 'corrigido'))
  );

create or replace function privado.registro_editado()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if auth.uid() is not null and auth.uid() = old.oficineiro_id then
    new.revisao_status := case old.revisao_status when 'devolvido' then 'corrigido' when 'revisado' then null else old.revisao_status end;
    new.revisao_obs := old.revisao_obs;
    new.revisado_por := old.revisado_por;
    new.revisado_em := old.revisado_em;
  end if;
  return new;
end;
$$;
revoke all on function privado.registro_editado() from public, anon;

drop trigger if exists registro_editado on public.aulas_registro;
create trigger registro_editado before update on public.aulas_registro
  for each row execute function privado.registro_editado();

create or replace function privado.revisar_aula(p_id bigint, p_acao text, p_comentario text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_a public.aulas_registro;
  v_c text := left(trim(coalesce(p_comentario, '')), 500);
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_a from public.aulas_registro where id = p_id for update;
  if v_a.id is null or not privado.ve_escola(v_a.escola_id) then perform privado.negar(); end if;
  if p_acao is null or p_acao not in ('revisado', 'devolvido', 'anulado', 'aguardando') then perform privado.invalido('ação inválida'); end if;
  if v_a.situacao not in ('Realizada', 'Realizada parcialmente', 'Não realizada') then perform privado.invalido('esta aula ainda não foi registrada'); end if;
  if p_acao in ('devolvido', 'anulado') and length(v_c) < 5 then perform privado.invalido('explique o motivo para o oficineiro'); end if;
  update public.aulas_registro
     set revisao_status = nullif(p_acao, 'aguardando'),
         revisao_obs = nullif(v_c, ''),
         revisado_por = auth.uid(),
         revisado_em = now(),
         check_direcao = case when p_acao = 'devolvido' then null else check_direcao end,
         check_motivo = case when p_acao = 'devolvido' then null else check_motivo end,
         check_por = case when p_acao = 'devolvido' then null else check_por end,
         check_em = case when p_acao = 'devolvido' then null else check_em end
   where id = p_id;
end;
$$;

create or replace function public.revisar_aula(p_id bigint, p_acao text, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.revisar_aula(p_id, p_acao, p_comentario) $$;

revoke all on function privado.revisar_aula(bigint, text, text), public.revisar_aula(bigint, text, text) from public, anon;
grant execute on function privado.revisar_aula(bigint, text, text), public.revisar_aula(bigint, text, text) to authenticated;

create table if not exists public.lembretes_registro (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null references public.perfis (id) on delete cascade,
  escola_id     smallint not null references public.escolas (id),
  grade_aula_id bigint not null references public.grade_aulas (id) on delete cascade,
  data          date not null,
  enviado_por   uuid not null references public.perfis (id),
  enviado_em    timestamptz not null default now(),
  unique (grade_aula_id, data)
);
alter table public.lembretes_registro enable row level security;
revoke all on public.lembretes_registro from anon, authenticated;
grant select on public.lembretes_registro to authenticated;

drop policy if exists lembretes_ler on public.lembretes_registro;
create policy lembretes_ler on public.lembretes_registro for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

drop trigger if exists auditoria on public.lembretes_registro;
create trigger auditoria after insert or update or delete on public.lembretes_registro
  for each row execute function auditoria.trigger_linha();

create or replace function privado.enviar_lembrete(p_grade_aula_id bigint, p_data date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  g public.grade_aulas;
  v_ult timestamptz;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
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

create or replace function public.enviar_lembrete(p_grade_aula_id bigint, p_data date)
returns timestamptz language sql security invoker set search_path = ''
as $$ select privado.enviar_lembrete(p_grade_aula_id, p_data) $$;

create or replace function privado.meus_lembretes()
returns table (id bigint, grade_aula_id bigint, data date, enviado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  return query
    select l.id, l.grade_aula_id, l.data, l.enviado_em
      from public.lembretes_registro l
     where l.oficineiro_id = auth.uid()
       and date_trunc('month', l.data) = date_trunc('month', privado.hoje())
       and not exists (select 1 from public.aulas_registro r where r.grade_aula_id = l.grade_aula_id and r.data = l.data)
     order by l.data;
end;
$$;

create or replace function public.meus_lembretes()
returns table (id bigint, grade_aula_id bigint, data date, enviado_em timestamptz)
language sql security invoker set search_path = ''
as $$ select * from privado.meus_lembretes() $$;

revoke all on function privado.enviar_lembrete(bigint, date), public.enviar_lembrete(bigint, date),
                       privado.meus_lembretes(), public.meus_lembretes() from public, anon;
grant execute on function privado.enviar_lembrete(bigint, date), public.enviar_lembrete(bigint, date),
                          privado.meus_lembretes(), public.meus_lembretes() to authenticated;
