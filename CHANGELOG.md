# Histórico de mudanças

## Próxima versão

### Jornada do Usuário no mês da leitura

- Todos os percentuais usam o mês da data da leitura (dia 1º ao último dia, 4 semanas), com metas proporcionais aos dias já passados enquanto o mês está em andamento.
- Utilização passa a ser "acessou pelo menos 1 vez no mês"; "Sem uso no mês" substitui "sem uso há mais de 30 dias"; engajado é o aluno com 1 acesso por semana (4 no mês) e o professor ou servidor com 3 dias por semana (12 no mês), com o % de engajados sobre os implementados.
- As aulas das turmas vêm da agenda dos oficineiros: aulas previstas no mês, realizadas, execução até a data da leitura e presença na máquina (cada aluno conta no máximo uma vez por aula realizada); turma sem aula lançada aparece como "sem agenda". Substitui o "Aula em 7 dias".
- Semáforo sem "Base pequena": toda escola é Crítico, Atenção ou Em dia, com a execução das aulas abaixo de 60% levando a Atenção; motivos exibidos na ordem das novas regras.
- A aba "Escola e turmas" passa a se chamar "Turmas" e mostra só alunos; a evolução mensal mostra a utilização em % dos implementados, só nos meses com leitura salva.

### Base de acessos diária

- Nova aba do Administrador recebe as planilhas do B.I. como vêm (usuários criados, implementados, dias de acesso e sem acesso por 30, 60, 90 e 120 dias), lê e confere tudo no navegador e mostra a prévia com contagens, unidades novas e conferência entre as planilhas antes de gravar.
- Unidades administrativas sem cadastro entram como unidades da carteira da planilha (AT1), para que ninguém fique de fora; unidades já cadastradas sem carteira recebem a da planilha.
- O banco guarda só nome, perfil, unidade, carteira, turma, responsável, datas e dias de acesso; o login fica apenas como resumo com chave, e e-mail, matrícula e demais colunas não saem do navegador.
- Um retrato por dia: a Jornada do Usuário mostra o mais recente, permite escolher o dia de comparação e monta a evolução mensal pelo último retrato de cada mês; a gravação é só do Administrador com verificação em duas etapas e fica na auditoria.

## 2.0.0 · 23/11/2026

Versão oficial de lançamento: o projeto do Supabase passa a ser o de produção.

### Convites de primeiro acesso

- Nova aba do Administrador lista as contas que aguardam o primeiro acesso, com filtros por cargo, escola, carteira, situação do convite, data de criação e busca por nome ou e-mail, e envia por e-mail o convite que apresenta o sistema e pede o primeiro acesso.
- Seleção uma a uma, das filtradas ou de todas; reenvio só com confirmação; cada envio fica registrado (quem enviou e quando) e na auditoria.
- A criação de contas, individual ou em lote, continua sem enviar e-mail.

### Presença

- Direção (espelho do oficineiro) e Coordenação (Presença na Escola › Por oficineiro) mostram as marcações feitas sem internet e quanto tempo depois chegaram.
- No Relatório Geral do Oficineiro, "Justificar" e "Solicitar ajuste" abrem a tela Presença com o pedido de ajuste já preenchido.

### Documentos

- Cada relatório mensal recebe um código de verificação, impresso no rodapé dos relatórios de presença e de atividades. Qualquer pessoa confere o documento pelo endereço impresso (`#verificar`), sem login; a consulta mostra a situação, o mês, a escola e o nome abreviado.

### Segurança e dados

- Sessão única por conta: um login novo encerra as outras sessões, e o banco recusa as funções chamadas por uma sessão encerrada.
- Justificativas, tentativas de presença e assinaturas do espelho passam a exigir o segundo fator também na leitura das próprias linhas.
- Retenção automática: todo 15 de fevereiro, os registros anteriores a 1º de janeiro de cinco anos atrás são apagados, sem cópia na auditoria; o prazo fica em `configuracoes.retencao_anos` (mínimo 5).

### Entrada

- A tela de entrada mostra só o acesso e o primeiro acesso; o guia rápido fica em Configurações.
- A página declara o idioma português, para leitores de tela.
- O aviso de privacidade saiu do site até a revisão jurídica preencher os dados do controlador e do encarregado; o rascunho enxuto fica em `public/privacidade.html`.
- Link de volta do guia rápido com contraste suficiente sobre o fundo claro.

### Testes

- Dados de teste com onboarding, justificativas, marcações sem internet, presença do analista, históricos de visita e de conferência, mudança de escola agendada e espelho assinado.
- Matriz de permissões cobre as funções do onboarding e a conferência pública.

## 1.1.0 · 14/11/2026

### Presença

- O Oficineiro pode marcar a presença sem internet: a marcação fica guardada no aparelho, com a hora e a localização do momento, e é enviada quando a conexão volta (até 8 horas depois). O banco recusa hora no futuro, anterior à marcação anterior ou com mais de 8 horas, e identifica a marcação como feita sem internet.

### Administração

- Auditoria › Erros do navegador: erros de JavaScript das sessões ficam registrados (com limite por pessoa e sem repetição) e são apagados depois de 90 dias.
- Versão numerada (1.1.0) lida do `package.json` no build e mostrada em Configurações.

### Interface

- Avisos temporários com a mesma duração em todos os perfis.
- Agendas do Gerente com linhas de tabela e nomes acessíveis corretos; tabela de horas do Oficineiro com células identificadas.
- Esc fecha a gaveta de contas em lote do Coordenador; a gaveta de nova carteira tem título.
- Imagem da entrada em WebP e fontes em WOFF2: cerca de 36% menos bytes por tela e entrada cerca de 1,4 s mais rápida em celular com 3G.
- Guia rápido por perfil e aviso de privacidade (rascunho para revisão jurídica), ligados na entrada e em Configurações.

### Correções

- Onboarding: a regra do NTE não confunde mais escolas com "nte" no nome (por exemplo, "Horizonte").
- Código ajustado às regras novas do ESLint 10.

### Testes e documentação

- Dados de teste com escolas de baixa adoção, mais contas e aulas recentes; varredura das telas também nas abas, gavetas e no celular.
- Testes unitários de geração e leitura de planilhas; testes das funções de borda com `deno test`; matriz de permissões das RPC e testes de escopo comparados com o resultado esperado no CI.
- `docs/operacao.md`: publicação, migrações, funções, tarefas agendadas, cópia de segurança, restauração e troca de chaves.

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
