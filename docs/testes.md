# Testes

O projeto tem cinco grupos de verificação. Todos rodam no GitHub Actions a cada push (`.github/workflows/ci.yml`) e podem ser repetidos localmente.

| Grupo | Onde | O que cobre |
| --- | --- | --- |
| Banco | `supabase/tests/database` | 664 asserções pgTAP: regras de negócio, permissões e fluxos de cada perfil |
| Segurança | `tests/security` | auditoria de RLS, matriz de execução das RPC por perfil e tentativas de sair do próprio escopo |
| Unitários | `tests/unit` | regras puras das bibliotecas de `src/lib` (datas, ciclos, presença, documentos, lote de contas, notificações) |
| Interface | `tests/ui` | as telas de todos os perfis nos temas claro e escuro, com checagem automática de acessibilidade |
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

`rls_audit.py` falha se algum perfil lê, altera ou apaga o que não deveria. `rpc_matrix.py` lista, para cada função exposta, os perfis que conseguem executá-la, e `scope_audit.py` tenta acessar outra escola ou carteira, injetar SQL e escalar privilégios; ambos gravam o resultado em JSON para comparação entre versões.

## Unitários

Usam o executor nativo do Node (`node:test`), sem dependências:

```bash
npm test
```

Cada biblioteca é carregada num contexto isolado com um `window` mínimo, como acontece no navegador.

## Interface

A varredura abre o site gerado em `dist/` com o Chromium do Playwright, entra em cada perfil com as contas fictícias de `tests/fixtures/dados_teste.sql`, percorre todas as telas do menu e falha se uma tela ficar vazia, se houver erro de JavaScript, se alguma chamada ao banco for recusada ou se o axe-core apontar problema de acessibilidade grave ou crítico. Rótulos acessíveis que não repetem o texto visível (`label-content-name-mismatch`, comuns nos cartões da agenda e da grade, cujo rótulo é um resumo do conteúdo) aparecem como aviso, sem reprovar a varredura. As chamadas ao Supabase são atendidas por `tests/ui/postgrest.js`, que traduz as requisições do PostgREST em SQL executado no banco local com as permissões do usuário, sem precisar do serviço de autenticação.

```bash
npx playwright install chromium
cp src/config.example.js src/config.js
npm run build
npm run test:ui
```

Use `TEMAS=claro` para varrer só um tema.

## Estático

```bash
npm run lint
npm run format:check
ruff check scripts tests
ruff format --check scripts tests
cd supabase/functions && deno fmt --check && deno lint && deno check acesso/index.ts admin-usuarios/index.ts
```

`npm run lint` inclui `scripts/lint_components.js`, que extrai o script de cada `.dc.html` e o passa pelo ESLint e pelo Prettier; `npm run format:components` formata esses scripts.
