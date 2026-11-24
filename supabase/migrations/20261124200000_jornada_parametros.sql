-- Jornada do Usuário: parâmetros do gerente, carteira de cada unidade, ajustes de lotação e carga diária pelo gerente.

create table if not exists public.jornada_parametros (
  id            smallint primary key default 1 check (id = 1),
  aulas_semana  smallint not null default 1 check (aulas_semana between 1 and 5),
  dias_semana   smallint not null default 3 check (dias_semana between 1 and 5),
  periodo       text not null default 'auto' check (periodo in ('auto', 'mes', '30d', '6m')),
  autor_nome    text,
  atualizado_em timestamptz
);
insert into public.jornada_parametros (id) values (1) on conflict (id) do nothing;
alter table public.jornada_parametros enable row level security;
revoke all on public.jornada_parametros from public, anon, authenticated;
grant select on public.jornada_parametros to authenticated;
drop policy if exists jornada_parametros_ler on public.jornada_parametros;
create policy jornada_parametros_ler on public.jornada_parametros for select to authenticated
  using ((select privado.acesso_ok()) and (select privado.papel_atual()) in ('gerente', 'analista', 'coordenador'));

-- Regras de lotação preenchidas por painel privado (sem nomes no código): por login ou por escola e ano mínimo (alunos).
create table if not exists public.jornada_ajustes_lotacao (
  id              bigint generated always as identity primary key,
  login_hash      bytea check (octet_length(login_hash) = 32),
  escola_base     smallint references public.escolas (id),
  ano_minimo      smallint check (ano_minimo between 1 and 9),
  escola_destino  smallint not null references public.escolas (id),
  criado_em       timestamptz not null default now(),
  check ((login_hash is not null and escola_base is null and ano_minimo is null)
      or (login_hash is null and escola_base is not null and ano_minimo is not null))
);
alter table public.jornada_ajustes_lotacao enable row level security;
revoke all on public.jornada_ajustes_lotacao from public, anon, authenticated;

create or replace function privado.resumo_de_login(p_login text)
returns bytea
language plpgsql stable security definer set search_path = ''
as $$
declare v_chave text := privado.segredo('fsm_jornada_hmac');
begin
  if v_chave is null then perform privado.invalido('chave da base de acessos não configurada'); end if;
  return extensions.hmac(encode(extensions.digest(lower(btrim(p_login)), 'sha256'), 'hex'), v_chave, 'sha256');
end;
$$;

create or replace function privado.aplicar_ajustes_lotacao(p_base date default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.jornada_ajustes_lotacao) then return; end if;
  update public.jornada_pessoas j
     set escola_id = a.escola_destino,
         carteira_id = coalesce((select e.carteira_id from public.escolas e where e.id = a.escola_destino), j.carteira_id)
    from public.jornada_ajustes_lotacao a
   where (p_base is null or j.base_ref = p_base)
     and j.escola_origem_id is null
     and j.escola_id is distinct from a.escola_destino
     and ((a.login_hash is not null and j.login_hash = a.login_hash)
       or (a.login_hash is null and j.tipo = 'A' and j.escola_id = a.escola_base and j.ano_escolar >= a.ano_minimo));
end;
$$;

create or replace function privado.tratativas_na_carga()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.aplicar_ajustes_lotacao(r.base_ref) from (select distinct n.base_ref from novas n) r;
  perform privado.aplicar_tratativas(null, r.base_ref) from (select distinct n.base_ref from novas n) r;
  return null;
end;
$$;

create or replace function privado.jornada_ajustes_lotacao()
returns table (id bigint, regra text, destino text, afetados integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_base date := (select max(r.base_ref) from public.jornada_retratos r);
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'gerente' then perform privado.negar(); end if;
  return query
  select a.id,
         case when a.login_hash is null
              then 'Alunos do ' || a.ano_minimo || 'º ano em diante que vêm na base como ' || coalesce(b.nome, 'escola ' || a.escola_base)
              else coalesce((select case p.tipo when 'A' then 'Aluno(a) ' when 'P' then 'Professor(a) ' else 'Servidor(a) ' end || p.nome
                               from public.jornada_pessoas p
                              where p.login_hash = a.login_hash order by p.base_ref desc limit 1), 'Usuário ainda não carregado')
         end,
         d.nome::text,
         (select count(*)::int from public.jornada_pessoas p
           where p.base_ref = v_base and p.escola_id = a.escola_destino and p.escola_origem_id is null
             and ((a.login_hash is not null and p.login_hash = a.login_hash)
               or (a.login_hash is null and p.tipo = 'A' and p.ano_escolar >= a.ano_minimo)))
    from public.jornada_ajustes_lotacao a
    join public.escolas d on d.id = a.escola_destino
    left join public.escolas b on b.id = a.escola_base
   order by a.id;
end;
$$;

create or replace function public.jornada_ajustes_lotacao()
returns table (id bigint, regra text, destino text, afetados integer)
language sql stable security invoker set search_path = ''
as $$ select * from privado.jornada_ajustes_lotacao(); $$;

create or replace function privado.salvar_parametros_jornada(p_aulas smallint, p_dias smallint, p_periodo text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'gerente' then perform privado.negar(); end if;
  if p_aulas is null or p_aulas not between 1 and 5 then perform privado.invalido('aulas por semana: de 1 a 5'); end if;
  if p_dias is null or p_dias not between 1 and 5 then perform privado.invalido('dias de uso por semana: de 1 a 5'); end if;
  if p_periodo is null or p_periodo not in ('auto', 'mes', '30d', '6m') then perform privado.invalido('período inválido'); end if;
  update public.jornada_parametros
     set aulas_semana = p_aulas, dias_semana = p_dias, periodo = p_periodo,
         autor_nome = (select p.nome from public.perfis p where p.id = auth.uid()), atualizado_em = now()
   where id = 1;
  perform auditoria.registrar('JORNADA_PARAMETROS', 'jornada_parametros', '1',
                              jsonb_build_object('aulas_semana', p_aulas, 'dias_semana', p_dias, 'periodo', p_periodo));
end;
$$;

create or replace function public.salvar_parametros_jornada(p_aulas smallint, p_dias smallint, p_periodo text)
returns void
language sql security invoker set search_path = ''
as $$ select privado.salvar_parametros_jornada(p_aulas, p_dias, p_periodo); $$;

create or replace function privado.definir_carteira_da_unidade(p_escola smallint, p_carteira text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_antes text;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'gerente' then perform privado.negar(); end if;
  select e.carteira_id into v_antes from public.escolas e where e.id = p_escola;
  if not found then perform privado.invalido('unidade não encontrada'); end if;
  if p_carteira is not null and not exists (select 1 from public.carteiras c where c.id = p_carteira) then
    perform privado.invalido('carteira não encontrada');
  end if;
  if v_antes is not distinct from p_carteira then return; end if;
  update public.escolas set carteira_id = p_carteira where id = p_escola;
  update public.jornada_pessoas set carteira_id = p_carteira
   where escola_id = p_escola and base_ref = (select max(r.base_ref) from public.jornada_retratos r);
  perform auditoria.registrar('JORNADA_CARTEIRA_UNIDADE', 'escolas', p_escola::text,
                              jsonb_build_object('antes', v_antes, 'depois', p_carteira));
end;
$$;

create or replace function public.definir_carteira_da_unidade(p_escola smallint, p_carteira text)
returns void
language sql security invoker set search_path = ''
as $$ select privado.definir_carteira_da_unidade(p_escola, p_carteira); $$;

revoke all on function privado.resumo_de_login(text),
                       privado.aplicar_ajustes_lotacao(date),
                       privado.tratativas_na_carga(),
                       privado.jornada_ajustes_lotacao(),
                       public.jornada_ajustes_lotacao(),
                       privado.salvar_parametros_jornada(smallint, smallint, text),
                       public.salvar_parametros_jornada(smallint, smallint, text),
                       privado.definir_carteira_da_unidade(smallint, text),
                       public.definir_carteira_da_unidade(smallint, text)
  from public, anon, authenticated;
grant execute on function privado.jornada_ajustes_lotacao(),
                          public.jornada_ajustes_lotacao(),
                          privado.salvar_parametros_jornada(smallint, smallint, text),
                          public.salvar_parametros_jornada(smallint, smallint, text),
                          privado.definir_carteira_da_unidade(smallint, text),
                          public.definir_carteira_da_unidade(smallint, text)
  to authenticated;

-- Carga diária: o gerente também grava a base, com a mesma verificação em duas etapas do administrador.
create or replace function privado.carregar_base_acessos(
  p_base_ref date, p_unidades jsonb, p_pessoas jsonb, p_substituir boolean, p_resumo jsonb
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_chave text;
  v_existia int;
  v_unidade record;
  v_id smallint;
  v_novas int := 0;
  v_com_carteira int := 0;
  v_ruim record;
  v_total int;
  v_inseridas int;
begin
  if not (privado.eh_admin() or (privado.acesso_ok() and privado.papel_atual() = 'gerente')) then
    perform privado.negar();
  end if;
  if p_base_ref is null or p_base_ref > privado.hoje() then
    perform privado.invalido('data da base: informe uma data até hoje');
  end if;
  if p_base_ref < privado.hoje() - interval '5 years' then
    perform privado.invalido('data da base fora do prazo de guarda de 5 anos');
  end if;
  if jsonb_typeof(p_pessoas) is distinct from 'array' or jsonb_array_length(p_pessoas) not between 1 and 30000 then
    perform privado.invalido('envie de 1 a 30000 pessoas');
  end if;
  if p_unidades is not null and (jsonb_typeof(p_unidades) <> 'array' or jsonb_array_length(p_unidades) > 300) then
    perform privado.invalido('lista de unidades inválida');
  end if;
  if p_resumo is not null and (jsonb_typeof(p_resumo) <> 'object' or length(p_resumo::text) > 20000) then
    perform privado.invalido('resumo da carga inválido');
  end if;
  select pessoas into v_existia from public.jornada_retratos where base_ref = p_base_ref;
  if v_existia is not null and not coalesce(p_substituir, false) then
    perform privado.invalido('já existe base de acessos nesta data: confirme a substituição');
  end if;
  v_chave := privado.segredo('fsm_jornada_hmac');
  if v_chave is null then perform privado.invalido('chave da base de acessos não configurada'); end if;

  for v_unidade in
    select u.escola, btrim(regexp_replace(coalesce(u.nome, ''), '\s+', ' ', 'g')) as nome, u.carteira, u.ordem
      from rows from (jsonb_to_recordset(coalesce(p_unidades, '[]'::jsonb)) as (escola smallint, nome text, carteira text))
           with ordinality as u(escola, nome, carteira, ordem)
  loop
    if v_unidade.carteira is null or not exists (select 1 from public.carteiras c where c.id = v_unidade.carteira) then
      perform privado.invalido('unidade ' || v_unidade.ordem || ': carteira não encontrada');
    end if;
    if v_unidade.escola is not null then
      update public.escolas e set carteira_id = v_unidade.carteira
       where e.id = v_unidade.escola and e.carteira_id is null;
      if found then v_com_carteira := v_com_carteira + 1; end if;
    else
      if length(v_unidade.nome) not between 3 and 160 then
        perform privado.invalido('unidade ' || v_unidade.ordem || ': nome de 3 a 160 caracteres');
      end if;
      select e.id into v_id from public.escolas e where lower(e.nome) = lower(v_unidade.nome) order by e.id limit 1;
      if v_id is null then
        insert into public.escolas (sigla, nome, carteira_id)
        values (privado.sigla_de_unidade(v_unidade.nome), v_unidade.nome, v_unidade.carteira)
        returning id into v_id;
        v_novas := v_novas + 1;
      end if;
      v_id := null;
    end if;
  end loop;

  drop table if exists pg_temp.carga_pessoas;
  create temporary table pg_temp.carga_pessoas on commit drop as
  select x.ordem,
         lower(x.h) as h,
         btrim(regexp_replace(coalesce(x.nome, ''), '\s+', ' ', 'g')) as nome,
         x.tipo,
         coalesce(x.escola, (select e.id from public.escolas e
                              where lower(e.nome) = lower(btrim(regexp_replace(coalesce(x.unidade, ''), '\s+', ' ', 'g')))
                              order by e.id limit 1)) as escola_id,
         x.carteira,
         nullif(btrim(coalesce(x.turma, '')), '') as turma,
         coalesce(x.ano, 0) as ano,
         nullif(btrim(regexp_replace(coalesce(x.responsavel, ''), '\s+', ' ', 'g')), '') as responsavel,
         x.primeiro,
         x.ultimo,
         x.dias,
         nullif(btrim(coalesce(x.matricula, '')), '') as matricula,
         nullif(lower(btrim(coalesce(x.email, ''))), '') as email,
         nullif(btrim(regexp_replace(coalesce(x.funcao, ''), '\s+', ' ', 'g')), '') as funcao
    from rows from (jsonb_to_recordset(p_pessoas)
                    as (h text, nome text, tipo text, escola smallint, unidade text, carteira text, turma text, ano smallint,
                        responsavel text, primeiro date, ultimo date, dias integer, matricula text, email text, funcao text))
         with ordinality as x(h, nome, tipo, escola, unidade, carteira, turma, ano, responsavel, primeiro, ultimo, dias,
                              matricula, email, funcao, ordem);

  select c.ordem,
         case
           when c.h is null or c.h !~ '^[0-9a-f]{64}$' then 'login sem resumo válido'
           when length(c.nome) not between 2 and 160 then 'nome de 2 a 160 caracteres'
           when c.tipo is null or c.tipo not in ('A', 'P', 'S') then 'perfil inválido'
           when c.escola_id is null or not exists (select 1 from public.escolas e where e.id = c.escola_id) then 'unidade não encontrada'
           when c.carteira is not null and not exists (select 1 from public.carteiras k where k.id = c.carteira) then 'carteira não encontrada'
           when c.ano not between 0 and 9 then 'ano escolar inválido'
           when length(c.turma) > 40 then 'turma com mais de 40 caracteres'
           when length(c.responsavel) > 160 then 'responsável com mais de 160 caracteres'
           when c.primeiro > p_base_ref or c.ultimo > p_base_ref then 'data de acesso depois da data da base'
           when c.primeiro < date '2000-01-01' or c.ultimo < date '2000-01-01' then 'data de acesso inválida'
           when c.dias < 0 or c.dias > 100000 then 'dias de acesso inválidos'
           when c.matricula !~ '^[0-9A-Za-z.-]{1,20}$' then 'matrícula inválida'
           when length(c.email) > 160 or c.email !~ '^[^@\s]+@[^@\s]+$' then 'e-mail inválido'
           when length(c.funcao) > 80 then 'função com mais de 80 caracteres'
         end as motivo
    into v_ruim
    from pg_temp.carga_pessoas c
   where c.h is null or c.h !~ '^[0-9a-f]{64}$' or length(c.nome) not between 2 and 160
      or c.tipo is null or c.tipo not in ('A', 'P', 'S')
      or c.escola_id is null or not exists (select 1 from public.escolas e where e.id = c.escola_id)
      or (c.carteira is not null and not exists (select 1 from public.carteiras k where k.id = c.carteira))
      or c.ano not between 0 and 9 or length(c.turma) > 40 or length(c.responsavel) > 160
      or c.primeiro > p_base_ref or c.ultimo > p_base_ref
      or c.primeiro < date '2000-01-01' or c.ultimo < date '2000-01-01'
      or c.dias < 0 or c.dias > 100000
      or c.matricula !~ '^[0-9A-Za-z.-]{1,20}$' or length(c.email) > 160 or c.email !~ '^[^@\s]+@[^@\s]+$'
      or length(c.funcao) > 80
   order by c.ordem
   limit 1;
  if v_ruim.ordem is not null then
    perform privado.invalido('pessoa ' || v_ruim.ordem || ': ' || v_ruim.motivo);
  end if;
  select count(*)::int into v_total from pg_temp.carga_pessoas;
  if (select count(distinct h) from pg_temp.carga_pessoas) <> v_total then
    perform privado.invalido('há logins repetidos na carga');
  end if;

  delete from public.jornada_pessoas where base_ref = p_base_ref;
  insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma,
                                      base_ref, carteira_id, turma, primeiro_acesso, ultimo_acesso, login_hash,
                                      matricula, email, funcao)
  select c.escola_id, c.nome, c.tipo, c.ano,
         case when c.ultimo is null then -1 else p_base_ref - c.ultimo end,
         c.dias, c.responsavel, p_base_ref, c.carteira, c.turma, c.primeiro, c.ultimo,
         extensions.hmac(c.h, v_chave, 'sha256'),
         c.matricula, c.email, c.funcao
    from pg_temp.carga_pessoas c
   order by c.ordem;
  get diagnostics v_inseridas = row_count;

  update public.jornada_retratos
     set origem = 'site', resumo = p_resumo, autor_id = auth.uid(),
         autor_nome = (select p.nome from public.perfis p where p.id = auth.uid()), carregado_em = now()
   where base_ref = p_base_ref;

  perform auditoria.registrar('CARGA_BASE_ACESSOS', 'jornada_pessoas', p_base_ref::text,
                              jsonb_build_object('pessoas', v_inseridas, 'substituidas', coalesce(v_existia, 0),
                                                 'unidades_novas', v_novas, 'unidades_com_carteira', v_com_carteira));
  return jsonb_build_object('base_ref', p_base_ref, 'pessoas', v_inseridas, 'substituidas', coalesce(v_existia, 0),
                            'unidades_novas', v_novas, 'unidades_com_carteira', v_com_carteira);
end;
$$;
