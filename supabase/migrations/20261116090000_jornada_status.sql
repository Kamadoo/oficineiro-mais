create table if not exists public.jornada_escola_status (
  id            bigint generated always as identity primary key,
  escola_id     smallint not null references public.escolas (id),
  status        text not null check (status in ('sem_acao', 'acao_planejada', 'em_execucao', 'acompanhando', 'concluida', 'bloqueada')),
  acao          text check (length(acao) <= 1000),
  proximo_passo text check (length(proximo_passo) <= 500),
  prazo         date,
  base_ref      date,
  autor_id      uuid references public.perfis (id) on delete set null,
  autor_nome    text not null check (length(autor_nome) between 1 and 120),
  criado_em     timestamptz not null default now()
);
create index if not exists jornada_escola_status_escola on public.jornada_escola_status (escola_id, criado_em desc);

create table if not exists public.jornada_carteira_status (
  id          bigint generated always as identity primary key,
  carteira_id text not null references public.carteiras (id),
  status      text not null check (status in ('em_dia', 'atencao', 'critico')),
  resumo      text not null check (length(resumo) between 3 and 2000),
  base_ref    date,
  autor_id    uuid references public.perfis (id) on delete set null,
  autor_nome  text not null check (length(autor_nome) between 1 and 120),
  criado_em   timestamptz not null default now()
);
create index if not exists jornada_carteira_status_carteira on public.jornada_carteira_status (carteira_id, criado_em desc);

alter table public.jornada_escola_status enable row level security;
alter table public.jornada_carteira_status enable row level security;
revoke all on table public.jornada_escola_status, public.jornada_carteira_status from public, anon, authenticated;
grant select on table public.jornada_escola_status, public.jornada_carteira_status to authenticated;

drop policy if exists jornada_escola_status_ler on public.jornada_escola_status;
create policy jornada_escola_status_ler on public.jornada_escola_status for select to authenticated
  using ((select privado.papel_atual()) in ('gerente', 'coordenador', 'analista') and privado.ve_escola(escola_id));

drop policy if exists jornada_carteira_status_ler on public.jornada_carteira_status;
create policy jornada_carteira_status_ler on public.jornada_carteira_status for select to authenticated
  using (
    (select privado.acesso_ok())
    and ((select privado.papel_atual()) in ('gerente', 'coordenador')
         or ((select privado.papel_atual()) = 'analista' and carteira_id = (select privado.carteira_atual())))
  );

create or replace function privado.registrar_status_escola(
  p_escola smallint, p_status text, p_acao text, p_proximo_passo text, p_prazo date
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_papel public.papel := privado.papel_atual();
  v_id bigint;
  v_acao text := nullif(btrim(regexp_replace(coalesce(p_acao, ''), '[[:cntrl:]]+', ' ', 'g')), '');
  v_passo text := nullif(btrim(regexp_replace(coalesce(p_proximo_passo, ''), '[[:cntrl:]]+', ' ', 'g')), '');
begin
  if not privado.acesso_ok() or v_papel is null or v_papel not in ('gerente', 'analista')
     or not privado.ve_escola(p_escola) then
    perform privado.negar();
  end if;
  if p_status is null or p_status not in ('sem_acao', 'acao_planejada', 'em_execucao', 'acompanhando', 'concluida', 'bloqueada') then
    perform privado.invalido('status inválido');
  end if;
  if length(v_acao) > 1000 then perform privado.invalido('ação com mais de 1000 caracteres'); end if;
  if length(v_passo) > 500 then perform privado.invalido('próximo passo com mais de 500 caracteres'); end if;
  if p_prazo is not null and (p_prazo < privado.hoje() - 30 or p_prazo > privado.hoje() + 365) then
    perform privado.invalido('prazo fora do intervalo permitido');
  end if;
  insert into public.jornada_escola_status (escola_id, status, acao, proximo_passo, prazo, base_ref, autor_id, autor_nome)
  values (p_escola, p_status, v_acao, v_passo, p_prazo,
          (select max(j.base_ref) from public.jornada_pessoas j where j.escola_id = p_escola),
          auth.uid(), (select p.nome from public.perfis p where p.id = auth.uid()))
  returning id into v_id;
  perform auditoria.registrar('JORNADA_STATUS_ESCOLA', 'jornada_escola_status', v_id::text,
                              jsonb_build_object('escola_id', p_escola, 'status', p_status));
  return v_id;
end;
$$;

create or replace function public.registrar_status_escola(
  p_escola smallint, p_status text, p_acao text default null, p_proximo_passo text default null, p_prazo date default null
)
returns bigint
language sql security invoker set search_path = ''
as $$ select privado.registrar_status_escola(p_escola, p_status, p_acao, p_proximo_passo, p_prazo) $$;

create or replace function privado.registrar_status_carteira(p_carteira text, p_status text, p_resumo text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_papel public.papel := privado.papel_atual();
  v_id bigint;
  v_resumo text := btrim(regexp_replace(coalesce(p_resumo, ''), '[[:cntrl:]]+', ' ', 'g'));
begin
  if not privado.acesso_ok() or v_papel is null
     or not (v_papel = 'gerente' or (v_papel = 'analista' and p_carteira = privado.carteira_atual())) then
    perform privado.negar();
  end if;
  if not exists (select 1 from public.carteiras c where c.id = p_carteira) then
    perform privado.invalido('carteira inexistente');
  end if;
  if p_status is null or p_status not in ('em_dia', 'atencao', 'critico') then
    perform privado.invalido('status inválido');
  end if;
  if length(v_resumo) < 3 then perform privado.invalido('escreva o resumo da semana'); end if;
  if length(v_resumo) > 2000 then perform privado.invalido('resumo com mais de 2000 caracteres'); end if;
  insert into public.jornada_carteira_status (carteira_id, status, resumo, base_ref, autor_id, autor_nome)
  values (p_carteira, p_status, v_resumo,
          (select max(j.base_ref) from public.jornada_pessoas j
             join public.escolas e on e.id = j.escola_id where e.carteira_id = p_carteira),
          auth.uid(), (select p.nome from public.perfis p where p.id = auth.uid()))
  returning id into v_id;
  perform auditoria.registrar('JORNADA_STATUS_CARTEIRA', 'jornada_carteira_status', v_id::text,
                              jsonb_build_object('carteira_id', p_carteira, 'status', p_status));
  return v_id;
end;
$$;

create or replace function public.registrar_status_carteira(p_carteira text, p_status text, p_resumo text)
returns bigint
language sql security invoker set search_path = ''
as $$ select privado.registrar_status_carteira(p_carteira, p_status, p_resumo) $$;

revoke all on function privado.registrar_status_escola(smallint, text, text, text, date),
                       public.registrar_status_escola(smallint, text, text, text, date),
                       privado.registrar_status_carteira(text, text, text),
                       public.registrar_status_carteira(text, text, text)
  from public, anon, authenticated;
grant execute on function privado.registrar_status_escola(smallint, text, text, text, date),
                          public.registrar_status_escola(smallint, text, text, text, date),
                          privado.registrar_status_carteira(text, text, text),
                          public.registrar_status_carteira(text, text, text)
  to authenticated;
