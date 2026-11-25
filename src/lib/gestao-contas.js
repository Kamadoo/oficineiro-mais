window.FSM_GESTAO_CONTAS = (() => {
  const Base = window.FSM_BASE;

  function valoresDasContas(s) {
    const NOMES_DE_PERFIL = {
      oficineiro: 'Oficineiro de Inclusão Digital',
      analista: 'Analista',
      direcao: 'Direção da escola',
      coordenador: 'Coordenador',
      gerente: 'Gerente de Projetos',
      administrador: 'Administrador'
    };
    const escolaPorId = Object.fromEntries((s.escolas || []).map(e => [String(e.id), e]));
    const carteiraPorId = Object.fromEntries((s.carteiras || []).map(c => [c.id, c]));
    const dataBr = v => {
      if (!v) return '';
      const [a, m, d] = String(v).slice(0, 10).split('-');
      return d + '/' + m + '/' + a;
    };
    const quando = v => {
      if (!v) return '';
      const d = new Date(v);
      return isNaN(d)
        ? ''
        : d.toLocaleDateString('pt-BR') +
            ' às ' +
            d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    };
    const nomeDaEscola = id => {
      const e = escolaPorId[String(id)];
      return e ? e.nome : '';
    };
    const atuacaoDaConta = c =>
      c.papel === 'oficineiro' || c.papel === 'direcao'
        ? nomeDaEscola(c.escola_id) || 'Escola não encontrada'
        : c.papel === 'analista'
          ? 'Carteira ' + ((carteiraPorId[c.carteira_id] || {}).rotulo || c.carteira_id || '')
          : 'Toda a rede';
    const situacaoDaConta = c => (!c.ativo ? 'desativada' : c.primeiro_acesso ? 'primeiro' : 'ativa');
    const SITUACOES_DE_CONTA = {
      ativa: ['Ativo', 'var(--texto-verde-700)', 'var(--fundo-verde-80)'],
      primeiro: ['Aguardando 1º acesso', 'var(--texto-ambar-745)', 'var(--fundo-ambar-80)'],
      desativada: ['Desativado', 'var(--texto-cinza-600)', 'var(--fundo-cinza-70)']
    };
    const podeGerir = c =>
      !c.eu && (s.ehAdmin ? c.papel !== 'administrador' : c.papel === 'oficineiro' || c.papel === 'direcao');
    const abrirMudanca = c => {
      const t = new Date();
      t.setDate(t.getDate() + 1);
      while (t.getDay() === 0 || t.getDay() === 6 || Base.feriado(t)) t.setDate(t.getDate() + 1);
      this.abrirGavetaDeConta(
        {
          mudanca: {
            id: c.id,
            nome: c.nome,
            atual: c.escola_id,
            escola: '',
            vale: Base.iso(t),
            motivo: '',
            agora: false
          }
        },
        'ct-mu-escola'
      );
    };
    const contaAberta = s.contaAberta ? s.contas.find(c => c.id === s.contaAberta) : null;
    const telefoneFormatado = t => {
      const d = String(t || '');
      return d.length === 11
        ? '(' + d.slice(0, 2) + ') ' + d.slice(2, 7) + '-' + d.slice(7)
        : d.length === 10
          ? '(' + d.slice(0, 2) + ') ' + d.slice(2, 6) + '-' + d.slice(6)
          : '';
    };
    const detalheDaConta = contaAberta
      ? {
          nome: contaAberta.nome,
          pode: podeGerir(contaAberta),
          naoPode: !podeGerir(contaAberta),
          motivo: contaAberta.eu
            ? 'Você não pode alterar a própria conta. Peça ao Gerente de Projetos.'
            : contaAberta.papel === 'administrador'
              ? 'Contas de administrador só são alteradas pelo painel do Supabase.'
              : 'O Coordenador do núcleo altera apenas contas de oficineiro e de direção escolar. As demais são alteradas pelo Gerente de Projetos.',
          itens: [
            ['Perfil', NOMES_DE_PERFIL[contaAberta.papel] || contaAberta.papel],
            ['Login', contaAberta.usuario || 'gerado no primeiro acesso'],
            [contaAberta.papel === 'analista' ? 'Carteira' : 'Escola de atuação', atuacaoDaConta(contaAberta)],
            ...(contaAberta.papel === 'oficineiro'
              ? [
                  ['Jornada', 'Flexível · 8 horas entre 07:00 e 17:00'],
                  [
                    ((s.contratadas || {})[contaAberta.id] || {}).tipo === 'CPF'
                      ? 'CPF da contratada'
                      : 'CNPJ da contratada',
                    ((s.contratadas || {})[contaAberta.id] || {}).mascara || 'não informado'
                  ]
                ]
              : []),
            ['Situação', SITUACOES_DE_CONTA[situacaoDaConta(contaAberta)][0]],
            ...(!contaAberta.ativo && contaAberta.desativado_em
              ? [
                  ['Desativada em', new Date(contaAberta.desativado_em).toLocaleDateString('pt-BR')],
                  [
                    'Remoção automática',
                    'a partir de ' +
                      new Date(new Date(contaAberta.desativado_em).getTime() + 30 * 864e5).toLocaleDateString('pt-BR')
                  ]
                ]
              : []),
            ['Telefone', telefoneFormatado(contaAberta.telefone) || 'não informado'],
            ['Conta criada em', dataBr(contaAberta.criado_em)],
            ['Último acesso', quando(contaAberta.ultimo_acesso) || 'ainda não entrou']
          ].map(([l, v]) => ({ rotulo: l, valor: v })),
          temMudanca: !!contaAberta.mudanca_escola,
          mudancaTexto: contaAberta.mudanca_escola
            ? 'Muda para ' +
              nomeDaEscola(contaAberta.mudanca_escola) +
              ' a partir de ' +
              dataBr(contaAberta.mudanca_vale) +
              ' · ' +
              contaAberta.mudanca_motivo
            : '',
          podeEscola: podeGerir(contaAberta) && contaAberta.papel === 'oficineiro' && contaAberta.ativo,
          podeJornada: podeGerir(contaAberta) && contaAberta.papel === 'oficineiro' && contaAberta.ativo,
          contratada: s.contratadaEditada != null ? s.contratadaEditada : '',
          escreverContratada: e => this.setState({ contratadaEditada: e.target.value }),
          contratadaMudou: s.contratadaEditada != null,
          salvarContratada: () => this.salvarContratada(contaAberta),
          contratadaBotao: s.salvandoContratada ? 'Salvando…' : 'Salvar CNPJ/CPF',
          salvandoContratada: s.salvandoContratada,
          contratadaAtual: ((s.contratadas || {})[contaAberta.id] || {}).mascara || '',
          podeDesativar: podeGerir(contaAberta) && contaAberta.ativo,
          podeReativar: podeGerir(contaAberta) && !contaAberta.ativo,
          alterar: () => abrirMudanca(contaAberta),
          desativar: () =>
            this.setState({ confirmandoDesativacao: true }, () => {
              const b = document.getElementById('ct-det-confirma');
              if (b) b.focus();
            }),
          voltar: () =>
            this.setState({ confirmandoDesativacao: false }, () => {
              const b = document.getElementById('ct-det-desativar');
              if (b) b.focus();
            }),
          confirmar: () => this.ativarConta(contaAberta, false),
          reativar: () => this.ativarConta(contaAberta, true),
          cancelarMudanca: () => this.cancelarMudanca(contaAberta)
        }
      : {};
    const nova = s.novaConta || {};
    const mudarNova = k => e => this.setState({ novaConta: { ...this.state.novaConta, [k]: e.target.value } });
    const perfisDaNovaConta = [
      ['oficineiro', 'Oficineiro de Inclusão Digital'],
      ['direcao', 'Direção da escola'],
      ...(s.ehAdmin
        ? [
            ['analista', 'Analista'],
            ['coordenador', 'Coordenador'],
            ['gerente', 'Gerente de Projetos']
          ]
        : [])
    ].map(([k, l], i) => {
      const marcado = nova.papel === k,
        off = k === 'coordenador' && !s.ehAdmin;
      return {
        rotulo: l,
        marcado: marcado ? 'true' : 'false',
        desligado: off,
        id: i === 0 ? 'ct-nv-perfil' : 'ct-nv-perfil-' + k,
        tabulacao: marcado || (!nova.papel && i === 0) ? '0' : '-1',
        borda: marcado ? 'var(--destaque-ciano-660)' : 'var(--borda-cinza-160)',
        classe: marcado ? '' : 'fundo-branco botao-secundario',
        fundo: marcado ? 'var(--fundo-ciano-60)' : 'var(--fundo-branco)',
        cor: off ? 'var(--texto-cinza-470)' : marcado ? 'var(--texto-ciano-740)' : 'var(--texto-ciano-850)',
        escolher: () => {
          if (!off) this.setState({ novaConta: { ...this.state.novaConta, papel: k } });
        }
      };
    });
    const teclaNosPerfis = e => {
      const perfis = s.ehAdmin
        ? ['oficineiro', 'direcao', 'analista', 'coordenador', 'gerente']
        : ['oficineiro', 'direcao'];
      const i = perfis.indexOf(this.state.novaConta && this.state.novaConta.papel);
      let j = -1;
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') j = (i + 1) % perfis.length;
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') j = (i - 1 + perfis.length) % perfis.length;
      else return;
      e.preventDefault();
      this.setState({ novaConta: { ...this.state.novaConta, papel: perfis[j] } }, () => {
        const b = document.getElementById(j === 0 ? 'ct-nv-perfil' : 'ct-nv-perfil-' + perfis[j]);
        if (b) b.focus();
      });
    };
    const escolasAtivas = (s.escolas || []).filter(e => e.ativa !== false);
    const mudanca = s.mudanca || {};
    const mudarMudanca = k => e => this.setState({ mudanca: { ...this.state.mudanca, [k]: e.target.value } });
    const escolaDaMudanca = escolaPorId[String(mudanca.escola)];
    const dataMinimaDaMudanca = new Date(),
      dataMaximaDaMudanca = new Date();
    dataMaximaDaMudanca.setDate(dataMaximaDaMudanca.getDate() + 180);
    return {
      NOMES_DE_PERFIL,
      SITUACOES_DE_CONTA,
      abrirMudanca,
      atuacaoDaConta,
      carteiraPorId,
      contaAberta,
      dataBr,
      dataMaximaDaMudanca,
      dataMinimaDaMudanca,
      detalheDaConta,
      escolaDaMudanca,
      escolaPorId,
      escolasAtivas,
      mudanca,
      mudarMudanca,
      mudarNova,
      nomeDaEscola,
      nova,
      perfisDaNovaConta,
      podeGerir,
      quando,
      situacaoDaConta,
      teclaNosPerfis
    };
  }

  function chavesDasContas(s, valores) {
    const {
      contaAberta,
      contexto,
      dataMaximaDaMudanca,
      dataMinimaDaMudanca,
      detalheDaConta,
      escolaDaMudanca,
      escolasAtivas,
      mudanca,
      mudarMudanca,
      mudarNova,
      nomeDaEscola,
      nova,
      perfisDaNovaConta,
      teclaNosPerfis
    } = valores;
    return {
      fecharConta: () => this.fecharGavetaDeConta(),
      novaContaAberta: !!s.novaConta,
      novaConta: {
        nome: nova.nome || '',
        telefone: nova.telefone || '',
        email: nova.email || '',
        cpf: nova.cpf || '',
        escola: nova.escola || '',
        carteira: nova.carteira || '',
        jornada: nova.jornada || '07:00',
        setJornada: mudarNova('jornada'),
        contratada: nova.contratada || '',
        escreverContratada: mudarNova('contratada'),
        escreverNome: mudarNova('nome'),
        escreverTelefone: mudarNova('telefone'),
        escreverEmail: mudarNova('email'),
        escreverCpf: mudarNova('cpf'),
        escolherEscola: mudarNova('escola'),
        escolherCarteira: mudarNova('carteira'),
        ...window.FSM_CONTAS.camposDoConvite.call(this, nova)
      },
      perfisDaNovaConta,
      dicaDePerfil: s.ehAdmin
        ? 'Contas de coordenador e de gerente veem toda a rede. Crie só para quem precisa.'
        : 'Contas de coordenador são criadas pelo Gerente de Projetos.',
      teclaNosPerfis,
      pedeEscola: nova.papel === 'oficineiro' || nova.papel === 'direcao',
      ehOficineiro: nova.papel === 'oficineiro',
      ehAnalista: nova.papel === 'analista',
      opcoesDeEscolaDaConta: escolasAtivas.map(e => ({ valor: e.sigla, rotulo: e.nome })),
      opcoesDeCarteiraDaConta: (s.carteiras || []).map(c => ({ valor: c.id, rotulo: c.rotulo })),
      erroNovaConta: s.erroConta,
      temErroNovaConta: !!s.erroConta,
      criarConta: () => this.criarConta(),
      novaContaBotao: s.salvandoConta ? 'Criando…' : 'Criar usuário',
      salvandoConta: s.salvandoConta,
      contaAberta: !!contaAberta,
      conta: detalheDaConta,
      confirmandoDesativacao: s.confirmandoDesativacao,
      erroConta: s.erroConta,
      temErroConta: !!(contaAberta && s.erroConta),
      mudancaAberta: !!s.mudanca,
      mudanca: {
        nome: mudanca.nome || '',
        atual: nomeDaEscola(mudanca.atual) || '—',
        escola: mudanca.escola || '',
        vale: mudanca.vale || '',
        motivo: mudanca.motivo || '',
        agora: !!mudanca.agora,
        comData: !mudanca.agora,
        escolherEscola: mudarMudanca('escola'),
        escolherData: mudarMudanca('vale'),
        escreverMotivo: mudarMudanca('motivo'),
        marcarAgora: e =>
          this.setState({ mudanca: { ...this.state.mudanca, agora: e.target.checked }, erroMudanca: '' })
      },
      opcoesDeEscolaDaMudanca: escolasAtivas
        .filter(e => e.id !== mudanca.atual)
        .map(e => ({ valor: String(e.id), rotulo: e.nome })),
      enderecoDaMudanca: escolaDaMudanca && escolaDaMudanca.endereco ? escolaDaMudanca.endereco : '',
      temEnderecoDaMudanca: !!(escolaDaMudanca && escolaDaMudanca.endereco),
      mudancaMinima: Base.iso(
        new Date(dataMinimaDaMudanca.getFullYear(), dataMinimaDaMudanca.getMonth(), dataMinimaDaMudanca.getDate() + 1)
      ),
      mudancaMaxima: Base.iso(dataMaximaDaMudanca),
      erroMudanca: s.erroMudanca,
      temErroMudanca: !!s.erroMudanca,
      salvarMudanca: () => this.salvarMudanca(),
      mudancaBotao: s.salvandoConta ? 'Salvando…' : mudanca.agora ? 'Alterar agora' : 'Salvar alteração',
      aviso: s.aviso,
      contexto
    };
  }

  return { valoresDasContas, chavesDasContas };
})();
