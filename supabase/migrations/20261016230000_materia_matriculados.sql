alter table public.turmas add column if not exists matriculados smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'turmas_matriculados_faixa') then
    alter table public.turmas add constraint turmas_matriculados_faixa check (matriculados is null or matriculados between 0 and 999);
  end if;
end $$;

create or replace function privado.grade_exige_materia()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if auth.uid() is null then return new; end if;
  if new.componente is null and (tg_op = 'INSERT' or old.componente is not null) then
    perform privado.invalido('escolha a matéria da aula');
  end if;
  return new;
end;
$$;
revoke all on function privado.grade_exige_materia() from public, anon;

drop trigger if exists grade_exige_materia on public.grade_aulas;
create trigger grade_exige_materia before insert or update on public.grade_aulas
  for each row execute function privado.grade_exige_materia();

create or replace function privado.registro_matriculados()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_m smallint;
begin
  if new.grade_aula_id is null then return new; end if;
  select t.matriculados into v_m
    from public.grade_aulas g
    join public.turmas t on t.escola_id = g.escola_id and t.ano = g.ano and t.turma = g.turma
   where g.id = new.grade_aula_id;
  if v_m is not null then new.matriculados := v_m; end if;
  return new;
end;
$$;
revoke all on function privado.registro_matriculados() from public, anon, authenticated;

drop trigger if exists registro_matriculados on public.aulas_registro;
create trigger registro_matriculados before insert or update on public.aulas_registro
  for each row execute function privado.registro_matriculados();
