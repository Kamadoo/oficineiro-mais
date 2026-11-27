alter table public.perfis add column if not exists cargo text;

update public.perfis set cargo = 'inclusao_digital' where papel::text = 'oficineiro' and cargo is null;
update public.perfis set cargo = null where papel::text <> 'oficineiro' and cargo is not null;

alter table public.perfis drop constraint if exists perfis_cargo_check;
alter table public.perfis add constraint perfis_cargo_check check (
  (papel::text = 'oficineiro' and cargo in ('inclusao_digital', 'tempo_integral')) or
  (papel::text <> 'oficineiro' and cargo is null)
);

create or replace function privado.ajustar_cargo()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.papel::text = 'oficineiro' then
    new.cargo := coalesce(new.cargo, 'inclusao_digital');
  else
    new.cargo := null;
  end if;
  return new;
end;
$$;
revoke all on function privado.ajustar_cargo() from public, anon, authenticated;

drop trigger if exists ajustar_cargo on public.perfis;
create trigger ajustar_cargo before insert or update of papel, cargo on public.perfis
  for each row execute function privado.ajustar_cargo();

grant select (cargo) on public.perfis to authenticated;

create or replace function privado.cargo_de(p_usuario uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select p.cargo from public.perfis p where p.id = p_usuario;
$$;
revoke all on function privado.cargo_de(uuid) from public, anon;
grant execute on function privado.cargo_de(uuid) to authenticated;

create or replace function privado.conferir_tipo_do_cargo()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.tipo <> 'P' and privado.cargo_de(new.oficineiro_id) = 'tempo_integral' then
    perform privado.invalido('o cargo Oficineiro registra apenas atividades de projeto tempo integral');
  end if;
  return new;
end;
$$;
revoke all on function privado.conferir_tipo_do_cargo() from public, anon, authenticated;

drop trigger if exists conferir_tipo_do_cargo on public.grade_aulas;
create trigger conferir_tipo_do_cargo before insert or update of tipo, oficineiro_id on public.grade_aulas
  for each row execute function privado.conferir_tipo_do_cargo();
drop trigger if exists conferir_tipo_do_cargo on public.grade_semanas;
create trigger conferir_tipo_do_cargo before insert or update of tipo, oficineiro_id on public.grade_semanas
  for each row execute function privado.conferir_tipo_do_cargo();
drop trigger if exists conferir_tipo_do_cargo on public.aulas_registro;
create trigger conferir_tipo_do_cargo before insert or update of tipo, oficineiro_id on public.aulas_registro
  for each row execute function privado.conferir_tipo_do_cargo();

create or replace function privado.alterar_cargo(p_usuario uuid, p_cargo text, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.perfis;
  v_motivo text;
begin
  if not (coalesce(privado.gestor_ok(), false) or privado.eh_admin()) then perform privado.negar(); end if;
  if p_usuario = auth.uid() then perform privado.negar(); end if;
  if p_cargo is null or p_cargo not in ('inclusao_digital', 'tempo_integral') then perform privado.invalido('cargo inválido'); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v from public.perfis where id = p_usuario and removido_em is null for update;
  if v.id is null or v.papel::text <> 'oficineiro' then perform privado.invalido('o cargo só vale para contas de oficineiro'); end if;
  if v.cargo = p_cargo then perform privado.invalido('nada foi alterado'); end if;
  if p_cargo = 'tempo_integral' and exists (
    select 1 from public.grade_aulas g
     where g.oficineiro_id = v.id and g.tipo <> 'P'
       and g.ano_letivo >= extract(year from privado.hoje())::smallint
  ) then
    perform privado.invalido('a grade desta conta tem aulas regulares ou formações de professores; remova-as antes de mudar o cargo');
  end if;
  update public.perfis set cargo = p_cargo where id = v.id;
  perform auditoria.registrar('ALTERAR_CARGO', 'perfis', v.id::text, jsonb_build_object(
    'cargo', jsonb_build_object('de', v.cargo, 'para', p_cargo),
    'motivo', v_motivo));
end;
$$;
revoke all on function privado.alterar_cargo(uuid, text, text) from public, anon;
grant execute on function privado.alterar_cargo(uuid, text, text) to authenticated;

create or replace function public.alterar_cargo(p_usuario uuid, p_cargo text, p_motivo text)
returns void
language sql security invoker set search_path = ''
as $$ select privado.alterar_cargo(p_usuario, p_cargo, p_motivo) $$;
revoke all on function public.alterar_cargo(uuid, text, text) from public, anon;
grant execute on function public.alterar_cargo(uuid, text, text) to authenticated;

create or replace function privado.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'cargo', p.cargo,
    'nome', case when privado.mfa_ok() then p.nome end,
    'usuario', case when privado.mfa_ok() then p.usuario end,
    'escola_id', case when privado.mfa_ok() then p.escola_id end,
    'carteira_id', case when privado.mfa_ok() then p.carteira_id end,
    'jornada_inicio', case when privado.mfa_ok() then to_char(p.jornada_inicio, 'HH24:MI') end,
    'precisa_mfa', not privado.mfa_ok(),
    'precisa_criar_usuario', p.usuario is null,
    'precisa_trocar_senha', p.trocar_senha,
    'acesso_ok', privado.acesso_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;

drop function if exists public.contas_gestao();
drop function if exists privado.contas_gestao();

create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean, desativado_em timestamptz, cargo text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_admin boolean := privado.eh_admin();
  v_todos boolean := privado.eh_admin() or privado.papel_atual() = 'gerente';
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  perform privado.aplicar_mudancas_escola();
  return query
    select p.id, p.nome, p.usuario, p.papel::text, p.escola_id, p.carteira_id, p.ativo,
           (p.usuario is null or p.trocar_senha), p.criado_em, x.acesso_atual, p.telefone,
           m.escola_nova, m.vale_a_partir, m.motivo, p.id = auth.uid(), to_char(p.jornada_inicio, 'HH24:MI'),
           p.trocar_senha, p.desativado_em, p.cargo
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     where p.removido_em is null
       and (v_admin or p.papel::text <> 'administrador')
       and (v_todos or p.papel::text in ('oficineiro', 'direcao') or p.id = auth.uid())
     order by p.nome;
end;
$$;

create or replace function public.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean, desativado_em timestamptz, cargo text)
language sql security invoker set search_path = ''
as $$ select * from privado.contas_gestao() $$;

revoke all on function privado.contas_gestao(), public.contas_gestao() from public, anon;
grant execute on function privado.contas_gestao(), public.contas_gestao() to authenticated;

drop function if exists public.convites_pendentes();
drop function if exists privado.convites_pendentes();

create or replace function privado.convites_pendentes()
returns table (id uuid, nome text, email text, papel text, escola_id smallint, escola text, carteira_id text,
               criado_em timestamptz, envios integer, ultimo_envio timestamptz, situacao text, ultimo_por text,
               ultima_tentativa timestamptz, cargo text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not coalesce(privado.eh_admin(), false) then perform privado.negar(); end if;
  return query
    select p.id, p.nome, u.email::text, p.papel::text, p.escola_id, e.nome, coalesce(p.carteira_id, e.carteira_id),
           p.criado_em, coalesce(c.n, 0)::integer, c.ultimo,
           case
             when l.situacao is null then 'nunca'
             when l.situacao = 'enviando' and l.criado_em < now() - interval '15 minutes' then 'falhou'
             else l.situacao
           end,
           a.nome, coalesce(l.enviado_em, l.criado_em), p.cargo
      from public.perfis p
      join auth.users u on u.id = p.id
      left join public.escolas e on e.id = p.escola_id
      left join lateral (
        select count(*) as n, max(k.enviado_em) as ultimo
          from privado.convites k
         where k.usuario_id = p.id and k.situacao = 'enviado') c on true
      left join lateral (
        select k.situacao, k.criado_em, k.enviado_em, k.enviado_por
          from privado.convites k
         where k.usuario_id = p.id
         order by k.criado_em desc, k.id desc
         limit 1) l on true
      left join public.perfis a on a.id = l.enviado_por
     where p.removido_em is null and p.ativo and p.papel::text <> 'administrador'
       and (p.usuario is null or p.trocar_senha)
     order by p.nome;
end;
$$;

create or replace function public.convites_pendentes()
returns table (id uuid, nome text, email text, papel text, escola_id smallint, escola text, carteira_id text,
               criado_em timestamptz, envios integer, ultimo_envio timestamptz, situacao text, ultimo_por text,
               ultima_tentativa timestamptz, cargo text)
language sql stable security invoker set search_path = ''
as $$ select * from privado.convites_pendentes() $$;

revoke all on function privado.convites_pendentes(), public.convites_pendentes() from public, anon;
grant execute on function privado.convites_pendentes(), public.convites_pendentes() to authenticated;
