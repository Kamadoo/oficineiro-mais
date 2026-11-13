# Arquitetura

## Visão geral

O Oficineiro+ é um site estático que conversa diretamente com um banco PostgreSQL hospedado no Supabase. Não há servidor de aplicação: as regras de negócio e de acesso ficam no banco, em políticas de Row Level Security e em funções SQL, e duas Edge Functions cuidam do que exige segredo do lado do servidor (autenticação e administração de contas).

## Interface

### Componentes

Cada tela é um arquivo `.dc.html` com três partes:

- **modelo** em HTML com marcações `sc-if`, `sc-for` e interpolação `{{ }}`;
- **estilo** declarado no `<helmet>` do componente;
- **lógica** numa classe JavaScript que estende `DCLogic` e expõe os valores do modelo em `renderVals`.

Os componentes são compostos com `<dc-import name="...">`. O runtime (`vendor/dc-runtime/dc-runtime.js`) é de terceiros; a origem e os ajustes estão em `vendor/README.md`. Ele carrega cada componente sob demanda a partir de `./components/<nome>.dc.html`, compila o modelo e o renderiza com React 18.

Cada perfil é um componente de nível superior (`oficineiro`, `direcao`, `analista`, `coordenador`, `gerente`) que mantém o estado compartilhado, as gavetas, as notificações e as ações que gravam no banco, e entrega a cada tela um objeto `contexto`. As telas (`gerente-contas`, `oficineiro-presenca` etc.) ficam responsáveis apenas pela apresentação e pelos filtros próprios, guardados em memória por tela. O menu lateral e o cabeçalho são componentes comuns a todos os perfis.

### Bibliotecas

| Arquivo | Papel |
| --- | --- |
| `lib/auth.js` | sessão, login, MFA, renovação de token e chamadas às RPC |
| `lib/base.js` | formatação, datas do ciclo, máscaras e utilitários comuns |
| `lib/planilha.js` | leitura e geração de planilhas XLSX sem dependências |
| `lib/notificacoes.js` | central de avisos de cada perfil |
| `lib/aparencia.js` | tema claro e escuro e preferências de exibição |
| `lib/onboarding.js` | leitura das planilhas de onboarding e associação dos registros às escolas |

### Estilo

`src/styles/app.css` concentra as classes utilitárias e os componentes visuais. Todas as cores passam por variáveis CSS, o que permite o tema escuro sem duplicar regras. Classes e variáveis de cor seguem uma escala por família e tom, de 0 (mais claro) a 1000 (mais escuro): `fundo-cinza-20`, `cor-ciano-850`, `borda-cinza-160`; transparências levam o sufixo `-a` com a opacidade (`fundo-branco-a9`). `src/lib/aparencia.js` associa cada tom claro ao equivalente do tema escuro.

## Build

`scripts/build.py` gera `dist/`:

1. Publica cada componente, script, folha de estilo e imagem em `dist/a/` com os 12 primeiros caracteres do SHA-256 no nome, o que permite cache imutável.
2. Monta `window.__resources`, o mapa entre o nome lógico de cada componente e o arquivo publicado, e calcula o hash desse script inline para a CSP.
3. Confere o SHA-256 de cada arquivo de `vendor/` e o Subresource Integrity do React.
4. Embute a fonte Inter localmente, sem requisições a terceiros.
5. Grava `_headers` com CSP, HSTS e demais cabeçalhos de segurança, além de `robots.txt` e manifesto.
6. Recusa a geração se encontrar CPF válido, e-mail fora dos domínios de teste ou nomes de uma base de referência (`scripts/privacy_check.py`).

### Peso e minificação

Os arquivos não são minificados. O site gerado tem cerca de 1,9 MB de texto, dos quais 1,25 MB são componentes; com a compressão que o Cloudflare aplica na entrega, o total cai para perto de 0,5 MB. Cada perfil baixa só os próprios componentes, sob demanda, e todos ficam em cache imutável pelo nome com hash. Minificar exigiria reescrever o JavaScript dentro dos `.dc.html` e o espaço entre elementos dos modelos, que o runtime interpreta como texto, com risco de mudar o resultado na tela para um ganho pequeno depois da compressão.

## Configuração por implantação

`src/config.js`, fora do controle de versão, define o endereço e a chave pública do Supabase e a identidade do órgão cliente (`cliente.orgao`, `cliente.cidade`, `cliente.projeto`), usada no cabeçalho dos documentos oficiais e em Configurações. O logotipo do cliente é `public/brand/logo-cliente.png`; quando a variável `OFICINEIRO_MARCA` aponta para uma pasta com um arquivo de mesmo nome, o build publica esse arquivo no lugar do genérico. Assim o repositório não carrega a marca de nenhum cliente.

## Banco de dados

### Esquemas

| Esquema | Conteúdo |
| --- | --- |
| `public` | tabelas de negócio e invólucros das funções chamadas pelo site |
| `privado` | funções `SECURITY DEFINER` com a lógica sensível, sem acesso direto pela API |
| `auditoria` | registro de alterações por gatilho e registro de atividades |

As funções de `privado` validam o perfil e o escopo de quem chama e sinalizam erros com dois códigos padronizados: `22023` para dados inválidos e `42501` para acesso negado.

### Domínio

- **Presença:** marcações de entrada, almoço e saída com a hora do servidor, aceitas só dentro do raio da escola; ajustes pedidos pelo oficineiro e decididos pela direção.
- **Grade e aulas:** grade padrão por escola com variações por semana, validação pela direção e registro de cada aula ligada à grade.
- **Ciclos:** apuração do dia 21 ao dia 20 para contratos por CNPJ e do dia 1 ao último dia do mês para CPF, com fechamento automático por `pg_cron`.
- **Campo:** agenda e registro de visitas dos analistas, com presença do analista na escola.
- **Contas:** cadastro, desativação, mudança de escola agendada e remoção com anonimização dos registros históricos.

### Migrações e testes

As migrações em `supabase/migrations` são aplicadas em ordem pela CLI do Supabase. Os testes em `supabase/tests/database` usam pgTAP e simulam cada perfil por meio das claims do JWT, cobrindo permissões, regras de negócio e fluxos completos.

## Edge Functions

| Função | Responsabilidade |
| --- | --- |
| `acesso` | login por usuário e senha, primeiro acesso por CPF ou CNPJ com código enviado por e-mail, troca de senha e encerramento das outras sessões |
| `admin-usuarios` | cadastro, desativação, reativação e remoção de contas, respeitando o que cada perfil pode administrar |

Ambas usam a chave de serviço apenas no servidor, aceitam requisições só da origem configurada em `FSM_ORIGEM_PERMITIDA` e compartilham as rotinas de `supabase/functions/_shared`.

## Hospedagem

O site é publicado no Cloudflare Pages a partir de `dist/`. O banco, a autenticação, as funções e as tarefas agendadas ficam no Supabase, na região de São Paulo.
