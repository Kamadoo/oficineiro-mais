create or replace function privado.escolas_da_jornada()
returns smallint[]
language sql stable security definer set search_path = ''
as $$
  select case
    when not coalesce(privado.acesso_ok(), false) then '{}'::smallint[]
    when privado.papel_atual() in ('gerente', 'coordenador') then array(select e.id from public.escolas e)
    when privado.papel_atual() = 'analista'
      then array(select e.id from public.escolas e where e.carteira_id = privado.carteira_atual())
    else '{}'::smallint[]
  end;
$$;

revoke all on function privado.escolas_da_jornada() from public, anon;
grant execute on function privado.escolas_da_jornada() to authenticated;

drop policy jornada_ler on public.jornada_pessoas;
create policy jornada_ler on public.jornada_pessoas for select to authenticated
  using (escola_id = any (coalesce((select privado.escolas_da_jornada()), '{}'::smallint[])));
