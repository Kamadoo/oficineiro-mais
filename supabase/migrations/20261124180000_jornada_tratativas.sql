alter table public.jornada_pessoas add column if not exists matricula text check (length(matricula) between 1 and 20);
alter table public.jornada_pessoas add column if not exists email text check (length(email) between 3 and 160);
alter table public.jornada_pessoas add column if not exists funcao text check (length(funcao) between 1 and 80);
alter table public.jornada_pessoas add column if not exists situacao text
  check (situacao in ('pend_desat', 'em_analise', 'mantido', 'transferido', 'desativado'));
alter table public.jornada_pessoas add column if not exists escola_origem_id smallint references public.escolas (id);
create index if not exists jornada_pessoas_login on public.jornada_pessoas (login_hash) where login_hash is not null;

grant select (matricula, email, funcao, situacao, escola_origem_id) on table public.jornada_pessoas to authenticated;

drop policy if exists jornada_ler on public.jornada_pessoas;
create policy jornada_ler on public.jornada_pessoas for select to authenticated
  using (escola_id = any (coalesce((select privado.escolas_da_jornada()), '{}'::smallint[]))
         and situacao is distinct from 'desativado');

create table if not exists public.jornada_tratativas (
  id             bigint generated always as identity primary key,
  login_hash     bytea not null check (octet_length(login_hash) = 32),
  nome           text not null check (length(nome) between 2 and 160),
  tipo           char(1) not null check (tipo in ('A', 'P', 'S')),
  matricula      text check (length(matricula) between 1 and 20),
  email          text check (length(email) between 3 and 160),
  acao           text not null check (acao in ('saiu', 'transferido', 'licenca')),
  status         text not null check (status in ('pend_desat', 'em_analise', 'mantido', 'transferido', 'desativado')),
  escola_origem  smallint not null references public.escolas (id),
  escola_destino smallint references public.escolas (id),
  observacao     text check (length(observacao) <= 500),
  base_ref       date not null,
  autor_id       uuid references public.perfis (id) on delete set null,
  autor_nome     text not null check (length(autor_nome) between 1 and 120),
  carteira_id    text references public.carteiras (id),
  criado_em      timestamptz not null default now(),
  decidido_por   uuid references public.perfis (id) on delete set null,
  decidido_nome  text check (length(decidido_nome) between 1 and 120),
  decidido_em    timestamptz,
  ciente_em      timestamptz,
  check ((acao = 'transferido') = (escola_destino is not null)),
  check (escola_destino is distinct from escola_origem)
);
create index if not exists jornada_tratativas_login on public.jornada_tratativas (login_hash, criado_em desc, id desc);
create index if not exists jornada_tratativas_destino on public.jornada_tratativas (escola_destino) where ciente_em is null;
create unique index if not exists jornada_tratativas_aberta on public.jornada_tratativas (login_hash)
  where status in ('pend_desat', 'em_analise');

alter table public.jornada_tratativas enable row level security;
revoke all on table public.jornada_tratativas from public, anon, authenticated;
grant select (id, nome, tipo, matricula, email, acao, status, escola_origem, escola_destino, observacao, base_ref,
              autor_nome, carteira_id, criado_em, decidido_nome, decidido_em, ciente_em)
  on table public.jornada_tratativas to authenticated;

drop policy if exists jornada_tratativas_ler on public.jornada_tratativas;
create policy jornada_tratativas_ler on public.jornada_tratativas for select to authenticated
  using (
    (select privado.acesso_ok())
    and ((select privado.papel_atual()) in ('gerente', 'coordenador')
         or ((select privado.papel_atual()) = 'analista'
             and (escola_origem = any (coalesce((select privado.escolas_da_jornada()), '{}'::smallint[]))
                  or escola_destino = any (coalesce((select privado.escolas_da_jornada()), '{}'::smallint[])))))
  );

create or replace function privado.aplicar_tratativas(p_login bytea default null, p_base date default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.jornada_tratativas t where p_login is null or t.login_hash = p_login) then
    return;
  end if;
  if exists (select 1 from public.jornada_pessoas j
              where (j.escola_origem_id is not null or j.situacao is not null)
                and (p_login is null or j.login_hash = p_login)
                and (p_base is null or j.base_ref = p_base)) then
    update public.jornada_pessoas j
       set escola_id = coalesce(j.escola_origem_id, j.escola_id),
           escola_origem_id = null,
           situacao = null
     where (j.escola_origem_id is not null or j.situacao is not null)
       and (p_login is null or j.login_hash = p_login)
       and (p_base is null or j.base_ref = p_base);
  end if;

  update public.jornada_pessoas j
     set escola_origem_id = j.escola_id,
         escola_id = t.escola_destino,
         carteira_id = coalesce((select e.carteira_id from public.escolas e where e.id = t.escola_destino), j.carteira_id),
         turma = case when j.tipo = 'A' then null else j.turma end,
         ano_escolar = case when j.tipo = 'A' then 0 else j.ano_escolar end,
         responsavel_turma = case when j.tipo = 'A' then null else j.responsavel_turma end
    from (select distinct on (x.login_hash) x.login_hash, x.escola_destino, x.base_ref
            from public.jornada_tratativas x
           where x.acao = 'transferido' and (p_login is null or x.login_hash = p_login)
           order by x.login_hash, x.criado_em desc, x.id desc) t
   where j.login_hash = t.login_hash
     and j.base_ref >= t.base_ref
     and j.escola_id is distinct from t.escola_destino
     and (p_base is null or j.base_ref = p_base);

  update public.jornada_pessoas j
     set situacao = t.status
    from (select distinct on (x.login_hash) x.login_hash, x.status, x.base_ref
            from public.jornada_tratativas x
           where p_login is null or x.login_hash = p_login
           order by x.login_hash, x.criado_em desc, x.id desc) t
   where j.login_hash = t.login_hash
     and (j.base_ref >= t.base_ref or t.status = 'desativado')
     and (p_base is null or j.base_ref = p_base);
end;
$$;

create or replace function privado.tratar_usuario(p_pessoa bigint, p_acao text, p_destino smallint, p_observacao text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_papel public.papel := privado.papel_atual();
  v_obs text := nullif(btrim(regexp_replace(coalesce(p_observacao, ''), '[[:cntrl:]]+', ' ', 'g')), '');
  v_pessoa record;
  v_escola smallint;
  v_id bigint;
begin
  if not privado.acesso_ok() or v_papel is null or v_papel not in ('gerente', 'analista') then
    perform privado.negar();
  end if;
  select j.* into v_pessoa from public.jornada_pessoas j where j.id = p_pessoa;
  if v_pessoa.id is null or v_pessoa.login_hash is null then perform privado.invalido('usuário não encontrado na base'); end if;
  if v_pessoa.base_ref <> (select max(r.base_ref) from public.jornada_retratos r) then
    perform privado.invalido('use a base de acessos mais recente');
  end if;
  v_escola := v_pessoa.escola_id;
  if not (v_escola = any (coalesce(privado.escolas_da_jornada(), '{}'::smallint[]))) then perform privado.negar(); end if;
  if v_pessoa.situacao in ('pend_desat', 'em_analise', 'desativado') then
    perform privado.invalido('este usuário já está com o gerente');
  end if;
  if p_acao is null or p_acao not in ('saiu', 'transferido', 'licenca') then perform privado.invalido('situação inválida'); end if;
  if length(v_obs) > 500 then perform privado.invalido('observação com mais de 500 caracteres'); end if;
  if p_acao = 'saiu' and (v_obs is null or length(v_obs) < 3) then perform privado.invalido('informe o motivo da saída'); end if;
  if p_acao = 'transferido' then
    if p_destino is null or not exists (select 1 from public.escolas e where e.id = p_destino) then
      perform privado.invalido('escolha a nova escola');
    end if;
    if p_destino = v_escola then perform privado.invalido('a nova escola é a escola atual'); end if;
  end if;

  insert into public.jornada_tratativas (login_hash, nome, tipo, matricula, email, acao, status, escola_origem, escola_destino,
                                         observacao, base_ref, autor_id, autor_nome, carteira_id)
  values (v_pessoa.login_hash, v_pessoa.nome, v_pessoa.tipo, v_pessoa.matricula, v_pessoa.email, p_acao,
          case p_acao when 'saiu' then 'pend_desat' when 'transferido' then 'transferido' else 'em_analise' end,
          v_escola, case when p_acao = 'transferido' then p_destino end, v_obs, v_pessoa.base_ref,
          auth.uid(), (select p.nome from public.perfis p where p.id = auth.uid()),
          (select e.carteira_id from public.escolas e where e.id = v_escola))
  returning id into v_id;
  perform privado.aplicar_tratativas(v_pessoa.login_hash);
  perform auditoria.registrar('JORNADA_TRATATIVA', 'jornada_tratativas', v_id::text,
                              jsonb_build_object('acao', p_acao, 'escola_origem', v_escola, 'escola_destino', p_destino));
  return v_id;
end;
$$;

create or replace function privado.decidir_tratativas(p_ids bigint[], p_decisao text)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_de text;
  v_para text;
  v_n integer;
  v_login bytea;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'gerente' then perform privado.negar(); end if;
  if p_ids is null or cardinality(p_ids) not between 1 and 2000 then perform privado.invalido('escolha de 1 a 2000 usuários'); end if;
  case p_decisao
    when 'desativar' then v_de := 'pend_desat'; v_para := 'desativado';
    when 'manter' then v_de := 'em_analise'; v_para := 'mantido';
    when 'para_desativacao' then v_de := 'em_analise'; v_para := 'pend_desat';
    else perform privado.invalido('decisão inválida');
  end case;
  if exists (select 1 from unnest(p_ids) i where not exists (
               select 1 from public.jornada_tratativas t where t.id = i and t.status = v_de)) then
    perform privado.invalido('há usuários que não estão nesta situação');
  end if;
  update public.jornada_tratativas t
     set status = v_para, decidido_por = auth.uid(), decidido_em = now(),
         decidido_nome = (select p.nome from public.perfis p where p.id = auth.uid())
   where t.id = any (p_ids);
  get diagnostics v_n = row_count;
  for v_login in select distinct t.login_hash from public.jornada_tratativas t where t.id = any (p_ids) loop
    perform privado.aplicar_tratativas(v_login);
  end loop;
  perform auditoria.registrar('JORNADA_TRATATIVA_DECISAO', 'jornada_tratativas', p_decisao,
                              jsonb_build_object('decisao', p_decisao, 'usuarios', v_n));
  return v_n;
end;
$$;

create or replace function privado.ciente_tratativas()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_n integer;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  update public.jornada_tratativas t
     set ciente_em = now()
   where t.acao = 'transferido' and t.ciente_em is null
     and t.escola_destino in (select e.id from public.escolas e where e.carteira_id = privado.carteira_atual());
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function public.tratar_usuario(p_pessoa bigint, p_acao text, p_destino smallint default null,
                                                 p_observacao text default null)
returns bigint
language sql security invoker set search_path = ''
as $$ select privado.tratar_usuario(p_pessoa, p_acao, p_destino, p_observacao) $$;

create or replace function public.decidir_tratativas(p_ids bigint[], p_decisao text)
returns integer
language sql security invoker set search_path = ''
as $$ select privado.decidir_tratativas(p_ids, p_decisao) $$;

create or replace function public.ciente_tratativas()
returns integer
language sql security invoker set search_path = ''
as $$ select privado.ciente_tratativas() $$;

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

create or replace function privado.tratativas_na_carga()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.aplicar_tratativas(null, r.base_ref) from (select distinct n.base_ref from novas n) r;
  return null;
end;
$$;

drop trigger if exists jornada_pessoas_tratativas on public.jornada_pessoas;
create trigger jornada_pessoas_tratativas after insert on public.jornada_pessoas
  referencing new table as novas for each statement execute function privado.tratativas_na_carga();

revoke all on function privado.aplicar_tratativas(bytea, date),
                       privado.tratativas_na_carga(),
                       privado.tratar_usuario(bigint, text, smallint, text),
                       privado.decidir_tratativas(bigint[], text),
                       privado.ciente_tratativas(),
                       public.tratar_usuario(bigint, text, smallint, text),
                       public.decidir_tratativas(bigint[], text),
                       public.ciente_tratativas()
  from public, anon, authenticated;
grant execute on function privado.tratar_usuario(bigint, text, smallint, text),
                          privado.decidir_tratativas(bigint[], text),
                          privado.ciente_tratativas(),
                          public.tratar_usuario(bigint, text, smallint, text),
                          public.decidir_tratativas(bigint[], text),
                          public.ciente_tratativas()
  to authenticated;
