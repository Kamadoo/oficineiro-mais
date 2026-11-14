# Operação

Rotinas para publicar, manter e recuperar o Oficineiro+. Os comandos supõem a raiz do repositório como pasta atual, com Python 3.12, Node.js 22 e, quando indicado, a [CLI do Supabase](https://supabase.com/docs/guides/cli) instalada e ligada ao projeto (`supabase link --project-ref <ref>`).

## Publicar uma versão

1. Atualize `version` no `package.json` (versionamento semântico: correção no terceiro número, funcionalidade no segundo, mudança que quebra compatibilidade no primeiro) e registre as mudanças no `CHANGELOG.md`.
2. Rode as verificações: `npm run lint`, `npm run format:check`, `npm test`, `ruff check scripts tests`; para mudanças no banco, os testes pgTAP e a auditoria (ver [testes.md](testes.md)).
3. Gere o site: `python scripts/build.py`. O build lê a versão do `package.json`, mostra-a em Configurações e interrompe a geração se encontrar dado pessoal ou referência não publicada.
4. Crie a tag no commit publicado: `git tag -a v1.1.0 -m "Oficineiro+ 1.1.0"` e `git push origin v1.1.0`.

## Publicar o site

O site é estático e vai para o Cloudflare Pages a partir de `dist/`.

1. Confira se `src/config.js` aponta para o projeto Supabase certo (endereço e chave pública).
2. Gere `dist/` como acima.
3. No painel do Cloudflare Pages, envie o conteúdo de `dist/` como nova implantação (ou use `npx wrangler pages deploy dist --project-name <projeto>`).
4. Abra o site e confira: entrada, login com MFA, uma tela de cada perfil e Configurações › Versão do sistema.

O arquivo `dist/_headers` leva a CSP, que inclui o hash do script inline e o endereço do Supabase: um build com outro `config.js` gera outra CSP. Os arquivos em `dist/a/` têm hash no nome e cache imutável; `index.html`, `ajuda.html` e `privacidade.html` não têm cache longo.

Para voltar à versão anterior, use "Rollback" na lista de implantações do Cloudflare Pages.

## Aplicar mudanças no banco

As migrações ficam em `supabase/migrations`, em ordem de data. Para aplicar ao projeto:

```bash
supabase db push
```

Sem a CLI, abra o SQL Editor do Supabase e rode, em ordem, os arquivos ainda não aplicados, cada um dentro de `begin; … commit;`. Depois de qualquer migração, rode `supabase/scripts/verificar_seguranca.sql` e confira que todas as linhas saem com `ok = true`.

Nunca edite uma migração já aplicada: crie outra com data posterior.

## Publicar as funções de borda

```bash
supabase functions deploy acesso
supabase functions deploy admin-usuarios
```

As duas funções usam `verify_jwt = false` (a própria função confere a sessão) e precisam do segredo `FSM_ORIGEM_PERMITIDA` com o endereço do site, sem barra no final. Mais de uma origem separada por vírgula:

```bash
supabase secrets set FSM_ORIGEM_PERMITIDA=https://oficineiromais.com.br
```

Pelo painel, em Edge Functions, cole o código de cada `index.ts`; como o painel não resolve importações relativas, o conteúdo de `_shared/seguranca.ts` precisa ir junto no mesmo arquivo.

## Tarefas agendadas

Criadas pelas migrações com `pg_cron` (Database › Cron no painel):

| Tarefa | Horário (UTC) | O que faz |
| --- | --- | --- |
| `fsm-remover-contas-desativadas` | 06:17 | remove ou anonimiza contas desativadas há mais de 30 dias |
| `fsm-limpar-erros-navegador` | 06:41 | apaga erros do navegador com mais de 90 dias |

Para conferir as últimas execuções:

```sql
select jobname, status, start_time, return_message
  from cron.job_run_details join cron.job using (jobid)
 order by start_time desc limit 20;
```

## Cópia de segurança e restauração

O Supabase faz cópias diárias nos planos pagos (Database › Backups); com a recuperação a um ponto no tempo ligada, é possível voltar a qualquer minuto da janela contratada. Além disso, mantenha uma cópia própria, guardada fora do Supabase e com acesso restrito, porque contém dados pessoais:

```bash
supabase db dump --linked -f copia_roles.sql --role-only
supabase db dump --linked -f copia_esquema.sql
supabase db dump --linked -f copia_dados.sql --data-only --use-copy
```

Para restaurar num projeto novo (nunca por cima do projeto em uso sem antes copiá-lo):

1. Crie o projeto na mesma região e rode as migrações (`supabase db push`).
2. Restaure os dados: `psql "<conexão do projeto novo>" -f copia_dados.sql`.
3. Publique as funções, defina `FSM_ORIGEM_PERMITIDA` e confira as tarefas agendadas.
4. Atualize `src/config.js` com o endereço e a chave pública do projeto novo, gere e publique o site.
5. Rode `verificar_seguranca.sql` e entre com uma conta de cada perfil.

Teste a restauração pelo menos uma vez por semestre num projeto de teste.

## Troca de chaves

Troque as chaves quando alguém com acesso sair da equipe, quando houver suspeita de vazamento ou uma vez por ano.

1. **Chave secreta** (`sb_secret_…`, usada só pelas funções de borda): em Project Settings › API Keys, crie uma nova chave secreta, confira que as funções a recebem (a plataforma injeta `SUPABASE_SECRET_KEYS`) e revogue a antiga. Ela nunca vai para o site, para arquivos do repositório ou para mensagens.
2. **Chave pública** (`sb_publishable_…`): crie a nova, troque em `src/config.js`, gere e publique o site, e só então revogue a antiga.
3. **Chave de assinatura das sessões (JWT):** em Project Settings › JWT Keys, faça a rotação; as sessões abertas expiram e cada pessoa entra de novo.
4. **Senha do banco:** em Project Settings › Database; atualize onde ela estiver guardada para as cópias de segurança.

Depois de qualquer troca, entre com uma conta de cada perfil e confira a Auditoria › Erros do navegador.

## Painéis de acompanhamento

Os painéis SQL de acompanhamento (contagens, pendências, conferências) são mantidos fora do repositório público. Rode-os no SQL Editor, sempre em modo de leitura, e nunca copie resultados com dados pessoais para fora do Supabase.

## Retenção dos dados

As regras estão no [aviso de privacidade](../public/privacidade.html): registros do serviço e auditoria por 5 anos depois do fim do ano letivo, erros do navegador por 90 dias (automático), contas desativadas removidas em 30 dias (automático). A exclusão dos registros com mais de 5 anos ainda é manual: no início de cada ano letivo, confira com a coordenação o que venceu antes de apagar ou anonimizar.
