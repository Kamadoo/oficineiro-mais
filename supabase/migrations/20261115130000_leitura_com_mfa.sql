drop policy if exists presenca_ajustes_ler on public.presenca_ajustes;
create policy presenca_ajustes_ler on public.presenca_ajustes for select to authenticated
  using ((select privado.acesso_ok())
         and (oficineiro_id = (select auth.uid())
              or ((select privado.papel_atual()) in ('direcao', 'coordenador', 'gerente') and privado.ve_escola(escola_id))));

drop policy if exists presenca_tentativas_ler on public.presenca_tentativas;
create policy presenca_tentativas_ler on public.presenca_tentativas for select to authenticated
  using ((select privado.acesso_ok())
         and (oficineiro_id = (select auth.uid())
              or ((select privado.papel_atual()) in ('direcao', 'coordenador', 'gerente') and privado.ve_escola(escola_id))));

drop policy if exists espelho_assinaturas_ler on public.espelho_assinaturas;
create policy espelho_assinaturas_ler on public.espelho_assinaturas for select to authenticated
  using ((select privado.acesso_ok())
         and (oficineiro_id = (select auth.uid())
              or (select privado.papel_atual()) in ('coordenador', 'gerente')
              or ((select privado.papel_atual()) = 'direcao'
                  and exists (select 1 from public.perfis p
                               where p.id = espelho_assinaturas.oficineiro_id and privado.ve_escola(p.escola_id)))));
