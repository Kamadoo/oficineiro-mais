create table if not exists public.turmas (
  id        integer generated always as identity primary key,
  escola_id smallint not null references public.escolas (id) on delete cascade,
  ano       smallint not null check (ano between 0 and 9),
  turma     text not null default '' check (turma ~ '^[A-Z0-9]{0,4}$'),
  unique (escola_id, ano, turma)
);

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'grade_aulas' and column_name = 'frequencia') then
    drop table public.grade_aulas;
    drop function if exists privado.ocorrencias(date, text, date);
  end if;
end $$;

create table if not exists public.grade_aulas (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null default auth.uid() references public.perfis (id),
  escola_id     smallint not null default privado.escola_atual() references public.escolas (id),
  ano_letivo    smallint not null default extract(year from privado.hoje())::smallint check (ano_letivo between 2024 and 2100),
  dia_semana    smallint not null check (dia_semana between 1 and 5),
  inicio        time not null,
  fim           time not null,
  ano           smallint not null check (ano between 0 and 9),
  turma         text not null check (turma ~ '^[A-Z0-9]{1,4}$'),
  tipo          char(1) not null check (tipo in ('R', 'C', 'P')),
  solucao       text not null check (length(solucao) between 1 and 80),
  professor     text check (length(professor) <= 120),
  espaco        text check (espaco in ('Laboratório', 'Sala da turma', 'Biblioteca', 'Outro')),
  observacao    text check (length(observacao) <= 300),
  criado_em     timestamptz not null default now(),
  check (fim > inicio)
);
create index if not exists grade_aulas_oficineiro_ano on public.grade_aulas (oficineiro_id, ano_letivo, dia_semana);
create index if not exists grade_aulas_escola_ano on public.grade_aulas (escola_id, ano_letivo);

alter table public.turmas enable row level security;
alter table public.grade_aulas enable row level security;

create or replace function privado.grade_sem_conflito()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1
      from public.grade_aulas g
     where g.oficineiro_id = new.oficineiro_id
       and g.id is distinct from new.id
       and g.ano_letivo = new.ano_letivo
       and g.dia_semana = new.dia_semana
       and g.inicio < new.fim and new.inicio < g.fim
  ) then
    raise exception 'já existe uma aula sua neste horário' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function privado.grade_sem_conflito() from public, anon;

drop trigger if exists grade_sem_conflito on public.grade_aulas;
create trigger grade_sem_conflito before insert or update on public.grade_aulas
  for each row execute function privado.grade_sem_conflito();

revoke all on public.turmas, public.grade_aulas from anon, authenticated;
grant select on public.turmas, public.grade_aulas to authenticated;
grant insert (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, professor, espaco, observacao)
  on public.grade_aulas to authenticated;
grant update (dia_semana, inicio, fim, ano, turma, tipo, solucao, professor, espaco, observacao)
  on public.grade_aulas to authenticated;
grant delete on public.grade_aulas to authenticated;

drop policy if exists turmas_ler on public.turmas;
create policy turmas_ler on public.turmas for select to authenticated
  using (privado.ve_escola(escola_id));

drop policy if exists grade_ler on public.grade_aulas;
create policy grade_ler on public.grade_aulas for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

drop policy if exists grade_incluir on public.grade_aulas;
create policy grade_incluir on public.grade_aulas for insert to authenticated
  with check (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and ano_letivo >= extract(year from privado.hoje())
  );

drop policy if exists grade_alterar on public.grade_aulas;
create policy grade_alterar on public.grade_aulas for update to authenticated
  using (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and ano_letivo >= extract(year from privado.hoje())
  )
  with check (
    (select privado.acesso_ok())
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and ano_letivo >= extract(year from privado.hoje())
  );

drop policy if exists grade_excluir on public.grade_aulas;
create policy grade_excluir on public.grade_aulas for delete to authenticated
  using (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and ano_letivo >= extract(year from privado.hoje())
  );

drop trigger if exists auditoria on public.turmas;
create trigger auditoria after insert or update or delete on public.turmas
  for each row execute function auditoria.trigger_linha();
drop trigger if exists auditoria on public.grade_aulas;
create trigger auditoria after insert or update or delete on public.grade_aulas
  for each row execute function auditoria.trigger_linha();
