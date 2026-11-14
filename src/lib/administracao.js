window.FSM_ADMINISTRACAO = (() => {
  const Base = window.FSM_BASE;
  const { ANOS, anoTxt } = Base;

  function valoresDoSistema(s, valores) {
    const { NOMES_DE_PERFIL, carteiraPorId, quando } = valores;
    const escolasDoSistema = s.escolasDoSistema || [],
      turmas = s.turmasDoSistema || [],
      carts = s.carteiras || [],
      contasDoSistema = s.contas || [];
    const turmasDe = id => turmas.filter(t => t.escola_id === id);
    const ativas = contasDoSistema.filter(c => c.ativo);
    const escAtivas = escolasDoSistema.filter(e => e.ativa !== false);
    const ACAO = {
      INSERT: 'Inclusão',
      UPDATE: 'Alteração',
      DELETE: 'Exclusão',
      CADASTRAR_USUARIO: 'Conta criada',
      DESATIVAR_USUARIO: 'Conta desativada',
      REATIVAR_USUARIO: 'Conta reativada',
      ADMIN_ALTERAR_PERFIL: 'Perfil alterado pelo administrador',
      ADMIN_EXIGIR_TROCA_SENHA: 'Troca de senha exigida',
      ADMIN_REDEFINIR_AUTENTICADOR: 'Autenticador redefinido',
      ADMIN_VER_EMAIL: 'E-mail consultado',
      ADMIN_ALTERAR_EMAIL: 'E-mail alterado',
      ADMIN_APAGAR_CONTA: 'Conta apagada pelo administrador',
      REMOVER_CONTA: 'Conta removida',
      ADMIN_CORRECAO: 'Correção do administrador',
      REVELAR_CPF: 'CPF completo consultado',
      IMPORTAR_OS: 'Ordem de Serviço importada',
      ACESSO: 'Entrada no site',
      CONSULTA: 'Consulta',
      EXPORTACAO: 'Exportação ou impressão',
      PRESENCA_RECUSADA: 'Presença recusada'
    };
    const TAB = {
      perfis: 'Contas',
      escolas: 'Escolas',
      turmas: 'Turmas',
      carteiras: 'Carteiras',
      presencas: 'Presenças',
      aulas_registro: 'Registros de atividades',
      grade_aulas: 'Grade de atividades',
      grade_envios: 'Envio da grade',
      grade_semanas: 'Semanas da grade',
      lembretes_registro: 'Lembretes de registro',
      mudancas_escola: 'Mudanças de escola',
      relatorios_mensais: 'Relatórios mensais',
      presenca_reaberturas: 'Encerramentos desfeitos',
      onboarding_os: 'Ordens de serviço',
      onboarding_itens: 'Itens de ordem de serviço',
      visitas: 'Visitas',
      configuracoes: 'Configurações do sistema',
      feriados: 'Feriados e recessos'
    };
    const PAPEL_AUD = { ...NOMES_DE_PERFIL, administrador: 'Administrador' };
    const CAMPO = {
      papel: 'Perfil',
      escola_id: 'Escola',
      carteira_id: 'Carteira',
      motivo: 'Motivo',
      ativo: 'Conta ativa',
      ativa: 'Escola ativa',
      trocar_senha: 'Precisa trocar a senha',
      nome: 'Nome',
      usuario: 'Login',
      telefone: 'Telefone',
      sigla: 'Sigla',
      rotulo: 'Nome',
      endereco: 'Endereço',
      raio_m: 'Raio (m)',
      latitude: 'Latitude',
      longitude: 'Longitude',
      posicao_confirmada: 'Localização confirmada',
      matriculados: 'Matriculados',
      jornada_inicio: 'Horário de trabalho',
      fatores: 'Autenticadores removidos',
      cpf: 'CPF (mascarado)',
      inicio: 'Início',
      fim: 'Encerramento',
      lancada: 'Lançada pelo administrador',
      data: 'Data',
      competencia: 'Ciclo',
      status: 'Situação',
      ano_letivo: 'Ano letivo',
      conferencia_status: 'Conferência',
      excedente_status: 'Horas acima do previsto',
      deficit_status: 'Horas abaixo do previsto',
      horario_status: 'Horário de início',
      revisao_status: 'Revisão do registro',
      suporte_email: 'E-mail do suporte',
      suporte_telefone: 'Telefone do suporte',
      suporte_horario: 'Horário do suporte',
      tipo: 'Tipo',
      id: 'Identificador',
      oficineiro_id: 'Oficineiro',
      usuario_id: 'Conta',
      grade_aula_id: 'Atividade da grade',
      criado_em: 'Criado em',
      atualizado_em: 'Atualizado em',
      revisado_em: 'Revisado em',
      revisado_por: 'Revisado por',
      revisao_obs: 'Observação da revisão',
      check_direcao: 'Check da direção',
      check_motivo: 'Motivo do check',
      check_por: 'Check feito por',
      check_em: 'Check feito em',
      fechado_em: 'Fechado em',
      direcao_por: 'Aprovado pela direção',
      direcao_em: 'Aprovado pela direção em',
      coordenacao_por: 'Aprovado pela coordenação',
      coordenacao_em: 'Aprovado pela coordenação em',
      devolvido_por: 'Devolvido por',
      devolvido_em: 'Devolvido em',
      devolvido_papel: 'Devolvido pelo perfil',
      motivo_devolucao: 'Motivo da devolução',
      enviado_em: 'Enviado em',
      enviado_por: 'Enviado por',
      decidido_em: 'Decidido em',
      decidido_por: 'Decidido por',
      conferido_em: 'Conferido em',
      conferido_por: 'Conferido por',
      comentario: 'Comentário',
      situacao: 'Situação',
      conteudo: 'Conteúdo',
      turma: 'Turma',
      solucao: 'Solução',
      componente: 'Componente',
      presentes: 'Presentes',
      conferencia: 'Conferência',
      conferencia_obs: 'Observação da conferência',
      justificativa: 'Justificativa',
      trabalhado_min: 'Minutos trabalhados',
      previsto_min: 'Minutos previstos',
      excedente_min: 'Minutos acima do previsto',
      deficit_min: 'Minutos abaixo do previsto',
      atraso_min: 'Minutos de atraso',
      ano: 'Ano',
      dia_semana: 'Dia da semana'
    };
    const rotCampo = k =>
      CAMPO[k] ||
      String(k)
        .replace(/_id$/, '')
        .replace(/_/g, ' ')
        .replace(/^./, c => c.toUpperCase());
    const ehUuid = v =>
      typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
    const ehData = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
    const ehHora = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}/.test(v);
    const dataHora = (v, seg) => {
      const d = new Date(v);
      if (isNaN(d)) return String(v);
      const o = { timeZone: 'America/Sao_Paulo' };
      return (
        d.toLocaleDateString('pt-BR', { ...o, day: '2-digit', month: '2-digit', year: 'numeric' }) +
        ' às ' +
        d.toLocaleTimeString('pt-BR', {
          ...o,
          hour: '2-digit',
          minute: '2-digit',
          ...(seg ? { second: '2-digit' } : {})
        })
      );
    };
    const nomeConta = id => (contasDoSistema.find(c => c.id === id) || {}).nome;
    const quem = ev =>
      (ev.nome ? ev.nome : ev.usuario_id ? 'Conta removida' : 'Sistema (banco de dados)') +
      (ev.nome && PAPEL_AUD[ev.papel] ? ' · ' + PAPEL_AUD[ev.papel] : '');
    const onde = ev => {
      const tb = TAB[ev.tabela] || ev.tabela || '—';
      if (!ev.registro) return tb;
      const n = ev.tabela === 'perfis' || /^[0-9a-f-]{36}$/.test(ev.registro) ? nomeConta(ev.registro) : null;
      return tb + (n ? ' · ' + n : ' · nº ' + ev.registro);
    };
    const valTxt = (k, v, det) => {
      if (v === null || v === undefined || v === '') return '—';
      if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
      if (k === 'papel') return PAPEL_AUD[v] || String(v);
      const VALS = {
        fechado: 'Fechado',
        devolvido: 'Devolvido',
        aprovado_direcao: 'Aprovado pela direção',
        aprovado_coordenacao: 'Aprovado pela coordenação',
        enviada: 'Enviada',
        validada: 'Validada',
        devolvida: 'Devolvida',
        alterada: 'Alterada',
        ok: 'Confirmada',
        contestada: 'Contestada',
        corrigida: 'Corrigida',
        pendente: 'Pendente',
        conferida: 'Conferida',
        nao_conferida: 'Não conferida',
        dentro: 'Dentro do padrão',
        aguardando: 'Aguardando decisão',
        autorizado: 'Aceito',
        conferido: 'Aceito',
        nao: 'Recusado',
        revisado: 'Revisado',
        corrigido: 'Corrigido',
        anulado: 'Anulado',
        direcao: 'Direção',
        coordenador: 'Coordenação'
      };
      if (/status$|^check_direcao$|^devolvido_papel$/.test(k) && VALS[v]) return VALS[v];
      if (k === 'competencia' && ehData(String(v).slice(0, 10))) {
        const MS = [
          'janeiro',
          'fevereiro',
          'março',
          'abril',
          'maio',
          'junho',
          'julho',
          'agosto',
          'setembro',
          'outubro',
          'novembro',
          'dezembro'
        ];
        return MS[Number(String(v).slice(5, 7)) - 1] + ' de ' + String(v).slice(0, 4);
      }
      if (ehUuid(v)) {
        const n = nomeConta(v);
        return det ? (n ? n + ' · ID ' + v : 'Conta removida ou de outro perfil · ID ' + v) : n || 'Conta removida';
      }
      if (ehHora(v)) return dataHora(v, det);
      if (ehData(v)) return v.slice(8, 10) + '/' + v.slice(5, 7) + '/' + v.slice(0, 4);
      if (k === 'escola_id') {
        const e = escolasDoSistema.find(x => String(x.id) === String(v));
        return e ? e.sigla + ' · ' + e.nome : 'Escola nº ' + v;
      }
      if (k === 'carteira_id') return (carteiraPorId[v] || {}).rotulo || String(v);
      if (typeof v === 'object') return det ? JSON.stringify(v) : 'ver detalhes';
      return String(v);
    };
    const campos = (ev, det) => {
      const d = ev.detalhes;
      if (!d || typeof d !== 'object') return [];
      return Object.keys(d)
        .map(k => {
          const valor = d[k];
          const mudou =
            valor && typeof valor === 'object' && !Array.isArray(valor) && ('de' in valor || 'para' in valor);
          if (mudou && JSON.stringify(valor.de) === JSON.stringify(valor.para)) return null;
          return {
            campo: rotCampo(k),
            texto: mudou ? valTxt(k, valor.de, det) + ' → ' + valTxt(k, valor.para, det) : valTxt(k, valor, det)
          };
        })
        .filter(Boolean);
    };
    const resumo = ev => {
      const c = campos(ev);
      if (!c.length) return '';
      const r = c
        .slice(0, 2)
        .map(x => x.campo + ': ' + x.texto)
        .join(' · ');
      return (r.length > 140 ? r.slice(0, 139) + '…' : r) + (c.length > 2 ? ' · e mais ' + (c.length - 2) : '');
    };
    const audLinha = ev => ({
      quando: quando(ev.em),
      quem: quem(ev),
      acao: ACAO[ev.acao] || ev.acao,
      onde: onde(ev),
      resumo: resumo(ev),
      aria: 'Ver detalhes: ' + (ACAO[ev.acao] || ev.acao) + ' em ' + quando(ev.em),
      abrir: () => this.abrirGavetaDeAdmin({ eventoAberto: ev.id }, 'adm-ev-titulo')
    });
    const ev = s.eventoAberto ? (s.auditoria || []).find(x => x.id === s.eventoAberto) : null;
    const escolaEditada = s.escolaEditada;
    const definirNaEscola = k => e =>
      this.setState({
        escolaEditada: { ...this.state.escolaEditada, [k]: k === 'ativa' ? e.target.checked : e.target.value }
      });
    const cart = s.carteiraEditada;
    const definirNaCarteira = k => e =>
      this.setState({ carteiraEditada: { ...this.state.carteiraEditada, [k]: e.target.value } });
    const novaTurma = s.novaTurma || {};
    const definirNaTurma = k => e => this.setState({ novaTurma: { ...this.state.novaTurma, [k]: e.target.value } });
    const contaAdministrada = s.contaAberta ? contasDoSistema.find(c => c.id === s.contaAberta) : null;
    const acaoDeAdmin = s.acaoDeAdmin || {};
    const papelDaAcao = contaAdministrada ? acaoDeAdmin.papel || contaAdministrada.papel : '',
      escolaDaAcao = contaAdministrada
        ? acaoDeAdmin.escola != null
          ? acaoDeAdmin.escola
          : contaAdministrada.escola_id
            ? String(contaAdministrada.escola_id)
            : ''
        : '',
      carteiraDaAcao = contaAdministrada
        ? acaoDeAdmin.carteira != null
          ? acaoDeAdmin.carteira
          : contaAdministrada.carteira_id || ''
        : '';
    const acaoMudou =
      !!contaAdministrada &&
      (papelDaAcao !== contaAdministrada.papel ||
        ((papelDaAcao === 'oficineiro' || papelDaAcao === 'direcao') &&
          escolaDaAcao !== String(contaAdministrada.escola_id || '')) ||
        (papelDaAcao === 'analista' && carteiraDaAcao !== (contaAdministrada.carteira_id || '')));
    const definirNaAcao = k => e =>
      this.setState({ acaoDeAdmin: { ...this.state.acaoDeAdmin, [k]: e.target.value }, erroConta: '' });
    const minTxt = m => (m == null ? '—' : Math.floor(m / 60) + 'h' + String(m % 60).padStart(2, '0'));
    const dmIso = Base.dmIso;
    const dmaIso = d => (d ? dmIso(d) + '/' + String(d).slice(0, 4) : '');
    const hojeSP = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' });
    const dadosDaConsulta = s.dadosDaConsulta,
      perfilDaConsulta = (dadosDaConsulta && dadosDaConsulta.perfil) || null;
    const presencaEditada = s.presencaEditada;
    const definirNaPresenca = k => e =>
      this.setState({ presencaEditada: { ...this.state.presencaEditada, [k]: e.target.value }, erroDaGaveta: '' });
    const presencaAtual =
      presencaEditada && !presencaEditada.nova && dadosDaConsulta
        ? (dadosDaConsulta.presencas || []).find(x => x.id === presencaEditada.id)
        : null;
    return {
      ACAO,
      PAPEL_AUD,
      acaoDeAdmin,
      carteiraDaAcao,
      escolaDaAcao,
      acaoMudou,
      papelDaAcao,
      definirNaAcao,
      ativas,
      audLinha,
      campos,
      cart,
      definirNaCarteira,
      carts,
      dadosDaConsulta,
      perfilDaConsulta,
      contaAdministrada,
      contasDoSistema,
      dataHora,
      dmIso,
      dmaIso,
      ehUuid,
      escolaEditada,
      escAtivas,
      definirNaEscola,
      escs: escolasDoSistema,
      ev,
      hojeSP,
      minTxt,
      onde,
      presencaAtual,
      definirNaPresenca,
      presencaEditada,
      quem,
      novaTurma,
      definirNaTurma,
      turmas,
      turmasDe
    };
  }

  function chavesDaAdministracao(s, valores) {
    const {
      ACAO,
      acaoDeAdmin,
      carteiraDaAcao,
      escolaDaAcao,
      acaoMudou,
      papelDaAcao,
      definirNaAcao,
      campos,
      cart,
      definirNaCarteira,
      carts,
      perfilDaConsulta,
      contaAdministrada,
      dataHora,
      dmaIso,
      ehUuid,
      escolaEditada,
      escAtivas,
      definirNaEscola,
      ev,
      hojeSP,
      minTxt,
      onde,
      presencaAtual,
      definirNaPresenca,
      presencaEditada,
      quem,
      novaTurma,
      definirNaTurma,
      turmasDe
    } = valores;
    return {
      ehAdmin: !!s.ehAdmin,
      ...(s.ehAdmin
        ? {
            escolaAberta: !!escolaEditada,
            admEscNova: !!escolaEditada && !escolaEditada.id,
            escolaExiste: !!(escolaEditada && escolaEditada.id),
            escolaTitulo: escolaEditada ? (escolaEditada.id ? escolaEditada.nome || 'Escola' : 'Nova escola') : '',
            escolaEditada: escolaEditada
              ? {
                  ...escolaEditada,
                  escreverSigla: definirNaEscola('sigla'),
                  escreverNome: definirNaEscola('nome'),
                  escreverEndereco: definirNaEscola('endereco'),
                  escreverTelefone: definirNaEscola('telefone'),
                  escolherCarteira: definirNaEscola('carteira_id'),
                  escreverLatitude: definirNaEscola('latitude'),
                  escreverLongitude: definirNaEscola('longitude'),
                  escreverRaio: definirNaEscola('raio_m'),
                  marcarAtiva: definirNaEscola('ativa')
                }
              : {},
            opcoesDeCarteira: carts.map(c => ({ valor: c.id, rotulo: c.rotulo })),
            salvarEscola: () => this.salvarEscola(),
            escolaBotao: s.salvandoSistema
              ? 'Salvando…'
              : escolaEditada && escolaEditada.id
                ? 'Salvar alterações'
                : 'Cadastrar escola',
            turmas:
              escolaEditada && escolaEditada.id
                ? turmasDe(escolaEditada.id).map(t => {
                    const raio =
                      s.turmasEditadas[t.id] != null
                        ? s.turmasEditadas[t.id]
                        : t.matriculados == null
                          ? ''
                          : String(t.matriculados);
                    return {
                      nome: anoTxt(t.ano) + (t.turma ? ' · Turma ' + t.turma : ''),
                      matriculados: raio,
                      aria: 'Matriculados de ' + anoTxt(t.ano) + (t.turma ? ' turma ' + t.turma : ''),
                      escreverMatriculados: e =>
                        this.setState({ turmasEditadas: { ...this.state.turmasEditadas, [t.id]: e.target.value } }),
                      mudou: raio !== (t.matriculados == null ? '' : String(t.matriculados)),
                      salvar: () => this.salvarTurma({ id: t.id, ano: t.ano, turma: t.turma, matr: raio }),
                      remover: () => this.removerTurma(t),
                      removerTexto: s.turmaARemover === t.id ? 'Confirmar remoção' : 'Remover',
                      removerCor: s.turmaARemover === t.id ? 'var(--destaque-branco)' : 'var(--texto-vermelho-600)',
                      removerClasse: s.turmaARemover === t.id ? '' : 'fundo-branco',
                      removerFundo: s.turmaARemover === t.id ? 'var(--destaque-vermelho-600)' : 'var(--fundo-branco)'
                    };
                  })
                : [],
            semTurmas: !!(escolaEditada && escolaEditada.id && !turmasDe(escolaEditada.id).length),
            novaTurma: {
              ...novaTurma,
              escolherAno: definirNaTurma('ano'),
              escreverTurma: definirNaTurma('turma'),
              escreverMatriculados: definirNaTurma('matr')
            },
            opcoesDeAno: ANOS.map(a => ({ valor: String(a), rotulo: anoTxt(a) })),
            incluirTurma: () => this.salvarTurma({ ano: novaTurma.ano, turma: novaTurma.turma, matr: novaTurma.matr }),
            carteiraAberta: !!cart,
            carteiraNova: !!(cart && cart.nova),
            carteiraEditada: cart
              ? {
                  ...cart,
                  titulo: cart.rotulo || cart.id || 'Nova carteira',
                  escreverCodigo: definirNaCarteira('id'),
                  escreverRotulo: definirNaCarteira('rotulo')
                }
              : {},
            salvarCarteira: () => this.salvarCarteira(),
            carteiraBotao: s.salvandoSistema
              ? 'Salvando…'
              : cart && cart.nova
                ? 'Cadastrar carteira'
                : 'Salvar alterações',
            registroAberto: !!ev,
            registro: ev
              ? {
                  titulo: ACAO[ev.acao] || ev.acao,
                  itens: [
                    ['Quando', dataHora(ev.em, true) + ' (horário de Brasília)'],
                    ['Quem', quem(ev)],
                    ['ID da conta', ev.usuario_id || '—'],
                    ['Onde', onde(ev)],
                    ['Registro alterado', ev.registro ? (ehUuid(ev.registro) ? 'ID ' : 'nº ') + ev.registro : '—'],
                    ['Código do evento', String(ev.id)]
                  ].map(([l, v]) => ({ rotulo: l, valor: v })),
                  campos: campos(ev, true),
                  semCampos: !campos(ev, true).length
                }
              : {},
            presencaAberta: !!presencaEditada,
            presencaEditada: presencaEditada
              ? {
                  ...presencaEditada,
                  pessoa: perfilDaConsulta ? perfilDaConsulta.nome : '',
                  titulo: presencaEditada.nova ? 'Lançar presença' : 'Presença de ' + dmaIso(presencaEditada.data),
                  max: hojeSP,
                  escreverMotivo: definirNaPresenca('motivo'),
                  escolherData: definirNaPresenca('data'),
                  escreverInicio: definirNaPresenca('ini'),
                  escreverFim: definirNaPresenca('fim'),
                  salvarHorarios: () => this.salvarHorariosPresenca(),
                  botao: s.salvandoSistema ? 'Salvando…' : presencaEditada.nova ? 'Lançar presença' : 'Salvar horários',
                  existe: !presencaEditada.nova && !!presencaAtual,
                  resumo: presencaAtual
                    ? 'Trabalhado ' + minTxt(presencaAtual.trabalhado_min) + ' · limite de 8h por dia'
                    : ''
                }
              : {},
            fecharGaveta: () => this.fecharGavetaDeAdmin(),
            erroGaveta: s.erroDaGaveta,
            temErroGaveta: !!s.erroDaGaveta,
            salvando: !!s.salvandoSistema,
            temAdministracao: !!(
              contaAdministrada &&
              !contaAdministrada.eu &&
              contaAdministrada.papel !== 'administrador'
            ),
            administracao: contaAdministrada
              ? {
                  motivo: acaoDeAdmin.motivo || '',
                  escreverMotivo: definirNaAcao('motivo'),
                  perfil: papelDaAcao,
                  escolherPerfil: definirNaAcao('papel'),
                  escola: escolaDaAcao,
                  escolherEscola: definirNaAcao('escola'),
                  carteira: carteiraDaAcao,
                  escolherCarteira: definirNaAcao('carteira'),
                  pedeEscola: papelDaAcao === 'oficineiro' || papelDaAcao === 'direcao',
                  pedeCarteira: papelDaAcao === 'analista',
                  mudou: acaoMudou,
                  salvarPerfil: () => this.executarAcaoDeConta(contaAdministrada, 'papel'),
                  podeExigirSenha:
                    !!contaAdministrada.usuario && !contaAdministrada.trocar_senha && contaAdministrada.ativo,
                  senhaPendente: !!contaAdministrada.trocar_senha && !!contaAdministrada.usuario,
                  exigirSenha: () => this.executarAcaoDeConta(contaAdministrada, 'senha'),
                  podeRedefinirAutenticador: contaAdministrada.ativo,
                  redefinirAutenticador: () => this.executarAcaoDeConta(contaAdministrada, 'mfa'),
                  nome: contaAdministrada.nome,
                  apagando: !!s.confirmandoRemocao,
                  apagarBotao: s.salvandoConta && s.confirmandoRemocao ? 'Apagando…' : 'Apagar definitivamente',
                  pedirApagar: () =>
                    this.setState({ confirmandoRemocao: true, erroConta: '' }, () => {
                      const b = document.getElementById('ct-adm-apagar-confirma');
                      if (b) b.focus();
                    }),
                  cancelarApagar: () =>
                    this.setState({ confirmandoRemocao: false }, () => {
                      const b = document.getElementById('ct-adm-apagar');
                      if (b) b.focus();
                    }),
                  apagar: () => this.executarAcaoDeConta(contaAdministrada, 'apagar'),
                  ...(() => {
                    const em = s.emailRevelado && s.emailRevelado.id === contaAdministrada.id ? s.emailRevelado : null;
                    const tem = !!(em && em.valor != null);
                    return {
                      emailOculto: !tem,
                      mostrarEmail: tem && !em.editando,
                      editandoEmail: tem && !!em.editando,
                      email: tem ? em.valor || 'Sem e-mail cadastrado' : '',
                      novoEmail: em && em.novo != null ? em.novo : '',
                      carregandoEmail: !!(em && em.carregando),
                      verEmailBotao: em && em.carregando ? 'Carregando…' : 'Mostrar e-mail',
                      salvarEmailBotao: s.salvandoConta && em && em.editando ? 'Salvando…' : 'Salvar e-mail',
                      verEmail: () => this.verEmailDaConta(contaAdministrada),
                      editarEmail: () =>
                        this.setState(
                          { emailRevelado: { ...em, editando: true, novo: em.valor || '' }, erroConta: '' },
                          () => {
                            const el = document.getElementById('ct-adm-email');
                            if (el) el.focus();
                          }
                        ),
                      escreverNovoEmail: e =>
                        this.setState({
                          emailRevelado: { ...this.state.emailRevelado, novo: e.target.value },
                          erroConta: ''
                        }),
                      cancelarEmail: () =>
                        this.setState({ emailRevelado: { ...em, editando: false, novo: null }, erroConta: '' }, () => {
                          const b = document.getElementById('ct-adm-email-alterar');
                          if (b) b.focus();
                        }),
                      salvarEmail: () => this.executarAcaoDeConta(contaAdministrada, 'email')
                    };
                  })()
                }
              : {},
            opcoesDePerfil: [
              ['oficineiro', 'Oficineiro de Inclusão Digital'],
              ['direcao', 'Direção da escola'],
              ['analista', 'Analista'],
              ['coordenador', 'Coordenador'],
              ['gerente', 'Gerente de Projetos']
            ].map(([v, l]) => ({ valor: v, rotulo: l })),
            opcoesDeEscolaAtiva: escAtivas.map(e => ({ valor: String(e.id), rotulo: e.nome }))
          }
        : { temAdministracao: false })
    };
  }

  return { valoresDoSistema, chavesDaAdministracao };
})();
