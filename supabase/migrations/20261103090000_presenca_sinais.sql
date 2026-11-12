create table if not exists public.presenca_sinais (
  id         bigint generated always as identity primary key,
  ajuste_id  bigint not null references public.presenca_ajustes(id) on delete cascade,
  autor_id   uuid not null references public.perfis(id),
  mensagem   text not null check (length(mensagem) between 5 and 300),
  criado_em  timestamptz not null default now()
);
create index if not exists presenca_sinais_ajuste_idx on public.presenca_sinais (ajuste_id, criado_em desc);
alter table public.presenca_sinais enable row level security;
revoke all on public.presenca_sinais from anon, authenticated;
grant select on public.presenca_sinais to authenticated;
drop policy if exists presenca_sinais_ler on public.presenca_sinais;
create policy presenca_sinais_ler on public.presenca_sinais for select to authenticated
  using ((select privado.papel_atual()) in ('direcao', 'coordenador', 'gerente')
         and exists (select 1 from public.presenca_ajustes a where a.id = ajuste_id and privado.ve_escola(a.escola_id)));
drop trigger if exists auditoria on public.presenca_sinais;
create trigger auditoria after insert or update or delete on public.presenca_sinais
  for each row execute function auditoria.trigger_linha();

create or replace function privado.sinalizar_ajuste(p_id bigint, p_mensagem text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_a public.presenca_ajustes;
  v_msg text := trim(coalesce(p_mensagem, ''));
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'coordenador' then perform privado.negar(); end if;
  select * into v_a from public.presenca_ajustes where id = p_id;
  if v_a.id is null or not privado.ve_escola(v_a.escola_id) then perform privado.invalido('solicitação não encontrada'); end if;
  if v_a.status <> 'em_analise' then perform privado.invalido('esta solicitação já foi analisada pela direção'); end if;
  if length(v_msg) < 5 then perform privado.invalido('escreva uma mensagem para a direção'); end if;
  if exists (select 1 from public.presenca_sinais s where s.ajuste_id = p_id and s.criado_em > now() - interval '1 hour') then
    perform privado.invalido('esta solicitação já foi sinalizada há menos de uma hora');
  end if;
  insert into public.presenca_sinais (ajuste_id, autor_id, mensagem) values (p_id, auth.uid(), left(v_msg, 300));
end;
$$;

create or replace function privado.relatorio_justificativas(p_status text default null, p_de date default null, p_ate date default null)
returns table(id bigint, oficineiro_id uuid, nome text, escola_id smallint, escola text, data date, tipo text,
              entrada time, saida_almoco time, retorno_almoco time, saida time, motivo text, status text,
              pedido_em timestamptz, analisado_em timestamptz, analise_obs text, analisado_nome text,
              sinal_em timestamptz, sinal_msg text, sinal_qtd integer)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente') then perform privado.negar(); end if;
  return query
  select a.id, a.oficineiro_id, o.nome, a.escola_id, e.nome, a.data, a.tipo, a.entrada, a.saida_almoco, a.retorno_almoco,
         a.saida, a.motivo, a.status, a.pedido_em, a.analisado_em, a.analise_obs, d.nome,
         s.criado_em, s.mensagem, coalesce(s.qtd, 0)::integer
    from public.presenca_ajustes a
    join public.perfis o on o.id = a.oficineiro_id
    join public.escolas e on e.id = a.escola_id
    left join public.perfis d on d.id = a.analisado_por
    left join lateral (
      select x.criado_em, x.mensagem, count(*) over () as qtd
        from public.presenca_sinais x
       where x.ajuste_id = a.id
       order by x.criado_em desc limit 1
    ) s on true
   where (p_status is null or a.status = p_status)
     and (p_de is null or a.data >= p_de)
     and (p_ate is null or a.data <= p_ate)
     and privado.ve_escola(a.escola_id)
   order by a.pedido_em desc
   limit case when p_de is null and p_ate is null then 300 else 2000 end;
end;
$$;

revoke all on function privado.sinalizar_ajuste(bigint, text), privado.relatorio_justificativas(text, date, date) from public, anon;
grant execute on function privado.sinalizar_ajuste(bigint, text), privado.relatorio_justificativas(text, date, date) to authenticated;

create or replace function public.sinalizar_ajuste(p_id bigint, p_mensagem text)
returns void language sql security invoker set search_path = ''
as $$ select privado.sinalizar_ajuste(p_id, p_mensagem) $$;

create or replace function public.relatorio_justificativas(p_status text default null, p_de date default null, p_ate date default null)
returns table(id bigint, oficineiro_id uuid, nome text, escola_id smallint, escola text, data date, tipo text,
              entrada time, saida_almoco time, retorno_almoco time, saida time, motivo text, status text,
              pedido_em timestamptz, analisado_em timestamptz, analise_obs text, analisado_nome text,
              sinal_em timestamptz, sinal_msg text, sinal_qtd integer)
language sql stable security invoker set search_path = ''
as $$ select * from privado.relatorio_justificativas(p_status, p_de, p_ate) $$;

revoke all on function public.sinalizar_ajuste(bigint, text), public.relatorio_justificativas(text, date, date) from public, anon;
grant execute on function public.sinalizar_ajuste(bigint, text), public.relatorio_justificativas(text, date, date) to authenticated;
