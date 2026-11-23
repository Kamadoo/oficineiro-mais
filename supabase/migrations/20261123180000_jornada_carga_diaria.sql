insert into public.carteiras (id, rotulo) values ('AT1', 'AT1') on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'fsm_jornada_hmac') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'), 'fsm_jornada_hmac', 'FSM: chave HMAC do login da base de acessos');
  end if;
end $$;

alter table public.jornada_pessoas alter column dias_acesso drop not null;
alter table public.jornada_pessoas add column if not exists carteira_id text references public.carteiras (id);
alter table public.jornada_pessoas add column if not exists turma text check (length(turma) between 1 and 40);
alter table public.jornada_pessoas add column if not exists primeiro_acesso date;
alter table public.jornada_pessoas add column if not exists ultimo_acesso date;
alter table public.jornada_pessoas add column if not exists login_hash bytea check (octet_length(login_hash) = 32);
alter table public.jornada_pessoas drop constraint if exists jornada_pessoas_datas_check;
alter table public.jornada_pessoas add constraint jornada_pessoas_datas_check check (
  (primeiro_acesso is null or primeiro_acesso <= base_ref) and (ultimo_acesso is null or ultimo_acesso <= base_ref)
);
create index if not exists jornada_pessoas_base on public.jornada_pessoas (base_ref);
create unique index if not exists jornada_pessoas_login_por_base on public.jornada_pessoas (base_ref, login_hash)
  where login_hash is not null;

revoke select on table public.jornada_pessoas from authenticated;
grant select (id, escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, responsavel_turma, base_ref,
              carteira_id, turma, primeiro_acesso, ultimo_acesso)
  on table public.jornada_pessoas to authenticated;

create table if not exists public.jornada_retratos (
  base_ref     date primary key,
  pessoas      integer not null default 0 check (pessoas >= 0),
  origem       text not null default 'importacao' check (origem in ('importacao', 'site')),
  resumo       jsonb,
  autor_id     uuid references public.perfis (id) on delete set null,
  autor_nome   text check (length(autor_nome) between 1 and 120),
  carregado_em timestamptz not null default now()
);

insert into public.jornada_retratos (base_ref, pessoas)
select j.base_ref, count(*)::int from public.jornada_pessoas j group by j.base_ref
on conflict (base_ref) do update set pessoas = excluded.pessoas;

alter table public.jornada_retratos enable row level security;
revoke all on table public.jornada_retratos from public, anon, authenticated;
grant select on table public.jornada_retratos to authenticated;
drop policy if exists jornada_retratos_ler on public.jornada_retratos;
create policy jornada_retratos_ler on public.jornada_retratos for select to authenticated
  using ((select privado.acesso_ok()) and (select privado.papel_atual()) in ('gerente', 'coordenador', 'analista'));

create or replace function privado.jornada_retratos_contar()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.jornada_retratos as r (base_ref, pessoas)
    select n.base_ref, count(*)::int from novas n group by n.base_ref
    on conflict (base_ref) do update set pessoas = r.pessoas + excluded.pessoas, carregado_em = now();
  else
    update public.jornada_retratos r set pessoas = greatest(0, r.pessoas - a.n)
      from (select base_ref, count(*)::int n from antigas group by base_ref) a
     where r.base_ref = a.base_ref;
    delete from public.jornada_retratos r
     where r.pessoas = 0 and r.base_ref in (select distinct base_ref from antigas);
  end if;
  return null;
end;
$$;
revoke all on function privado.jornada_retratos_contar() from public, anon, authenticated;

drop trigger if exists jornada_retratos_ins on public.jornada_pessoas;
create trigger jornada_retratos_ins after insert on public.jornada_pessoas
  referencing new table as novas for each statement execute function privado.jornada_retratos_contar();
drop trigger if exists jornada_retratos_del on public.jornada_pessoas;
create trigger jornada_retratos_del after delete on public.jornada_pessoas
  referencing old table as antigas for each statement execute function privado.jornada_retratos_contar();

create or replace function privado.sigla_de_unidade(p_nome text)
returns text
language plpgsql set search_path = ''
as $$
declare
  v_base text := (regexp_match(coalesce(p_nome, ''), '^\s*([A-Za-z0-9]{1,8})\s*-\s*'))[1];
  v_sigla text;
  v_n int := 2;
begin
  if v_base is null then
    select string_agg(left(p.palavra, 1), '' order by p.ordem) into v_base
      from (select palavra, ordem
              from regexp_split_to_table(
                     translate(lower(coalesce(p_nome, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'),
                     '[^a-z0-9]+') with ordinality as t(palavra, ordem)
             where palavra <> ''
               and palavra not in ('de', 'da', 'do', 'dos', 'das', 'e', 'municipal', 'secretaria', 'subsecretaria')
             order by ordem
             limit 5) p;
    v_base := coalesce(nullif(v_base, ''), 'un');
    v_base := upper(left(v_base, 1)) || substr(v_base, 2);
  end if;
  v_sigla := v_base;
  while exists (select 1 from public.escolas e where lower(e.sigla) = lower(v_sigla)) loop
    v_sigla := left(v_base, 8 - length(v_n::text)) || v_n;
    v_n := v_n + 1;
  end loop;
  return v_sigla;
end;
$$;
revoke all on function privado.sigla_de_unidade(text) from public, anon, authenticated;

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
  if not privado.eh_admin() then perform privado.negar(); end if;
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
         x.dias
    from rows from (jsonb_to_recordset(p_pessoas)
                    as (h text, nome text, tipo text, escola smallint, unidade text, carteira text, turma text, ano smallint,
                        responsavel text, primeiro date, ultimo date, dias integer))
         with ordinality as x(h, nome, tipo, escola, unidade, carteira, turma, ano, responsavel, primeiro, ultimo, dias, ordem);

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
                                      base_ref, carteira_id, turma, primeiro_acesso, ultimo_acesso, login_hash)
  select c.escola_id, c.nome, c.tipo, c.ano,
         case when c.ultimo is null then -1 else p_base_ref - c.ultimo end,
         c.dias, c.responsavel, p_base_ref, c.carteira, c.turma, c.primeiro, c.ultimo,
         extensions.hmac(c.h, v_chave, 'sha256')
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

create or replace function public.carregar_base_acessos(
  p_base_ref date, p_unidades jsonb, p_pessoas jsonb, p_substituir boolean default false, p_resumo jsonb default null
)
returns jsonb
language sql security invoker set search_path = ''
as $$ select privado.carregar_base_acessos(p_base_ref, p_unidades, p_pessoas, p_substituir, p_resumo) $$;

create or replace function public.jornada_resumo_mensal()
returns table (base_ref date, escola_id smallint, tipo char(1), ano_escolar smallint, n integer, nv integer, sr integer, en integer)
language sql stable security invoker set search_path = ''
as $$
  with ultima as (select max(r.base_ref) as d from public.jornada_retratos r),
       meses as (
         select max(r.base_ref) as d
           from public.jornada_retratos r, ultima u
          where r.base_ref > (u.d - interval '12 months')::date
          group by date_trunc('month', r.base_ref)
       )
  select j.base_ref, j.escola_id, j.tipo, j.ano_escolar,
         count(*)::int,
         count(*) filter (where j.dias_sem_acesso < 0)::int,
         count(*) filter (where j.dias_sem_acesso > 30)::int,
         count(*) filter (where j.dias_sem_acesso between 0 and 30 and coalesce(j.dias_acesso, 0) > 0
                            and j.dias_acesso::numeric / 26 >= case j.tipo when 'A' then 0.75 else 3 end)::int
    from public.jornada_pessoas j
   where j.base_ref in (select d from meses)
   group by j.base_ref, j.escola_id, j.tipo, j.ano_escolar
   order by j.base_ref, j.escola_id, j.tipo, j.ano_escolar;
$$;

revoke all on function privado.sigla_de_unidade(text),
                       privado.carregar_base_acessos(date, jsonb, jsonb, boolean, jsonb),
                       public.carregar_base_acessos(date, jsonb, jsonb, boolean, jsonb),
                       public.jornada_resumo_mensal()
  from public, anon, authenticated;
grant execute on function privado.carregar_base_acessos(date, jsonb, jsonb, boolean, jsonb),
                          public.carregar_base_acessos(date, jsonb, jsonb, boolean, jsonb),
                          public.jornada_resumo_mensal()
  to authenticated;
