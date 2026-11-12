create table if not exists public.check_historico (
  id            bigint generated always as identity primary key,
  aula_id       bigint not null references public.aulas_registro (id) on delete cascade,
  oficineiro_id uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  evento        text not null check (evento in ('confirmada', 'contestada', 'corrigida')),
  texto         text check (length(texto) <= 600),
  por           uuid references public.perfis (id),
  em            timestamptz not null default now()
);
create index if not exists check_historico_aula on public.check_historico (aula_id, em);
create index if not exists check_historico_escola on public.check_historico (escola_id, em);
alter table public.check_historico enable row level security;
revoke all on public.check_historico from anon, authenticated;
grant select on public.check_historico to authenticated;
drop policy if exists check_historico_ler on public.check_historico;
create policy check_historico_ler on public.check_historico for select to authenticated
  using (
    (select privado.acesso_ok())
    and privado.ve_escola(escola_id)
    and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid()))
  );

insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento, texto, por, em)
select a.id, a.oficineiro_id, a.escola_id,
       case when a.check_direcao = 'ok' then 'confirmada' else 'contestada' end,
       case when a.check_direcao = 'ok' then null else a.check_motivo end,
       a.check_por, a.check_em
  from public.aulas_registro a
 where a.check_direcao is not null
   and a.check_em is not null
   and not exists (select 1 from public.check_historico h where h.aula_id = a.id);

create or replace function privado.conferir_aula(p_id bigint, p_confirmar boolean, p_motivo text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.aulas_registro;
begin
  if privado.papel_atual() is distinct from 'direcao' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_a from public.aulas_registro where id = p_id for update;
  if v_a.id is null or v_a.escola_id is distinct from privado.escola_atual() then perform privado.negar(); end if;
  if v_a.situacao not in ('Realizada', 'Realizada parcialmente', 'Não realizada') then
    perform privado.invalido('a aula ainda não foi registrada pelo oficineiro');
  end if;
  if v_a.revisao_status = 'anulado' then perform privado.invalido('este registro foi anulado pela coordenação'); end if;
  if not coalesce(p_confirmar, false) and length(trim(coalesce(p_motivo, ''))) < 5 then
    perform privado.invalido('informe o motivo da contestação');
  end if;
  update public.aulas_registro
     set check_direcao = case when p_confirmar then 'ok' else 'contestada' end,
         check_motivo = case when p_confirmar then null else left(trim(p_motivo), 500) end,
         check_por = auth.uid(), check_em = now()
   where id = p_id;
  insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento, texto, por)
  values (v_a.id, v_a.oficineiro_id, v_a.escola_id,
          case when p_confirmar then 'confirmada' else 'contestada' end,
          case when p_confirmar then null else left(trim(p_motivo), 500) end,
          auth.uid());
end;
$$;

create or replace function privado.conferir_aulas(p_ids bigint[])
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  if privado.papel_atual() is distinct from 'direcao' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_ids is null or cardinality(p_ids) = 0 then perform privado.invalido('nenhuma aula escolhida'); end if;
  if cardinality(p_ids) > 500 then perform privado.invalido('confirme no máximo 500 aulas de uma vez'); end if;
  with feitas as (
    update public.aulas_registro
       set check_direcao = 'ok', check_motivo = null, check_por = auth.uid(), check_em = now()
     where id = any (p_ids)
       and escola_id = privado.escola_atual()
       and situacao in ('Realizada', 'Realizada parcialmente', 'Não realizada')
       and revisao_status is distinct from 'anulado'
       and (check_direcao is null or check_direcao = 'corrigida')
    returning id, oficineiro_id, escola_id
  )
  insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento, por)
  select id, oficineiro_id, escola_id, 'confirmada', auth.uid() from feitas;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function privado.check_corrigido()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_mud text[] := '{}';
begin
  if old.check_direcao is distinct from 'contestada' or new.check_direcao is distinct from 'corrigida' then
    return new;
  end if;
  if new.situacao is distinct from old.situacao then
    v_mud := v_mud || ('Situação: ' || coalesce(old.situacao, '—') || ' → ' || coalesce(new.situacao, '—'));
  end if;
  if new.inicio is distinct from old.inicio or new.fim is distinct from old.fim then
    v_mud := v_mud || ('Horário: ' || to_char(old.inicio, 'HH24:MI') || '–' || to_char(old.fim, 'HH24:MI')
                       || ' → ' || to_char(new.inicio, 'HH24:MI') || '–' || to_char(new.fim, 'HH24:MI'));
  end if;
  if new.turma is distinct from old.turma then
    v_mud := v_mud || ('Turma: ' || coalesce(old.turma, '—') || ' → ' || coalesce(new.turma, '—'));
  end if;
  if new.presentes is distinct from old.presentes or new.matriculados is distinct from old.matriculados then
    v_mud := v_mud || ('Presentes: ' || coalesce(old.presentes::text, '—') || '/' || coalesce(old.matriculados::text, '—')
                       || ' → ' || coalesce(new.presentes::text, '—') || '/' || coalesce(new.matriculados::text, '—'));
  end if;
  if new.motivo is distinct from old.motivo then
    v_mud := v_mud || ('Motivo: ' || coalesce(new.motivo, '—'));
  end if;
  if new.conteudo is distinct from old.conteudo or new.atividade is distinct from old.atividade
     or new.objetivo is distinct from old.objetivo or new.engajamento is distinct from old.engajamento then
    v_mud := v_mud || 'Descrição da atividade ajustada'::text;
  end if;
  insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento, texto, por)
  values (new.id, new.oficineiro_id, new.escola_id, 'corrigida',
          left(coalesce(nullif(array_to_string(v_mud, ' · '), ''), 'Registro revisado sem mudança nos dados principais'), 600),
          auth.uid());
  return new;
end;
$$;
revoke all on function privado.check_corrigido() from public, anon, authenticated;

drop trigger if exists check_corrigido on public.aulas_registro;
create trigger check_corrigido after update on public.aulas_registro
  for each row execute function privado.check_corrigido();
