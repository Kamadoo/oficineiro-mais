create or replace function privado.ano_rotulo(p_ano smallint)
returns text
language sql immutable set search_path = ''
as $$
  select case p_ano when -2 then '1º período' when -1 then '2º período' else p_ano || 'º ano' end;
$$;
revoke all on function privado.ano_rotulo(smallint) from public, anon;
grant execute on function privado.ano_rotulo(smallint) to authenticated;

create or replace function privado.oficinas()
returns text[]
language sql immutable set search_path = ''
as $$
  select array['Tempo de Estudo', 'Programa Construtores – Minecraft', 'Artesanato', 'Basquete', 'Colagem', 'Coral', 'Dança',
               'Direitos humanos', 'Empreendedorismo', 'Fanfarra', 'Fotografia', 'Futsal', 'Handebol', 'Hóquei',
               'Horta e Meio Ambiente', 'Jiu-Jitsu', 'Jogos Matemáticos', 'Jornal', 'Judô', 'Música/Flauta', 'Projeto de Vida',
               'Robótica', 'Rugby', 'Skate', 'Sorvebol', 'Teatro', 'Tempo de Aula – Reforço Escolar', 'Xadrez'];
$$;

create or replace function privado.oficina_categoria(p_oficina text)
returns text
language sql immutable set search_path = ''
as $$
  select case when p_oficina is null then null
              when p_oficina in ('Programa Construtores – Minecraft', 'Robótica') then 'Tecnologia'
              else 'Outras' end;
$$;

create or replace function privado.componentes()
returns text[]
language sql immutable set search_path = ''
as $$
  select array['Língua Portuguesa', 'Matemática', 'Ciências', 'História', 'Geografia', 'Arte', 'Educação Física',
               'Língua Inglesa', 'Projetos e oficinas'];
$$;
revoke all on function privado.oficinas(), privado.oficina_categoria(text), privado.componentes() from public, anon;
grant execute on function privado.oficinas(), privado.oficina_categoria(text), privado.componentes() to authenticated;

alter table public.grade_aulas add column if not exists oficina text;
alter table public.grade_aulas add column if not exists horario smallint;
alter table public.grade_semanas add column if not exists oficina text;
alter table public.aulas_registro add column if not exists oficina text;
alter table public.aulas_registro add column if not exists horario smallint;

alter table public.grade_aulas drop constraint if exists grade_aulas_tipo_check;
alter table public.grade_aulas drop constraint if exists grade_aulas_ano_check;
alter table public.grade_aulas drop constraint if exists grade_aulas_componente_lista;
alter table public.grade_aulas drop constraint if exists grade_aulas_oficina_check;
alter table public.grade_aulas drop constraint if exists grade_aulas_horario_check;
alter table public.grade_aulas alter column ano drop not null;
alter table public.grade_aulas alter column turma drop not null;
alter table public.grade_aulas alter column solucao drop not null;
alter table public.grade_semanas drop constraint if exists grade_semanas_tipo_check;
alter table public.grade_semanas drop constraint if exists grade_semanas_componente_lista;
alter table public.grade_semanas drop constraint if exists grade_semanas_oficina_check;
alter table public.grade_semanas alter column solucao drop not null;
alter table public.aulas_registro drop constraint if exists aulas_registro_tipo_check;
alter table public.aulas_registro drop constraint if exists aulas_registro_objetivo_check;
alter table public.aulas_registro drop constraint if exists aulas_registro_oficina_check;
alter table public.aulas_registro drop constraint if exists aulas_registro_horario_check;
alter table public.turmas drop constraint if exists turmas_ano_check;

alter table public.grade_aulas disable trigger grade_alterada;
alter table public.grade_aulas disable trigger grade_exige_materia;
alter table public.grade_semanas disable trigger grade_semana_alterada;

update public.grade_aulas
   set tipo = 'P',
       oficina = case when solucao ilike 'Programa Construtores%' then 'Programa Construtores – Minecraft'
                      else left(coalesce(nullif(trim(solucao), ''), 'Outro'), 60) end,
       componente = null,
       solucao = null,
       professor = null
 where tipo in ('C', 'P') and oficina is null;
update public.grade_aulas set componente = 'Projetos e oficinas' where componente = 'Outro';
update public.grade_aulas set componente = null where componente is not null and not (componente = any (privado.componentes()));
update public.grade_aulas set ano = -2 where ano = 0;
update public.grade_aulas
   set horario = greatest(1, least(12, ((extract(epoch from inicio)::integer / 60 - 420) / 50) + 1))
 where horario is null;

update public.grade_semanas
   set tipo = 'P',
       oficina = case when solucao ilike 'Programa Construtores%' then 'Programa Construtores – Minecraft'
                      else left(coalesce(nullif(trim(solucao), ''), 'Outro'), 60) end,
       componente = null,
       solucao = null
 where tipo in ('C', 'P') and oficina is null;
update public.grade_semanas set componente = 'Projetos e oficinas' where componente = 'Outro';
update public.grade_semanas set componente = null where componente is not null and not (componente = any (privado.componentes()));

alter table public.grade_aulas enable trigger grade_alterada;
alter table public.grade_aulas enable trigger grade_exige_materia;
alter table public.grade_semanas enable trigger grade_semana_alterada;

update public.turmas set ano = -2 where ano = 0 and not exists (
  select 1 from public.turmas t where t.escola_id = turmas.escola_id and t.ano = -2 and t.turma = turmas.turma);

alter table public.aulas_registro disable trigger registro_editado;
alter table public.aulas_registro disable trigger check_corrigido;
update public.aulas_registro r
   set tipo = 'P',
       oficina = coalesce(g.oficina, case when r.solucao ilike 'Programa Construtores%' then 'Programa Construtores – Minecraft'
                                          else left(coalesce(nullif(trim(r.solucao), ''), 'Outro'), 60) end),
       componente = null
  from (select id, oficina from public.grade_aulas) g
 where r.tipo in ('C', 'P') and r.oficina is null and g.id = r.grade_aula_id;
update public.aulas_registro
   set tipo = 'P',
       oficina = case when solucao ilike 'Programa Construtores%' then 'Programa Construtores – Minecraft'
                      else left(coalesce(nullif(trim(solucao), ''), 'Outro'), 60) end,
       componente = null
 where tipo in ('C', 'P') and oficina is null;
update public.aulas_registro set componente = 'Projetos e oficinas' where componente = 'Outro';
update public.aulas_registro set objetivo = 'Sim' where objetivo = 'Parcialmente';
update public.aulas_registro r set horario = g.horario
  from public.grade_aulas g where g.id = r.grade_aula_id and r.horario is null;
update public.aulas_registro r
   set turma = privado.ano_rotulo(g.ano) || ' · Turma ' || g.turma
  from public.grade_aulas g
 where g.id = r.grade_aula_id and g.ano = -2 and r.turma like 'Educação infantil%';
alter table public.aulas_registro enable trigger registro_editado;
alter table public.aulas_registro enable trigger check_corrigido;

alter table public.grade_aulas add constraint grade_aulas_tipo_check check (tipo in ('R', 'P', 'F'));
alter table public.grade_aulas add constraint grade_aulas_ano_check check (ano is null or ano in (-2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9));
alter table public.grade_aulas add constraint grade_aulas_componente_lista check (componente is null or componente = any (privado.componentes()));
alter table public.grade_aulas add constraint grade_aulas_oficina_check check (oficina is null or length(oficina) between 1 and 60);
alter table public.grade_aulas add constraint grade_aulas_horario_check check (horario is null or horario between 1 and 12);
alter table public.grade_semanas add constraint grade_semanas_tipo_check check (tipo in ('R', 'P', 'F'));
alter table public.grade_semanas add constraint grade_semanas_componente_lista check (componente is null or componente = any (privado.componentes()));
alter table public.grade_semanas add constraint grade_semanas_oficina_check check (oficina is null or length(oficina) between 1 and 60);
alter table public.aulas_registro add constraint aulas_registro_tipo_check check (tipo in ('R', 'P', 'F'));
alter table public.aulas_registro add constraint aulas_registro_objetivo_check check (objetivo in ('Sim', 'Não'));
alter table public.aulas_registro add constraint aulas_registro_oficina_check check (oficina is null or length(oficina) between 1 and 60);
alter table public.aulas_registro add constraint aulas_registro_horario_check check (horario is null or horario between 1 and 12);
alter table public.turmas add constraint turmas_ano_check check (ano in (-2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9));

create or replace function privado.grade_exige_materia()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_ini integer := extract(epoch from new.inicio)::integer / 60;
  v_fim integer := extract(epoch from new.fim)::integer / 60;
begin
  new.oficina := nullif(trim(coalesce(new.oficina, '')), '');
  new.solucao := nullif(trim(coalesce(new.solucao, '')), '');
  if new.tipo = 'P' then
    new.componente := null;
    new.solucao := null;
  elsif new.tipo = 'F' then
    new.componente := null;
    new.oficina := null;
    new.ano := null;
    new.turma := null;
    new.professor := null;
  else
    new.oficina := null;
  end if;
  if new.horario is null then new.horario := greatest(1, least(12, ((v_ini - 420) / 50) + 1)); end if;
  if auth.uid() is null then return new; end if;
  if v_ini < 420 then perform privado.invalido('As atividades começam a partir das 07:00'); end if;
  if v_fim > 1020 then perform privado.invalido('A atividade precisa terminar até as 17:00'); end if;
  if v_fim - v_ini not in (50, 100, 150) then perform privado.invalido('cada atividade tem 1, 2 ou 3 horários de 50 minutos'); end if;
  if new.tipo in ('R', 'P') and (new.ano is null or new.turma is null) then perform privado.invalido('escolha o ano e a turma'); end if;
  if new.tipo = 'R' and new.componente is null then perform privado.invalido('escolha o componente curricular'); end if;
  if new.tipo = 'P' and new.oficina is null then perform privado.invalido('escolha a oficina'); end if;
  if new.tipo in ('R', 'F') and new.solucao is null then perform privado.invalido('escolha a solução prevista'); end if;
  return new;
end;
$$;
revoke all on function privado.grade_exige_materia() from public, anon;

create or replace function privado.registro_da_grade()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  g public.grade_aulas;
  s public.grade_semanas;
begin
  if new.grade_aula_id is null then return new; end if;
  select * into g from public.grade_aulas where id = new.grade_aula_id;
  if g.id is null then return new; end if;
  select * into s from public.grade_semanas
   where grade_aula_id = g.id and semana = (date_trunc('week', new.data))::date;
  new.inicio := g.inicio;
  new.fim := g.fim;
  new.horario := g.horario;
  new.tipo := coalesce(s.tipo, g.tipo);
  new.turma := case when new.tipo = 'F' then 'Professores'
                    else privado.ano_rotulo(g.ano) || ' · Turma ' || g.turma end;
  if new.tipo = 'P' and new.oficina is null then new.oficina := coalesce(s.oficina, g.oficina); end if;
  return new;
end;
$$;
revoke all on function privado.registro_da_grade() from public, anon;

create or replace function privado.registro_campos()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.oficina := nullif(trim(coalesce(new.oficina, '')), '');
  if new.tipo = 'P' then
    new.componente := null;
    new.solucao := null;
  else
    new.oficina := null;
  end if;
  if new.tipo = 'F' then new.componente := null; end if;
  return new;
end;
$$;
revoke all on function privado.registro_campos() from public, anon, authenticated;
drop trigger if exists registro_normalizado on public.aulas_registro;
create trigger registro_normalizado before insert or update on public.aulas_registro
  for each row execute function privado.registro_campos();

create or replace function privado.registro_na_presenca()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_ini timestamptz;
  v_fim timestamptz;
begin
  if auth.uid() is null or auth.uid() <> new.oficineiro_id then return null; end if;
  if new.situacao not in ('Realizada', 'Realizada parcialmente') then return null; end if;
  if tg_op = 'UPDATE' and old.situacao in ('Realizada', 'Realizada parcialmente')
     and old.data = new.data and old.inicio = new.inicio and old.fim = new.fim then
    return null;
  end if;
  v_ini := (new.data + new.inicio) at time zone 'America/Sao_Paulo';
  v_fim := (new.data + new.fim) at time zone 'America/Sao_Paulo';
  if not exists (
    select 1 from public.presencas p
     where p.oficineiro_id = new.oficineiro_id and p.data = new.data
       and p.inicio <= v_ini and coalesce(p.fim, greatest(now(), v_fim)) >= v_fim
  ) then
    perform privado.invalido('a atividade só pode ser registrada como realizada se você estava com a presença iniciada na escola nesse horário');
  end if;
  return null;
end;
$$;
revoke all on function privado.registro_na_presenca() from public, anon, authenticated;
drop trigger if exists registro_na_presenca on public.aulas_registro;
create trigger registro_na_presenca after insert or update on public.aulas_registro
  for each row execute function privado.registro_na_presenca();

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
  v_of text;
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
    if v_tipo is null or v_tipo not in ('R', 'P', 'F') then perform privado.invalido('tipo de atividade inválido'); end if;
    if v_tipo = 'F' and g.tipo <> 'F' then perform privado.invalido('formação de professores precisa de um horário próprio na grade padrão'); end if;
    if v_tipo <> 'F' and g.tipo = 'F' then perform privado.invalido('este horário é de formação de professores'); end if;
    v_sol := nullif(trim(coalesce(v_item ->> 'solucao', '')), '');
    v_comp := nullif(trim(coalesce(v_item ->> 'componente', '')), '');
    v_of := nullif(trim(coalesce(v_item ->> 'oficina', '')), '');
    if v_tipo = 'P' then
      v_sol := null;
      v_comp := null;
      if v_of is null or length(v_of) > 60 then perform privado.invalido('escolha a oficina de cada atividade'); end if;
    else
      v_of := null;
      if v_sol is null or length(v_sol) > 80 then perform privado.invalido('informe a solução de cada atividade'); end if;
      if v_tipo = 'F' then v_comp := null; end if;
      if v_tipo = 'R' then v_comp := coalesce(v_comp, g.componente); end if;
      if v_tipo = 'R' and v_comp is null then perform privado.invalido('escolha o componente curricular'); end if;
      if v_comp is not null and not (v_comp = any (privado.componentes())) then perform privado.invalido('componente curricular inválido'); end if;
    end if;
    if v_tipo = g.tipo and v_sol is not distinct from g.solucao and v_comp is not distinct from g.componente
       and v_of is not distinct from g.oficina then
      continue;
    end if;
    if v_comp is not distinct from g.componente then v_comp := null; end if;
    insert into public.grade_semanas (grade_aula_id, oficineiro_id, escola_id, ano_letivo, semana, tipo, solucao, componente, oficina)
    values (g.id, v_uid, g.escola_id, v_ano, p_semana, v_tipo, v_sol, v_comp, v_of)
    on conflict (grade_aula_id, semana) do update
      set tipo = excluded.tipo, solucao = excluded.solucao, componente = excluded.componente, oficina = excluded.oficina;
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
    insert into public.grade_semanas (grade_aula_id, oficineiro_id, escola_id, ano_letivo, semana, tipo, solucao, componente, oficina)
    select s.grade_aula_id, s.oficineiro_id, s.escola_id, s.ano_letivo, d, s.tipo, s.solucao, s.componente, s.oficina
      from public.grade_semanas s
     where s.oficineiro_id = v_uid and s.semana = p_origem;
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function privado.admin_salvar_turma(p_escola smallint, p_ano smallint, p_turma text, p_matriculados smallint)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_id integer;
  v_turma text := upper(trim(coalesce(p_turma, '')));
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if not exists (select 1 from public.escolas where id = p_escola) then perform privado.invalido('escola não encontrada'); end if;
  if p_ano is null or p_ano not in (-2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9) then perform privado.invalido('ano escolar inválido'); end if;
  if v_turma !~ '^[A-Z0-9]{0,4}$' then perform privado.invalido('turma: até 4 letras ou números'); end if;
  if p_matriculados is not null and p_matriculados not between 0 and 999 then perform privado.invalido('matriculados: de 0 a 999'); end if;
  insert into public.turmas (escola_id, ano, turma, matriculados)
  values (p_escola, p_ano, v_turma, p_matriculados)
  on conflict (escola_id, ano, turma) do update set matriculados = excluded.matriculados
  returning id into v_id;
  return v_id;
end;
$$;

grant insert (oficina, horario), update (oficina, horario) on public.grade_aulas to authenticated;
grant insert (oficina), update (oficina) on public.aulas_registro to authenticated;
