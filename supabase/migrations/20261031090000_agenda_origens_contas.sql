create or replace function privado.agendar_minha_visita(
  p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_e public.escolas; v_id bigint; v_dia text;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  select * into v_e from public.escolas where id = p_escola;
  if v_e.id is null or v_e.ativa is false then perform privado.invalido('escolha uma escola ativa'); end if;
  if not privado.ve_escola(p_escola) then perform privado.invalido('esta escola não é da sua carteira'); end if;
  if p_data is null or p_data < privado.hoje() or p_data > privado.hoje() + 180 then
    perform privado.invalido('escolha uma data entre hoje e os próximos 6 meses');
  end if;
  v_dia := privado.dia_de_visita(p_data);
  if v_dia is not null then perform privado.invalido(v_dia); end if;
  if coalesce(p_origem, '') not in ('mapa_calor', 'demanda', 'analista') then perform privado.invalido('origem da visita inválida'); end if;
  if exists (select 1 from public.visitas_agenda
              where analista_id = auth.uid() and escola_id = p_escola and data = p_data and status = 'agendada') then
    perform privado.invalido('você já tem visita agendada nesta escola neste dia');
  end if;
  insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, orientacao, criada_por)
  values (auth.uid(), p_escola, p_data, p_hora, p_origem,
          nullif(left(trim(coalesce(p_tipo, '')), 80), ''),
          nullif(left(trim(coalesce(p_foco, '')), 120), ''),
          nullif(left(trim(coalesce(p_orientacao, '')), 1000), ''),
          auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean)
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
           p.trocar_senha
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     where (v_admin or p.papel::text <> 'administrador')
       and (v_todos or p.papel::text in ('oficineiro', 'direcao') or p.id = auth.uid())
     order by p.nome;
end;
$$;
