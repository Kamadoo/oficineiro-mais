# Histórico de mudanças

## 13/11/2026 (tarde)

### Agendas do Gerente

- Cartões das agendas com o nome da escola, e não só a sigla; aulas do oficineiro com tipo e solução da grade.
- Agenda dos oficineiros na tela Oficineiros, em aba própria e com semana independente; Analistas › Agendas mostra só os analistas.
- Exportação para Excel das duas agendas e aviso quando a semana não tem visitas ou atividades.
- Legenda da agenda dos oficineiros com quadrados visíveis.

### Interface

- Nome da escola no lugar da sigla sozinha em Atividades, Produtividade e Adoção.
- Cartões com conteúdo (agenda, grade, registro, Visão geral, Produtividade, Início da Direção) têm como nome acessível o próprio texto; os botões de ação têm rótulo que começa pelo texto visível. A varredura de acessibilidade passa a reprovar rótulos que não contêm o texto visível.
- Bordas, fundos e textos que repetiam cores da paleta passam a acompanhar o tema escuro; botões e cores de marca seguem fixos.

## 13/11/2026

### Organização do código

- Runtime de componentes movido para `vendor/dc-runtime/`, com origem, ajustes e hash conferido no build.
- Regras repetidas entre perfis levadas para `src/lib`: presença válida e limite diário, sino de notificações, carregamento do mapa, detalhamento do lote de contas, estilos de opção e de abas.
- Telas de Jornada do Usuário do Analista e do Gerente unidas num componente com propriedade de perfil.
- Gavetas de contas, de notificações e de cada perfil separadas em componentes próprios; CSS da página de entrada em `src/styles/entrada.css`. Os perfis ficaram cerca de 27% menores.
- Cores fixas fora da paleta trocadas por variáveis `--destaque-*`; estilos inline fixos trocados por classes.
- Nomes curtos substituídos por nomes descritivos nos perfis e nas telas; linhas longas dos modelos quebradas.
- Números soltos em constantes nomeadas (limite diário, almoço, duração do aviso, tamanho do lote).
- Falhas de impressão e de carregamento das turmas passam a avisar o usuário.
- Seta dos campos de seleção corrigida: o SVG perdia o `viewBox` quando o CSS da entrada estava embutido na página.
- Acessibilidade: contraste dos selos âmbar e índigo e do botão bloqueado, rótulos dos filtros do Onboarding, regiões roláveis focáveis, tabela do Relatório Geral com células, rótulos acessíveis que começam pelo texto visível nos botões de ação.

### Qualidade

- ESLint e Prettier no script de cada componente (`scripts/lint_components.js`).
- Testes unitários das bibliotecas com `node:test`.
- Varredura das telas com Playwright e checagem de acessibilidade com axe-core.
- Ruff nos scripts Python; `deno fmt`, `deno lint` e `deno check` nas funções de borda.
- Ações do CI fixadas pelo commit, Dependabot e versão fixa da CLI do Supabase.
- Documentação de testes em `docs/testes.md` e resumo em inglês no README.

## 12/11/2026

- Lógica de contas comum ao Coordenador e ao Gerente extraída para `src/lib/contas.js`.
- Métodos de montagem das telas do Coordenador, do Gerente e do Oficineiro divididos por área.
- Classes de cor renomeadas para uma escala por família e tom.
- Capturas de tela com dados fictícios no README.
- Versão inicial do repositório.
