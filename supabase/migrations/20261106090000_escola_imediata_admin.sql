create or replace function privado.alterar_escola(p_usuario uuid, p_escola smallint, p_vale date, p_motivo text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.perfis;
  v_hoje date := privado.hoje();
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  if p_usuario is null or p_usuario = auth.uid() then perform privado.invalido('não é possível alterar a própria conta'); end if;
  perform privado.aplicar_mudancas_escola();
  select * into v_p from public.perfis where id = p_usuario for update;
  if v_p.id is null or v_p.papel <> 'oficineiro' or not v_p.ativo then perform privado.invalido('somente contas ativas de oficineiro mudam de escola'); end if;
  if not exists (select 1 from public.escolas where id = p_escola and ativa) then perform privado.invalido('escola não encontrada'); end if;
  if p_escola = v_p.escola_id then perform privado.invalido('o oficineiro já atua nesta escola'); end if;
  if p_motivo is null or p_motivo not in ('Remanejamento do núcleo', 'Solicitação da SEMED', 'Ampliação de atendimento', 'Outro') then
    perform privado.invalido('escolha o motivo da alteração');
  end if;
  if p_vale is null or p_vale < v_hoje or p_vale > v_hoje + 180 then perform privado.invalido('a data precisa ser de hoje até 6 meses à frente'); end if;
  if p_vale = v_hoje and not privado.eh_admin() then perform privado.invalido('a mudança vale a partir do próximo dia; só o Administrador aplica na hora'); end if;
  update public.mudancas_escola set cancelada_em = now()
   where usuario_id = p_usuario and aplicada_em is null and cancelada_em is null;
  insert into public.mudancas_escola (usuario_id, escola_anterior, escola_nova, vale_a_partir, motivo, criado_por)
  values (p_usuario, v_p.escola_id, p_escola, p_vale, p_motivo, auth.uid());
  if p_vale <= v_hoje then
    perform privado.aplicar_mudancas_escola();
    return 'aplicada';
  end if;
  return 'agendada';
end;
$$;
