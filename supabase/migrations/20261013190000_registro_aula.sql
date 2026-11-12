alter table public.aulas_registro
  add column if not exists grade_aula_id  bigint references public.grade_aulas (id) on delete set null,
  add column if not exists professor_aula text check (length(professor_aula) <= 120),
  add column if not exists mudanca        text check (length(mudanca) <= 300),
  add column if not exists componente     text check (length(componente) <= 40),
  add column if not exists atividade      text check (length(atividade) <= 200),
  add column if not exists objetivo       text check (objetivo in ('Sim', 'Parcialmente', 'Não')),
  add column if not exists engajamento    smallint check (engajamento between 1 and 5),
  add column if not exists proxima_aula   text check (length(proxima_aula) <= 300);

alter table public.aulas_registro
  alter column oficineiro_id set default auth.uid(),
  alter column escola_id set default privado.escola_atual();

grant insert (grade_aula_id, professor_aula, mudanca, componente, atividade, objetivo, engajamento, proxima_aula)
  on public.aulas_registro to authenticated;
grant update (professor_aula, mudanca, componente, atividade, objetivo, engajamento, proxima_aula)
  on public.aulas_registro to authenticated;

drop policy if exists aulas_incluir on public.aulas_registro;
create policy aulas_incluir on public.aulas_registro for insert to authenticated
  with check (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and privado.mes_editavel(oficineiro_id, data)
    and (grade_aula_id is null
         or exists (select 1 from public.grade_aulas g
                     where g.id = grade_aula_id
                       and g.oficineiro_id = (select auth.uid())
                       and g.dia_semana = extract(isodow from data)))
  );
