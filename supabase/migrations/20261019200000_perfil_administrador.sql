alter type public.papel add value if not exists 'administrador';

alter table public.perfis drop constraint if exists escopo_por_papel;
alter table public.perfis add constraint escopo_por_papel check (
  (papel::text in ('oficineiro', 'direcao') and escola_id is not null and carteira_id is null) or
  (papel::text = 'analista' and carteira_id is not null and escola_id is null) or
  (papel::text in ('gerente', 'coordenador', 'administrador') and escola_id is null and carteira_id is null)
);

create or replace function privado.papel_atual()
returns public.papel
language sql stable security definer set search_path = ''
as $$
  select case when p.papel::text = 'administrador' then 'coordenador'::public.papel else p.papel end
    from public.perfis p
   where p.id = auth.uid() and p.ativo and not p.trocar_senha;
$$;

create or replace function privado.eh_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis p
                  where p.id = auth.uid() and p.ativo and not p.trocar_senha and p.papel::text = 'administrador')
     and privado.acesso_ok();
$$;
revoke all on function privado.eh_admin() from public, anon;
grant execute on function privado.eh_admin() to authenticated;

create or replace function privado.admin_alvo(p_usuario uuid)
returns public.perfis
language plpgsql security definer set search_path = ''
as $$
declare v public.perfis;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if p_usuario = auth.uid() then perform privado.invalido('não é possível alterar a própria conta'); end if;
  select * into v from public.perfis where id = p_usuario for update;
  if v.id is null then perform privado.invalido('conta não encontrada'); end if;
  if v.papel::text = 'administrador' then perform privado.invalido('contas de administrador só podem ser alteradas pelo painel do Supabase'); end if;
  return v;
end;
$$;
revoke all on function privado.admin_alvo(uuid) from public, anon, authenticated;

create or replace function privado.admin_motivo(p_motivo text)
returns text
language plpgsql set search_path = ''
as $$
begin
  if length(trim(coalesce(p_motivo, ''))) < 10 then perform privado.invalido('explique o motivo com pelo menos 10 caracteres'); end if;
  return left(trim(p_motivo), 500);
end;
$$;
revoke all on function privado.admin_motivo(text) from public, anon, authenticated;

drop function if exists public.contas_gestao();
drop function if exists privado.contas_gestao();
create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean)
language plpgsql security definer set search_path = ''
as $$
declare v_admin boolean := privado.eh_admin();
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  perform privado.aplicar_mudancas_escola();
  return query
    select p.id, p.nome, p.usuario, p.papel::text, p.escola_id, p.carteira_id, p.ativo,
           (p.usuario is null or p.trocar_senha), p.criado_em, x.acesso_atual, p.telefone,
           m.escola_nova, m.vale_a_partir, m.motivo, p.id = auth.uid(), to_char(p.jornada_inicio, 'HH24:MI'),
           p.trocar_senha
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     where v_admin or p.papel::text <> 'administrador'
     order by p.nome;
end;
$$;
create or replace function public.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean)
language sql security invoker set search_path = ''
as $$ select * from privado.contas_gestao() $$;
revoke all on function privado.contas_gestao(), public.contas_gestao() from public, anon;
grant execute on function privado.contas_gestao(), public.contas_gestao() to authenticated;

create or replace function privado.admin_alterar_papel(p_usuario uuid, p_papel text, p_escola smallint, p_carteira text, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.perfis;
  v_motivo text;
  v_escola smallint;
  v_carteira text;
begin
  v := privado.admin_alvo(p_usuario);
  v_motivo := privado.admin_motivo(p_motivo);
  if p_papel is null or p_papel not in ('gerente', 'coordenador', 'analista', 'direcao', 'oficineiro') then
    perform privado.invalido('perfil inválido');
  end if;
  if p_papel in ('oficineiro', 'direcao') then
    if not exists (select 1 from public.escolas where id = p_escola and ativa) then perform privado.invalido('escolha uma escola ativa'); end if;
    v_escola := p_escola;
  elsif p_papel = 'analista' then
    if not exists (select 1 from public.carteiras where id = p_carteira) then perform privado.invalido('escolha uma carteira'); end if;
    v_carteira := p_carteira;
  end if;
  if v.papel::text = p_papel and v.escola_id is not distinct from v_escola and v.carteira_id is not distinct from v_carteira then
    perform privado.invalido('nada foi alterado');
  end if;
  update public.mudancas_escola set cancelada_em = now()
   where usuario_id = v.id and aplicada_em is null and cancelada_em is null;
  update public.perfis
     set papel = p_papel::public.papel,
         escola_id = v_escola,
         carteira_id = v_carteira,
         jornada_inicio = case when p_papel = 'oficineiro' then jornada_inicio end
   where id = v.id;
  perform auditoria.registrar('ADMIN_ALTERAR_PERFIL', 'perfis', v.id::text, jsonb_build_object(
    'papel', jsonb_build_object('de', v.papel::text, 'para', p_papel),
    'escola_id', jsonb_build_object('de', v.escola_id, 'para', v_escola),
    'carteira_id', jsonb_build_object('de', v.carteira_id, 'para', v_carteira),
    'motivo', v_motivo));
end;
$$;

create or replace function privado.admin_exigir_troca_senha(p_usuario uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.perfis;
  v_motivo text;
begin
  v := privado.admin_alvo(p_usuario);
  v_motivo := privado.admin_motivo(p_motivo);
  if v.usuario is null then perform privado.invalido('esta conta ainda não fez o primeiro acesso'); end if;
  if v.trocar_senha then perform privado.invalido('esta conta já precisa trocar a senha no próximo acesso'); end if;
  update public.perfis set trocar_senha = true where id = v.id;
  perform auditoria.registrar('ADMIN_EXIGIR_TROCA_SENHA', 'perfis', v.id::text, jsonb_build_object('motivo', v_motivo));
end;
$$;

create or replace function privado.admin_salvar_escola(
  p_id smallint, p_sigla text, p_nome text, p_endereco text, p_telefone text, p_carteira text,
  p_latitude double precision, p_longitude double precision, p_raio smallint, p_ativa boolean
)
returns smallint
language plpgsql security definer set search_path = ''
as $$
declare
  v_id smallint;
  v_sigla text := trim(coalesce(p_sigla, ''));
  v_nome text := trim(coalesce(p_nome, ''));
  v_tel text := nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), '');
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if v_sigla !~ '^[A-Za-z0-9]{1,8}$' then perform privado.invalido('sigla: de 1 a 8 letras ou números'); end if;
  if length(v_nome) < 3 or length(v_nome) > 160 then perform privado.invalido('nome da escola: de 3 a 160 caracteres'); end if;
  if v_tel is not null and length(v_tel) not between 10 and 11 then perform privado.invalido('telefone inválido: use DDD e número'); end if;
  if p_carteira is not null and not exists (select 1 from public.carteiras where id = p_carteira) then
    perform privado.invalido('carteira não encontrada');
  end if;
  if (p_latitude is null) <> (p_longitude is null) then perform privado.invalido('informe latitude e longitude juntas'); end if;
  if p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    perform privado.invalido('coordenadas inválidas');
  end if;
  if coalesce(p_raio, 80) not between 20 and 500 then perform privado.invalido('o raio precisa ficar entre 20 e 500 metros'); end if;
  if exists (select 1 from public.escolas where lower(sigla) = lower(v_sigla) and id is distinct from p_id) then
    perform privado.invalido('já existe uma escola com esta sigla');
  end if;
  if p_id is null then
    insert into public.escolas (sigla, nome, endereco, telefone, carteira_id, latitude, longitude, raio_m, ativa, posicao_confirmada)
    values (v_sigla, v_nome, nullif(trim(coalesce(p_endereco, '')), ''), v_tel, p_carteira, p_latitude, p_longitude,
            coalesce(p_raio, 80), coalesce(p_ativa, true), p_latitude is not null)
    returning id into v_id;
  else
    if coalesce(p_ativa, true) = false and exists (select 1 from public.perfis where escola_id = p_id and ativo) then
      perform privado.invalido('a escola tem contas ativas: mude essas pessoas de escola antes de desativá-la');
    end if;
    update public.escolas
       set sigla = v_sigla, nome = v_nome, endereco = nullif(trim(coalesce(p_endereco, '')), ''), telefone = v_tel,
           carteira_id = p_carteira, latitude = p_latitude, longitude = p_longitude, raio_m = coalesce(p_raio, 80),
           ativa = coalesce(p_ativa, true),
           posicao_confirmada = case when latitude is distinct from p_latitude or longitude is distinct from p_longitude
                                     then p_latitude is not null else posicao_confirmada end
     where id = p_id
    returning id into v_id;
    if v_id is null then perform privado.invalido('escola não encontrada'); end if;
  end if;
  return v_id;
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
  if p_ano is null or p_ano not between 0 and 9 then perform privado.invalido('ano escolar inválido'); end if;
  if v_turma !~ '^[A-Z0-9]{0,4}$' then perform privado.invalido('turma: até 4 letras ou números'); end if;
  if p_matriculados is not null and p_matriculados not between 0 and 999 then perform privado.invalido('matriculados: de 0 a 999'); end if;
  insert into public.turmas (escola_id, ano, turma, matriculados)
  values (p_escola, p_ano, v_turma, p_matriculados)
  on conflict (escola_id, ano, turma) do update set matriculados = excluded.matriculados
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.admin_remover_turma(p_id integer)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.turmas;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  select * into v from public.turmas where id = p_id;
  if v.id is null then perform privado.invalido('turma não encontrada'); end if;
  if exists (select 1 from public.grade_aulas g
              where g.escola_id = v.escola_id and g.ano = v.ano and g.turma = v.turma
                and g.ano_letivo >= extract(year from privado.hoje())) then
    perform privado.invalido('esta turma está na grade de um oficineiro: retire da grade antes de remover');
  end if;
  delete from public.turmas where id = p_id;
end;
$$;

create or replace function privado.admin_salvar_carteira(p_id text, p_rotulo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id text := upper(trim(coalesce(p_id, '')));
  v_rotulo text := trim(coalesce(p_rotulo, ''));
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if v_id !~ '^[A-Z]{2,3}\d{1,2}$' then perform privado.invalido('código da carteira: 2 ou 3 letras e 1 ou 2 números, como CS1'); end if;
  if length(v_rotulo) < 1 or length(v_rotulo) > 80 then perform privado.invalido('nome da carteira: de 1 a 80 caracteres'); end if;
  insert into public.carteiras (id, rotulo) values (v_id, v_rotulo)
  on conflict (id) do update set rotulo = excluded.rotulo;
end;
$$;

create or replace function privado.admin_auditoria(
  p_desde date default null, p_ate date default null, p_usuario uuid default null,
  p_acao text default null, p_tabela text default null, p_limite integer default 300
)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, acao text, tabela text, registro text, detalhes jsonb)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  return query
    select e.id, e.em, e.usuario_id, p.nome, e.papel, e.acao, e.tabela, e.registro, e.detalhes
      from auditoria.eventos e
      left join public.perfis p on p.id = e.usuario_id
     where (p_desde is null or e.em >= (p_desde::timestamp at time zone 'America/Sao_Paulo'))
       and (p_ate is null or e.em < ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo'))
       and (p_usuario is null or e.usuario_id = p_usuario)
       and (p_acao is null or e.acao = p_acao)
       and (p_tabela is null or e.tabela = p_tabela)
     order by e.em desc, e.id desc
     limit least(greatest(coalesce(p_limite, 300), 1), 1000);
end;
$$;

create or replace function public.admin_alterar_papel(p_usuario uuid, p_papel text, p_escola smallint, p_carteira text, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_alterar_papel(p_usuario, p_papel, p_escola, p_carteira, p_motivo) $$;
create or replace function public.admin_exigir_troca_senha(p_usuario uuid, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_exigir_troca_senha(p_usuario, p_motivo) $$;
create or replace function public.admin_salvar_escola(
  p_id smallint, p_sigla text, p_nome text, p_endereco text, p_telefone text, p_carteira text,
  p_latitude double precision, p_longitude double precision, p_raio smallint, p_ativa boolean
)
returns smallint language sql security invoker set search_path = ''
as $$ select privado.admin_salvar_escola(p_id, p_sigla, p_nome, p_endereco, p_telefone, p_carteira, p_latitude, p_longitude, p_raio, p_ativa) $$;
create or replace function public.admin_salvar_turma(p_escola smallint, p_ano smallint, p_turma text, p_matriculados smallint)
returns integer language sql security invoker set search_path = ''
as $$ select privado.admin_salvar_turma(p_escola, p_ano, p_turma, p_matriculados) $$;
create or replace function public.admin_remover_turma(p_id integer)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_remover_turma(p_id) $$;
create or replace function public.admin_salvar_carteira(p_id text, p_rotulo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.admin_salvar_carteira(p_id, p_rotulo) $$;
create or replace function public.admin_auditoria(
  p_desde date default null, p_ate date default null, p_usuario uuid default null,
  p_acao text default null, p_tabela text default null, p_limite integer default 300
)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, acao text, tabela text, registro text, detalhes jsonb)
language sql stable security invoker set search_path = ''
as $$ select * from privado.admin_auditoria(p_desde, p_ate, p_usuario, p_acao, p_tabela, p_limite) $$;

revoke all on function
  privado.admin_alterar_papel(uuid, text, smallint, text, text), privado.admin_exigir_troca_senha(uuid, text),
  privado.admin_salvar_escola(smallint, text, text, text, text, text, double precision, double precision, smallint, boolean),
  privado.admin_salvar_turma(smallint, smallint, text, smallint), privado.admin_remover_turma(integer),
  privado.admin_salvar_carteira(text, text), privado.admin_auditoria(date, date, uuid, text, text, integer),
  public.admin_alterar_papel(uuid, text, smallint, text, text), public.admin_exigir_troca_senha(uuid, text),
  public.admin_salvar_escola(smallint, text, text, text, text, text, double precision, double precision, smallint, boolean),
  public.admin_salvar_turma(smallint, smallint, text, smallint), public.admin_remover_turma(integer),
  public.admin_salvar_carteira(text, text), public.admin_auditoria(date, date, uuid, text, text, integer)
  from public, anon;
grant execute on function
  privado.admin_alterar_papel(uuid, text, smallint, text, text), privado.admin_exigir_troca_senha(uuid, text),
  privado.admin_salvar_escola(smallint, text, text, text, text, text, double precision, double precision, smallint, boolean),
  privado.admin_salvar_turma(smallint, smallint, text, smallint), privado.admin_remover_turma(integer),
  privado.admin_salvar_carteira(text, text), privado.admin_auditoria(date, date, uuid, text, text, integer),
  public.admin_alterar_papel(uuid, text, smallint, text, text), public.admin_exigir_troca_senha(uuid, text),
  public.admin_salvar_escola(smallint, text, text, text, text, text, double precision, double precision, smallint, boolean),
  public.admin_salvar_turma(smallint, smallint, text, smallint), public.admin_remover_turma(integer),
  public.admin_salvar_carteira(text, text), public.admin_auditoria(date, date, uuid, text, text, integer)
  to authenticated;
