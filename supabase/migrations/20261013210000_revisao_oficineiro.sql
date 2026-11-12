create or replace function privado.fechar_relatorio(p_competencia date)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if v_comp > date_trunc('month', privado.hoje())::date then perform privado.invalido('não é possível fechar um mês futuro'); end if;
  if v_comp >= date_trunc('month', privado.hoje())::date
     and not exists (select 1 from public.relatorios_mensais r
                      where r.oficineiro_id = auth.uid() and r.competencia = v_comp and r.status = 'devolvido') then
    perform privado.invalido('o mês ainda não terminou: ele fecha sozinho depois do último dia');
  end if;
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status)
  values (auth.uid(), privado.escola_atual(), v_comp, 'fechado')
  on conflict (oficineiro_id, competencia) do update
     set status = 'fechado', fechado_em = now(), motivo_devolucao = null,
         direcao_por = null, direcao_em = null, coordenacao_por = null, coordenacao_em = null
   where public.relatorios_mensais.status = 'devolvido'
  returning id into v_id;
  if v_id is null then perform privado.invalido('este mês já está fechado'); end if;
  return v_id;
end;
$$;

drop policy if exists grade_incluir on public.grade_aulas;
create policy grade_incluir on public.grade_aulas for insert to authenticated
  with check (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and ano_letivo between extract(year from privado.hoje()) and extract(year from privado.hoje()) + 1
  );

create or replace function privado.registro_da_grade()
returns trigger
language plpgsql set search_path = ''
as $$
declare g public.grade_aulas;
begin
  if new.grade_aula_id is null then return new; end if;
  select * into g from public.grade_aulas where id = new.grade_aula_id;
  if g.id is null then return new; end if;
  new.inicio := g.inicio;
  new.fim := g.fim;
  new.tipo := g.tipo;
  new.turma := case when g.ano = 0 then 'Educação infantil' else g.ano || 'º ano' end || ' · Turma ' || g.turma;
  return new;
end;
$$;
revoke all on function privado.registro_da_grade() from public, anon;

drop trigger if exists registro_da_grade on public.aulas_registro;
create trigger registro_da_grade before insert on public.aulas_registro
  for each row execute function privado.registro_da_grade();
