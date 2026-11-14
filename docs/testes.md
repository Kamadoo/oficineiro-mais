# Testes

O projeto tem seis grupos de verificação. Todos rodam no GitHub Actions a cada push (`.github/workflows/ci.yml`) e podem ser repetidos localmente.

| Grupo | Onde | O que cobre |
| --- | --- | --- |
| Banco | `supabase/tests/database` | 680 asserções pgTAP: regras de negócio, permissões e fluxos de cada perfil |
| Segurança | `tests/security` | auditoria de RLS, matriz de execução das RPC por perfil e tentativas de sair do próprio escopo, comparadas com o resultado esperado versionado |
| Unitários | `tests/unit` | regras puras das bibliotecas de `src/lib` (datas, ciclos, presença, documentos, lote de contas, notificações, geração de planilhas, leitura de planilhas e da OS) |
| Funções de borda | `supabase/functions/tests` | portões de origem, método, sessão, MFA e perfil, validações, respostas que não revelam contas, limite de tentativas e tempo mínimo de resposta |
| Interface | `tests/ui` | as telas, abas e gavetas de todos os perfis nos temas claro e escuro e no celular, com checagem automática de acessibilidade |
| Estático | `eslint.config.js`, `.prettierrc`, `ruff.toml`, `supabase/functions/deno.json` | lint e formatação do JavaScript (bibliotecas e componentes), do Python e das funções de borda |

## Preparação

Requisitos: Node.js 22+, Python 3.12+ e a [CLI do Supabase](https://supabase.com/docs/guides/cli).

```bash
npm install
supabase start
```

A CLI sobe o PostgreSQL local na porta 54322. Os scripts de teste usam as variáveis padrão do `psql` (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`); para o banco da CLI:

```bash
export PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGPASSWORD=postgres
```

## Banco

Os testes pgTAP criam as próprias escolas, carteiras e contas, por isso rodam num banco sem dados de exemplo:

```bash
supabase db reset --no-seed
supabase test db
```

## Segurança

Depois dos testes do banco, carregue os dados fictícios e rode as auditorias:

```bash
psql -d postgres -v ON_ERROR_STOP=1 -q -f supabase/seed.sql
psql -d postgres -v ON_ERROR_STOP=1 -q -f tests/fixtures/dados_teste.sql
python tests/security/rls_audit.py
python tests/security/rpc_matrix.py
python tests/security/scope_audit.py
```

`rls_audit.py` falha se algum perfil lê, altera ou apaga o que não deveria. `rpc_matrix.py` lista, para cada função exposta, os perfis que conseguem executá-la, e `scope_audit.py` tenta acessar outra escola ou carteira, injetar SQL e escalar privilégios. Os dois comparam o resultado com `tests/security/esperado/` e falham em qualquer diferença: uma função nova, ou um perfil que passou a ser aceito ou recusado. Quando a mudança for intencional, regrave o esperado com `GRAVAR_ESPERADO=1` e revise o diff no commit. As mensagens do PostgreSQL são forçadas em inglês (`lc_messages=C`) para que a classificação não dependa do idioma do servidor.

## Unitários

Usam o executor nativo do Node (`node:test`), sem dependências:

```bash
npm test
```

Cada biblioteca é carregada num contexto isolado com um `window` mínimo, como acontece no navegador.

## Interface

A varredura abre o site gerado em `dist/` com o Chromium do Playwright, entra em cada perfil com as contas fictícias de `tests/fixtures/dados_teste.sql`, percorre todas as telas do menu e falha se uma tela ficar vazia, se houver erro de JavaScript, se alguma chamada ao banco for recusada ou se o axe-core apontar problema de acessibilidade grave ou crítico. As chamadas ao Supabase são atendidas por `tests/ui/postgrest.js`, que traduz as requisições do PostgREST em SQL executado no banco local com as permissões do usuário, sem precisar do serviço de autenticação.

```bash
npx playwright install chromium
cp src/config.example.js src/config.js
npm run build
npm run test:ui
```

Em cada tela, a varredura também abre as abas (`main [role=tab]`) e a primeira gaveta (`button[aria-haspopup="dialog"]`), confere o diálogo com o axe-core e fecha com Esc; depois repete o menu em 390 px, no primeiro tema, reprovando rolagem horizontal. Use `TEMAS=claro` para varrer só um tema, `SO=gerente,oficineiro` para alguns perfis, `ABAS=0` para pular abas e gavetas e `CELULAR=0` para pular o celular.

Os dados fictícios incluem escolas com baixa adoção e sem visita agendada, mais de 40 contas por escola na Jornada do Usuário, mais de 50 contas em Gestão de Contas e aulas registradas até o dia fixado no relógio dos testes (09/11/2026, 10h), para que listas paginadas, sugestões e agendas apareçam.

## Estático

```bash
npm run lint
npm run format:check
ruff check scripts tests
ruff format --check scripts tests
cd supabase/functions && deno fmt --check && deno lint && deno check acesso/index.ts admin-usuarios/index.ts
```

## Funções de borda

```bash
cd supabase/functions && deno test --allow-env --allow-read tests/
```

Os testes carregam cada função com `Deno.serve` e `fetch` substituídos (`tests/apoio.ts`): nenhuma chamada sai para a rede e o Supabase é simulado por rota.

`npm run lint` inclui `scripts/lint_components.js`, que extrai o script de cada `.dc.html` e o passa pelo ESLint e pelo Prettier; `npm run format:components` formata esses scripts.
