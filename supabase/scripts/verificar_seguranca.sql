with checagens(ordem, item, ok, detalhe) as (
  select 1, 'Todas as tabelas do FSM existem (20)',
         count(*) = 20, count(*)::text || ' encontradas'
    from pg_tables where schemaname = 'public'
     and tablename in ('carteiras','escolas','perfis','jornada_pessoas','presencas','aulas_registro',
                       'relatorios_mensais','visitas','onboarding_os','onboarding_itens','turmas','grade_aulas','grade_envios','lembretes_registro','mudancas_escola','grade_semanas',
                       'presenca_marcacoes','presenca_tentativas','presenca_ajustes','presenca_sinais')
  union all
  select 2, 'Proteção por linha (RLS) ligada em todas as tabelas do public',
         count(*) filter (where not c.relrowsecurity) = 0,
         coalesce(string_agg(c.relname, ', ') filter (where not c.relrowsecurity), 'nenhuma sem RLS')
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
  union all
  select 3, 'Visitante sem login (anon) não tem acesso a nenhuma tabela',
         count(*) = 0, count(*)::text || ' permissões encontradas'
    from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public'
  union all
  select 4, 'Visitante sem login (anon) não executa funções do FSM',
         count(*) = 0, coalesce(string_agg(distinct routine_schema || '.' || routine_name, ', '), 'nenhuma')
    from information_schema.role_routine_grants g
   where grantee in ('anon', 'PUBLIC') and routine_schema in ('public', 'privado', 'auditoria')
     and not exists (select 1 from pg_proc p join pg_depend d on d.objid = p.oid and d.deptype = 'e'
                      where p.proname = g.routine_name and p.pronamespace = g.routine_schema::regnamespace)
  union all
  select 5, 'CPF, CNPJ/CPF da contratada, usuário e situação da conta ilegíveis pela API',
         count(*) filter (where has_column_privilege('authenticated', format('public.%I', t), c, 'select')) = 0,
         coalesce('legíveis: ' || string_agg(t || '.' || c, ', ') filter (where has_column_privilege('authenticated', format('public.%I', t), c, 'select')), '')
    from (values ('onboarding_itens', 'cpf_cifrado'), ('onboarding_itens', 'cpf_hash'), ('perfis', 'cpf_cifrado'),
                 ('perfis', 'cpf_hash'), ('perfis', 'cpf_mascara'), ('perfis', 'usuario'), ('perfis', 'trocar_senha'), ('perfis', 'telefone'),
                 ('perfis', 'contratada_tipo'), ('perfis', 'contratada_cifrado'), ('perfis', 'contratada_mascara')) x(t, c)
   where exists (select 1 from information_schema.columns ic where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.c)
  union all
  select 6, 'Chaves de criptografia do CPF criadas no Vault (2)',
         count(*) = 2, count(*)::text || ' chaves'
    from vault.secrets where name in ('fsm_cpf_chave', 'fsm_cpf_hmac')
  union all
  select 7, 'Regras de acesso (políticas) instaladas',
         count(*) >= 14, count(*)::text || ' políticas'
    from pg_policies where schemaname = 'public'
  union all
  select 8, 'Auditoria automática ligada nas tabelas de pessoas e fluxos',
         count(distinct event_object_table) >= 10, count(distinct event_object_table)::text || ' tabelas auditadas'
    from information_schema.triggers where trigger_name like 'auditoria%' and event_object_schema = 'public'
  union all
  select 9, 'Auditoria não pode ser alterada nem apagada',
         count(*) = 2, count(*)::text || ' travas'
    from information_schema.triggers where event_object_schema = 'auditoria' and trigger_name like 'eventos_%'
  union all
  select 10, 'Funções protegidas não ficam expostas a quem não está logado',
         bool_and(not has_function_privilege('anon', p.oid, 'execute')),
         coalesce('abertas: ' || string_agg(n.nspname || '.' || p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')),
                  count(*)::text || ' funções conferidas')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'privado', 'auditoria')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select 11, 'Criptografia do CPF funcionando (teste com CPF fictício, nada é gravado)',
         privado.cpf_decifrar(privado.cpf_cifrar('52998224725')) = '52998224725'
         and privado.cpf_normalizado('123.456.789-00') is null, ''
  union all
  select 12, 'Nenhuma função SECURITY DEFINER no schema publicado (alerta 0029 do Advisor)',
         count(*) = 0, coalesce(string_agg(p.proname, ', '), 'nenhuma')
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and has_function_privilege('authenticated', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select 13, 'Funções exclusivas do servidor fechadas para usuário logado',
         count(*) filter (where f is null or has_function_privilege('authenticated', f, 'execute')) = 0,
         coalesce('abertas ou ausentes: ' || string_agg(nome, ', ') filter (where f is null or has_function_privilege('authenticated', f, 'execute')), count(*)::text || ' funções conferidas')
    from (select nome, to_regprocedure(nome) f
            from unnest(array['public.fsm_conta_por_cpf(text)', 'public.fsm_conta_por_usuario(text)', 'public.fsm_definir_cpf(uuid, text)',
                              'public.fsm_tentativa(text, integer, integer)', 'public.fsm_tentativa_zerar(text)', 'public.fsm_registrar_login(uuid)',
                              'public.registrar_acao_admin(uuid, text, text, jsonb)', 'privado.segredo(text)', 'privado.aplicar_mudancas_escola()',
                              'privado.cpf_cifrar(text)', 'privado.cpf_decifrar(bytea)', 'privado.cpf_hash(text)']) nome) x
  union all
  select 14, 'Autenticador exigido de todos os cargos',
         pg_get_functiondef('privado.acesso_ok()'::regprocedure) ~ 'papel_atual\(\) is not null and privado\.mfa_ok\(\)', ''
  union all
  select 15, 'Registro de aula e leitura de perfis exigem o autenticador',
         count(*) = 3, count(*)::text || ' de 3 regras conferidas'
    from pg_policies
   where schemaname = 'public'
     and ((policyname = 'aulas_incluir' and with_check ~ 'acesso_ok')
       or (policyname = 'aulas_alterar' and qual ~ 'acesso_ok' and with_check ~ 'acesso_ok')
       or (policyname = 'perfis_ler' and qual ~ 'mfa_ok'))
  union all
  select 16, 'Contas sem autenticador só existem no projeto de teste',
         count(*) = 0 or exists (select 1 from vault.secrets where name = 'fsm_ambiente_teste'),
         count(*)::text || ' conta(s) sem autenticador'
    from public.perfis where sem_mfa
)
select ordem as "#", item as "Verificação", case when ok then 'OK' else 'FALHA' end as "Resultado", detalhe as "Detalhe"
  from checagens order by ordem;
