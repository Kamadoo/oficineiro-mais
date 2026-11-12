alter table public.grade_aulas add column if not exists componente text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'grade_aulas_componente_lista') then
    alter table public.grade_aulas add constraint grade_aulas_componente_lista
      check (componente is null or componente in ('Matemática', 'Língua Portuguesa', 'Ciências', 'Geografia', 'História', 'Arte', 'Outro'));
  end if;
end $$;

grant insert (componente) on public.grade_aulas to authenticated;
grant update (componente) on public.grade_aulas to authenticated;

create table if not exists public.grade_semanas (
  id            bigint generated always as identity primary key,
  grade_aula_id bigint not null references public.grade_aulas (id) on delete cascade,
  oficineiro_id uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  ano_letivo    smallint not null,
  semana        date not null check (extract(isodow from semana) = 1),
  tipo          char(1) not null check (tipo in ('R', 'C', 'P')),
  solucao       text not null check (length(solucao) between 1 and 80),
  criado_em     timestamptz not null default now(),
  unique (grade_aula_id, semana)
);
alter table public.grade_semanas add column if not exists componente text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'grade_semanas_componente_lista') then
    alter table public.grade_semanas add constraint grade_semanas_componente_lista
      check (componente is null or componente in ('Matemática', 'Língua Portuguesa', 'Ciências', 'Geografia', 'História', 'Arte', 'Outro'));
  end if;
end $$;

create index if not exists grade_semanas_oficineiro on public.grade_semanas (oficineiro_id, ano_letivo, semana);
create index if not exists grade_semanas_escola on public.grade_semanas (escola_id, ano_letivo);

alter table public.grade_semanas enable row level security;
revoke all on public.grade_semanas from anon, authenticated;
grant select on public.grade_semanas to authenticated;

drop policy if exists grade_semanas_ler on public.grade_semanas;
create policy grade_semanas_ler on public.grade_semanas for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

drop trigger if exists auditoria on public.grade_semanas;
create trigger auditoria after insert or update or delete on public.grade_semanas
  for each row execute function auditoria.trigger_linha();

create or replace function privado.grade_semana_alterada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare g public.grade_semanas := coalesce(new, old);
begin
  update public.grade_envios
     set status = 'alterada'
   where oficineiro_id = g.oficineiro_id and ano_letivo = g.ano_letivo and status in ('enviada', 'validada');
  return null;
end;
$$;
revoke all on function privado.grade_semana_alterada() from public, anon, authenticated;

drop trigger if exists grade_semana_alterada on public.grade_semanas;
create trigger grade_semana_alterada after insert or update or delete on public.grade_semanas
  for each row execute function privado.grade_semana_alterada();

create or replace function privado.semana_editavel(p_semana date)
returns void
language plpgsql stable set search_path = ''
as $$
declare v_seg date := (date_trunc('week', privado.hoje()))::date;
begin
  if p_semana is null or extract(isodow from p_semana) <> 1 then perform privado.invalido('informe a segunda-feira da semana'); end if;
  if p_semana < v_seg then perform privado.invalido('semanas que já passaram não podem ser alteradas'); end if;
  if extract(year from p_semana) > extract(year from privado.hoje()) + 1 then perform privado.invalido('semana fora do ano letivo'); end if;
end;
$$;
revoke all on function privado.semana_editavel(date) from public, anon;
grant execute on function privado.semana_editavel(date) to authenticated;

create or replace function privado.salvar_semana_grade(p_semana date, p_itens jsonb)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ano smallint;
  v_item jsonb;
  g public.grade_aulas;
  v_tipo text;
  v_sol text;
  v_comp text;
  n integer := 0;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  perform privado.semana_editavel(p_semana);
  v_ano := extract(year from p_semana)::smallint;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) > 200 then
    perform privado.invalido('lista de aulas inválida');
  end if;
  delete from public.grade_semanas where oficineiro_id = v_uid and semana = p_semana;
  for v_item in select * from jsonb_array_elements(p_itens) loop
    select * into g from public.grade_aulas
     where id = (v_item ->> 'grade_aula_id')::bigint and oficineiro_id = v_uid and ano_letivo = v_ano;
    if g.id is null then perform privado.invalido('aula não encontrada na sua grade deste ano'); end if;
    v_tipo := v_item ->> 'tipo';
    v_sol := trim(coalesce(v_item ->> 'solucao', ''));
    if v_tipo is null or v_tipo not in ('R', 'C', 'P') then perform privado.invalido('tipo de aula inválido'); end if;
    if length(v_sol) < 1 or length(v_sol) > 80 then perform privado.invalido('informe a solução de cada aula'); end if;
    v_comp := nullif(trim(coalesce(v_item ->> 'componente', '')), '');
    if v_comp is not null and v_comp not in ('Matemática', 'Língua Portuguesa', 'Ciências', 'Geografia', 'História', 'Arte', 'Outro') then
      perform privado.invalido('matéria inválida');
    end if;
    if v_comp is not distinct from g.componente then v_comp := null; end if;
    if v_tipo = g.tipo and v_sol = g.solucao and v_comp is null then continue; end if;
    insert into public.grade_semanas (grade_aula_id, oficineiro_id, escola_id, ano_letivo, semana, tipo, solucao, componente)
    values (g.id, v_uid, g.escola_id, v_ano, p_semana, v_tipo, v_sol, v_comp)
    on conflict (grade_aula_id, semana) do update set tipo = excluded.tipo, solucao = excluded.solucao, componente = excluded.componente;
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function privado.copiar_semana_grade(p_origem date, p_destinos date[])
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  d date;
  n integer := 0;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_origem is null or extract(isodow from p_origem) <> 1 then perform privado.invalido('informe a segunda-feira da semana de origem'); end if;
  if p_destinos is null or cardinality(p_destinos) = 0 or cardinality(p_destinos) > 60 then perform privado.invalido('escolha de 1 a 60 semanas'); end if;
  foreach d in array p_destinos loop
    perform privado.semana_editavel(d);
    if d = p_origem then continue; end if;
    if extract(year from d) <> extract(year from p_origem) then perform privado.invalido('as semanas precisam ser do mesmo ano letivo'); end if;
    delete from public.grade_semanas where oficineiro_id = v_uid and semana = d;
    insert into public.grade_semanas (grade_aula_id, oficineiro_id, escola_id, ano_letivo, semana, tipo, solucao, componente)
    select s.grade_aula_id, s.oficineiro_id, s.escola_id, s.ano_letivo, d, s.tipo, s.solucao, s.componente
      from public.grade_semanas s
     where s.oficineiro_id = v_uid and s.semana = p_origem;
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.salvar_semana_grade(p_semana date, p_itens jsonb)
returns integer language sql security invoker set search_path = ''
as $$ select privado.salvar_semana_grade(p_semana, p_itens) $$;

create or replace function public.copiar_semana_grade(p_origem date, p_destinos date[])
returns integer language sql security invoker set search_path = ''
as $$ select privado.copiar_semana_grade(p_origem, p_destinos) $$;

revoke all on function privado.salvar_semana_grade(date, jsonb), privado.copiar_semana_grade(date, date[]),
  public.salvar_semana_grade(date, jsonb), public.copiar_semana_grade(date, date[]) from public, anon;
grant execute on function privado.salvar_semana_grade(date, jsonb), privado.copiar_semana_grade(date, date[]),
  public.salvar_semana_grade(date, jsonb), public.copiar_semana_grade(date, date[]) to authenticated;

create or replace function privado.registro_da_grade()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  g public.grade_aulas;
  v_tipo char(1);
begin
  if new.grade_aula_id is null then return new; end if;
  select * into g from public.grade_aulas where id = new.grade_aula_id;
  if g.id is null then return new; end if;
  select s.tipo into v_tipo from public.grade_semanas s
   where s.grade_aula_id = g.id and s.semana = (date_trunc('week', new.data))::date;
  new.inicio := g.inicio;
  new.fim := g.fim;
  new.tipo := coalesce(v_tipo, g.tipo);
  new.turma := case when g.ano = 0 then 'Educação infantil' else g.ano || 'º ano' end || ' · Turma ' || g.turma;
  return new;
end;
$$;
revoke all on function privado.registro_da_grade() from public, anon;
