window.FSM_ATIVIDADES = (() => {
  const Base = window.FSM_BASE;
  const { turmaTxt, detTipo, minDeHora } = Base;

  const dataDoIso = iso => {
    const p = String(iso).slice(0, 10).split('-').map(Number);
    return new Date(p[0], p[1] - 1, p[2]);
  };

  const TIPOS_DE_ATIVIDADE = {
    R: { curto: 'Aula regular', fg: 'var(--texto-azul-550)', bg: 'var(--fundo-azul-50)' },
    P: { curto: 'Projeto tempo integral', fg: 'var(--texto-ambar-745)', bg: 'var(--fundo-ambar-80)' },
    F: { curto: 'Formação de professores', fg: 'var(--texto-indigo-510)', bg: 'var(--fundo-indigo-50)' },
    C: { curto: 'Oficina de tecnologia', fg: 'var(--texto-verde-700)', bg: 'var(--fundo-verde-80)' },
    X: { curto: 'Planejamento', fg: 'var(--texto-cinza-600)', bg: 'var(--fundo-cinza-70)' }
  };

  function valoresDasAtividades(s, valores) {
    const { escolaDe, gradePorId, hojeDasAtividades, noFiltroDasAtividades, nomeDoOficineiro, ocorrenciasPendentes } =
      valores;
    const SITUACOES_DA_ATIVIDADE = {
      Realizada: ['var(--texto-verde-760)', 'var(--fundo-verde-80)'],
      'Realizada parcialmente': ['var(--texto-verde-760)', 'var(--fundo-verde-80)'],
      'Não realizada': ['var(--texto-vermelho-600)', 'var(--fundo-vermelho-50)'],
      'Pendente de registro': ['var(--texto-ambar-745)', 'var(--fundo-ambar-80)']
    };
    const REVISOES_DA_ATIVIDADE = {
      revisado: ['Revisado', 'var(--texto-verde-760)', 'var(--fundo-verde-80)'],
      devolvido: ['Devolvido para ajuste', 'var(--texto-vermelho-600)', 'var(--fundo-vermelho-50)'],
      corrigido: ['Corrigido · aguardando revisão', 'var(--texto-azul-640)', 'var(--fundo-azul-40)'],
      anulado: ['Anulado', 'var(--texto-cinza-600)', 'var(--fundo-cinza-70)']
    };
    const temposDeAula = (ini, fim) => Math.max(1, Math.round((minDeHora(fim) - minDeHora(ini)) / 50));
    const linhaDoRegistro = r => {
      const g = r.grade_aula_id ? gradePorId[r.grade_aula_id] : null,
        tp = TIPOS_DE_ATIVIDADE[r.tipo] || TIPOS_DE_ATIVIDADE.R,
        dt = new Date(r.data + 'T12:00:00');
      const situacao = SITUACOES_DA_ATIVIDADE[r.situacao] || SITUACOES_DA_ATIVIDADE['Realizada'],
        rv = REVISOES_DA_ATIVIDADE[r.revisao_status],
        acaoDeRevisao = s.acoesDeRevisao[r.id] || {};
      const realizou = r.situacao !== 'Não realizada',
        nome = nomeDoOficineiro(r.oficineiro_id),
        quando = Base.dm(dt) + ' às ' + String(r.inicio).slice(0, 5);
      const oc =
        r.situacao === 'Não realizada'
          ? String(r.motivo || '').split(' · ')[0]
          : r.mudanca
            ? 'Mudança: ' + r.mudanca
            : '';
      const decidido =
        r.revisao_status === 'revisado' || r.revisao_status === 'devolvido' || r.revisao_status === 'anulado';
      const modo = acaoDeRevisao.modo || '';
      return {
        key: 'r' + r.id,
        id: r.id,
        iso: r.data,
        oficineiro_id: r.oficineiro_id,
        escola_id: r.escola_id,
        pend: false,
        reg: r,
        data: Base.dm(dt),
        oficineiro: nome,
        escola: escolaDe(r.escola_id),
        escolaNome: escolaDe(r.escola_id),
        tipo: tp.curto,
        tipoCor: tp.fg,
        tipoFundo: tp.bg,
        professor: r.professor_aula
          ? 'Prof.: ' + r.professor_aula + ' (substituição)'
          : g && g.professor
            ? 'Prof.: ' + g.professor
            : '',
        turma: r.turma,
        horario: String(r.inicio).slice(0, 5) + '–' + String(r.fim).slice(0, 5),
        solucao: [r.tipo === 'R' ? r.componente : '', detTipo(r) || detTipo(g)].filter(Boolean).join(' · ') || '—',
        presentesMatriculados:
          realizou && r.presentes != null ? r.presentes + (r.matriculados ? '/' + r.matriculados : '') : '—',
        situacao: r.situacao === 'Realizada parcialmente' ? 'Realizada parcialmente' : r.situacao,
        situacaoCor: situacao[0],
        situacaoFundo: situacao[1],
        ocorrencia: oc,
        temOcorrencia: !!oc,
        temRevisao: !!rv,
        revisao: rv ? rv[0] : '',
        revisaoCor: rv ? rv[1] : '',
        revisaoFundo: rv ? rv[2] : '',
        revisaoObservacao: r.revisao_obs ? 'Comentário: ' + r.revisao_obs : '',
        temRevisaoObservacao: !!r.revisao_obs,
        engajamento: realizou && r.engajamento ? r.engajamento + '/5' : '—',
        engajamentoTitulo:
          realizou && r.engajamento
            ? 'Engajamento ' +
              r.engajamento +
              ' de 5 · ' +
              ['', 'Muito baixo', 'Baixo', 'Médio', 'Alto', 'Muito alto'][r.engajamento]
            : 'Sem nota de engajamento',
        evidencia: '—',
        tempos: realizou && r.revisao_status !== 'anulado' ? temposDeAula(r.inicio, r.fim) : 0,
        presentes: realizou && r.revisao_status !== 'anulado' ? r.presentes || 0 : 0,
        temAcoes: !decidido && !modo,
        decidido: decidido && !modo,
        painelAberto: !!modo,
        painelTexto:
          modo === 'devolvido'
            ? 'Devolver para ajuste: o oficineiro volta a poder editar este registro.'
            : 'Anular: o registro deixa de contar como atividade realizada.',
        painelBotao: acaoDeRevisao.salvando
          ? 'Salvando…'
          : modo === 'devolvido'
            ? 'Confirmar devolução'
            : 'Confirmar anulação',
        comentario: acaoDeRevisao.coment || '',
        escreverComentario: e => this.mudarAcaoDeRevisao(r.id, { coment: e.target.value, erro: '' }),
        temErro: !!acaoDeRevisao.erro,
        erro: acaoDeRevisao.erro || '',
        salvando: !!acaoDeRevisao.salvando,
        revisar: () => this.decidirRevisao(r.id, 'revisado'),
        devolver: () => {
          this.mudarAcaoDeRevisao(r.id, { modo: 'devolvido', erro: '' });
          setTimeout(() => {
            const el = document.getElementById('au-coment-' + r.id);
            if (el) el.focus();
          }, 40);
        },
        anular: () => {
          this.mudarAcaoDeRevisao(r.id, { modo: 'anulado', erro: '' });
          setTimeout(() => {
            const el = document.getElementById('au-coment-' + r.id);
            if (el) el.focus();
          }, 40);
        },
        confirmar: () => this.decidirRevisao(r.id, modo),
        cancelar: () =>
          this.setState(st => {
            const n = { ...st.acoesDeRevisao };
            delete n[r.id];
            return { acoesDeRevisao: n };
          }),
        desfazer: () => this.decidirRevisao(r.id, 'aguardando'),
        comentarioId: 'au-coment-' + r.id,
        ariaRevisar: 'Revisado: marcar como revisada a atividade de ' + nome + ', ' + quando,
        ariaDevolver: 'Devolver para ajuste a atividade de ' + nome + ', ' + quando,
        ariaAnular: 'Anular a atividade de ' + nome + ', ' + quando,
        ariaDesfazer: 'Desfazer a decisão sobre a atividade de ' + nome + ', ' + quando
      };
    };
    const linhaDaPendencia = o => {
      const g = o.g,
        tp = TIPOS_DE_ATIVIDADE[g.tipo] || TIPOS_DE_ATIVIDADE.R,
        situacao = SITUACOES_DA_ATIVIDADE['Pendente de registro'];
      return {
        key: 'p' + g.id + o.iso,
        id: null,
        iso: o.iso,
        oficineiro_id: g.oficineiro_id,
        escola_id: g.escola_id,
        pend: true,
        g,
        data: Base.dm(o.d),
        oficineiro: nomeDoOficineiro(g.oficineiro_id),
        escola: escolaDe(g.escola_id),
        escolaNome: escolaDe(g.escola_id),
        tipo: tp.curto,
        tipoCor: tp.fg,
        tipoFundo: tp.bg,
        professor: g.professor ? 'Prof.: ' + g.professor : '',
        turma: turmaTxt(g),
        horario: String(g.inicio).slice(0, 5) + '–' + String(g.fim).slice(0, 5),
        solucao: [g.tipo === 'R' ? g.componente : '', detTipo(g)].filter(Boolean).join(' · ') || '—',
        presentesMatriculados: '—',
        situacao: 'Pendente de registro',
        situacaoCor: situacao[0],
        situacaoFundo: situacao[1],
        ocorrencia: '',
        temOcorrencia: false,
        temRevisao: false,
        revisao: '',
        revisaoCor: '',
        revisaoFundo: '',
        revisaoObservacao: '',
        temRevisaoObservacao: false,
        engajamento: '—',
        engajamentoTitulo: 'Sem registro',
        evidencia: '—',
        tempos: 0,
        presentes: 0,
        temAcoes: false,
        decidido: false,
        painelAberto: false
      };
    };
    const ordemDasAtividades = (x, y) =>
      x.iso < y.iso
        ? 1
        : x.iso > y.iso
          ? -1
          : x.horario.localeCompare(y.horario) || x.oficineiro.localeCompare(y.oficineiro, 'pt-BR');
    const atividades = [
      ...s.registros.filter(noFiltroDasAtividades).map(linhaDoRegistro),
      ...ocorrenciasPendentes.filter(noFiltroDasAtividades).map(linhaDaPendencia)
    ].sort(ordemDasAtividades);
    const oficineirosVisiveis = s.oficineiros.filter(
      o => !s.escolaDasAtividades || String(o.escola_id) === s.escolaDasAtividades
    );
    const oficineiroEscolhido =
      s.oficineiroFiltrado ||
      (oficineirosVisiveis.some(o => o.id === s.oficineiroDasAtividades)
        ? s.oficineiroDasAtividades
        : oficineirosVisiveis[0]
          ? oficineirosVisiveis[0].id
          : '');
    const atividadesDoOficineiro = atividades.filter(r => r.oficineiro_id === oficineiroEscolhido);
    const chaveDaTurma = r => r.oficineiro_id + '|' + r.escola_id + '|' + r.turma;
    const opcoesDeTurma = [];
    const turmasVistas = {};
    atividades
      .filter(r => !r.pend)
      .forEach(r => {
        const k = chaveDaTurma(r);
        if (turmasVistas[k]) return;
        turmasVistas[k] = 1;
        opcoesDeTurma.push({ valor: k, rotulo: r.turma + ' · ' + r.escola + ' · ' + r.oficineiro + ' · ' + r.tipo });
      });
    opcoesDeTurma.sort((x, y) => x.rotulo.localeCompare(y.rotulo, 'pt-BR'));
    const turmaEscolhida = opcoesDeTurma.some(o => o.valor === s.turmaDaLinhaDoTempo)
      ? s.turmaDaLinhaDoTempo
      : opcoesDeTurma[0]
        ? opcoesDeTurma[0].valor
        : '';
    const registrosDaTurma = atividades
      .filter(r => !r.pend && chaveDaTurma(r) === turmaEscolhida)
      .sort((x, y) => (x.iso < y.iso ? -1 : x.iso > y.iso ? 1 : x.horario.localeCompare(y.horario)));
    const OBJETIVOS = {
      Sim: 'objetivo atingido',
      Parcialmente: 'objetivo atingido em parte',
      Não: 'objetivo não atingido'
    };
    const linhaDoTempo = registrosDaTurma.map(r => {
      const x = r.reg,
        nao = x.situacao === 'Não realizada',
        anulada = x.revisao_status === 'anulado';
      const titulo = nao
        ? 'Atividade não realizada'
        : [x.componente || x.oficina, x.atividade].filter(Boolean).join(' · ') || x.solucao || 'Atividade realizada';
      const meta = nao
        ? r.horario
        : [
            r.tempos + (r.tempos === 1 ? ' tempo' : ' tempos'),
            r.horario,
            x.presentes != null ? x.presentes + (x.matriculados ? '/' + x.matriculados : '') + ' presentes' : '',
            x.engajamento ? 'engajamento ' + x.engajamento : '',
            OBJETIVOS[x.objetivo] || ''
          ]
            .filter(Boolean)
            .join(' · ');
      return {
        data: r.data,
        titulo: (anulada ? '[Anulada] ' : '') + titulo,
        texto: nao
          ? 'Motivo: ' + (x.motivo || '—')
          : (x.conteudo || '') + (x.proxima_aula ? ' Próxima atividade: ' + x.proxima_aula : ''),
        detalhe: meta,
        cor: nao ? 'var(--texto-vermelho-600)' : anulada ? 'var(--texto-cinza-420)' : 'var(--texto-verde-700)'
      };
    });
    const tipoDeCicloDe = id => Base.cicloDe((s.oficineiros.find(o => o.id === id) || {}).documento_tipo);
    const noMesmoCiclo = (iso, t) =>
      Base.iso(Base.cicloComp(dataDoIso(iso), t)) === Base.iso(Base.cicloComp(dataDoIso(hojeDasAtividades), t));
    const pendenciasDeRegistro = atividades
      .filter(r => r.pend)
      .map(r => {
        const k = r.g.id + '|' + r.iso,
          lb = s.lembretes.find(l => l.grade_aula_id === r.g.id && l.data === r.iso),
          busy = !!s.enviandoLembrete[k];
        const dias = Math.round((new Date(hojeDasAtividades + 'T12:00:00') - new Date(r.iso + 'T12:00:00')) / 86400000);
        const recente = lb && Date.now() - new Date(lb.enviado_em).getTime() < 20 * 3600000,
          mesOk = noMesmoCiclo(r.iso, tipoDeCicloDe(r.g.oficineiro_id));
        return {
          data: r.data,
          oficineiro: r.oficineiro,
          turma: r.turma,
          escola: r.escola,
          tipo: r.tipo,
          horario: r.horario,
          atraso: dias === 0 ? 'hoje' : dias === 1 ? 'há 1 dia' : 'há ' + dias + ' dias',
          botao: busy
            ? 'Enviando…'
            : !mesOk
              ? 'Ciclo encerrado'
              : recente
                ? 'Lembrete enviado hoje'
                : lb
                  ? 'Enviar de novo'
                  : 'Enviar lembrete',
          info: lb
            ? 'Último lembrete em ' +
              Base.dm(new Date(lb.enviado_em)) +
              ' às ' +
              Base.hm(new Date(lb.enviado_em).getHours() * 60 + new Date(lb.enviado_em).getMinutes())
            : '',
          temInfo: !!lb,
          bloqueado: busy || !mesOk || !!recente,
          aria: 'Enviar lembrete para ' + r.oficineiro + ' registrar a atividade de ' + r.data + ', ' + r.turma,
          podeLembrar: !s.ehAdmin,
          lembrar: () => this.lembrarRegistro(r.g.id, r.iso, r.oficineiro)
        };
      });
    return {
      atividades,
      atividadesDoOficineiro,
      linhaDoTempo,
      oficineiroEscolhido,
      oficineirosVisiveis,
      opcoesDeTurma,
      pendenciasDeRegistro,
      registrosDaTurma,
      temposDeAula,
      turmaEscolhida
    };
  }

  return { dataDoIso, TIPOS_DE_ATIVIDADE, valoresDasAtividades };
})();
