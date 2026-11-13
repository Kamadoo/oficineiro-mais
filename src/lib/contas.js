window.FSM_CONTAS = (() => {
  const Base = window.FSM_BASE;

  const CHAVES_DAS_GAVETAS = [
    'baixarModelo',
    'cliente',
    'criarConta',
    'criarLote',
    'dicaDePerfil',
    'ehAdmin',
    'ehAnalista',
    'ehOficineiro',
    'enderecoDaMudanca',
    'erroLote',
    'erroMudanca',
    'erroNovaConta',
    'fecharConta',
    'fecharLote',
    'lerLote',
    'lote',
    'loteAberto',
    'mudanca',
    'mudancaAberta',
    'mudancaBotao',
    'mudancaMaxima',
    'mudancaMinima',
    'novaConta',
    'novaContaAberta',
    'novaContaBotao',
    'opcoesDeCarteiraDaConta',
    'opcoesDeEscolaDaConta',
    'opcoesDeEscolaDaMudanca',
    'pedeEscola',
    'perfisDaNovaConta',
    'salvandoConta',
    'salvarMudanca',
    'teclaNosPerfis',
    'temEnderecoDaMudanca',
    'temErroLote',
    'temErroMudanca',
    'temErroNovaConta'
  ];

  function chavesDasGavetas(chaves) {
    return Base.escolher(chaves, CHAVES_DAS_GAVETAS);
  }

  function avisar(t) {
    this.setState({ aviso: t });
    clearTimeout(this.temporizadorDoAviso);
    this.temporizadorDoAviso = setTimeout(() => this.setState({ aviso: '' }), 3200);
  }

  function travarFundo(on) {
    document.querySelectorAll('.estrutura').forEach(el => {
      if (on) el.setAttribute('inert', '');
      else el.removeAttribute('inert');
    });
  }

  function registrarConsulta(d) {
    const A = window.FSM_AUTH;
    if (A && A.registrarAtividade) A.registrarAtividade('CONSULTA', d);
  }

  function baixarModelo() {
    if (!window.FSM_PLANILHA) return this.avisar('Exportação indisponível nesta versão do site');
    window.FSM_PLANILHA.baixar(
      [
        [
          'Nome completo',
          'E-mail',
          'CPF ou CNPJ',
          'Perfil',
          'Escola (sigla)',
          'Carteira',
          'Horário',
          'Telefone',
          'CNPJ ou CPF da contratada'
        ]
      ],
      'modelo_contas_oficineiro_mais',
      'Contas'
    );
  }

  async function carregarContratadas() {
    const A = window.FSM_AUTH;
    if (!A || !A.contratadasGestao || !this.state.conectado) return;
    try {
      const l = await A.contratadasGestao();
      const m = {};
      (l || []).forEach(x => (m[x.id] = x));
      this.setState({ contratadas: m });
    } catch (x) {}
  }

  async function salvarContratada(c) {
    const v = this.state.contratadaEditada;
    if (v == null || this.state.salvandoContratada) return;
    this.setState({ salvandoContratada: true, erroConta: '' });
    try {
      await window.FSM_AUTH.definirContratada(c.id, v);
      this.setState({ salvandoContratada: false, contratadaEditada: null });
      this.avisar(
        (String(v).replace(/\D/g, '') ? 'CNPJ/CPF da contratada salvo · ' : 'CNPJ/CPF da contratada removido · ') +
          c.nome
      );
      this.carregarContratadas();
    } catch (x) {
      this.setState({
        salvandoContratada: false,
        erroConta: Base.msgErro(x, 'Não foi possível salvar o CNPJ/CPF da contratada.')
      });
    }
  }

  async function lerLote(e) {
    const f = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!f || !this.state.lote) return;
    try {
      const P = await window.FSM_ONB.lerPlanilha(f);
      const col = re => P.colunas.find(c => re.test(c)) || '';
      const C = {
        nome: col(/^nome/),
        email: col(/mail/),
        cpf: col(/^cpf/),
        perfil: col(/perfil|papel/),
        escola: col(/escola|sigla/),
        carteira: col(/carteira/),
        horario: col(/horario|jornada/),
        telefone: col(/telefone|celular/),
        contratada: col(/contratada/) || col(/^cnpj/)
      };
      const falta = ['nome', 'email', 'cpf', 'perfil'].filter(k => !C[k]);
      if (falta.length) throw new Error('faltam as colunas ' + falta.join(', ') + '. Use o modelo.');
      if (!P.linhas.length) throw new Error('a planilha não tem pessoas.');
      if (P.linhas.length > 200) throw new Error('envie no máximo 200 pessoas por vez.');
      const escolas = (this.state.escolasDoSistema || this.state.escolas || []).filter(x => x.ativa !== false),
        carts = this.state.carteiras || [];
      const vistosCpf = {},
        vistosEmail = {};
      const linhas = P.linhas.map((r, i) => {
        const nome = String(r[C.nome] || '')
            .trim()
            .replace(/\s+/g, ' '),
          email = String(r[C.email] || '')
            .trim()
            .toLowerCase(),
          cpf = String(r[C.cpf] || '').replace(/\D/g, ''),
          pn = Base.normTxt(r[C.perfil]),
          papel = /oficin/.test(pn)
            ? 'oficineiro'
            : /analist/.test(pn)
              ? 'analista'
              : /dire/.test(pn)
                ? 'direcao'
                : /coord/.test(pn)
                  ? 'coordenador'
                  : /gerent/.test(pn)
                    ? 'gerente'
                    : '',
          escTxt = String((C.escola && r[C.escola]) || '').trim(),
          esc = escTxt
            ? escolas.find(
                x => Base.normTxt(x.sigla) === Base.normTxt(escTxt) || Base.normTxt(x.nome) === Base.normTxt(escTxt)
              )
            : null,
          cartTxt = String((C.carteira && r[C.carteira]) || '').trim(),
          cart = cartTxt
            ? carts.find(
                x => Base.normTxt(x.id) === Base.normTxt(cartTxt) || Base.normTxt(x.rotulo) === Base.normTxt(cartTxt)
              )
            : null,
          hTxt = String((C.horario && r[C.horario]) || '').trim(),
          hMatch = hTxt.match(/^\s*0?([78])(?:[:h.]?00)?\s*h?\s*$/i),
          jornada = hTxt && !hMatch ? '' : '07:00',
          tel = String((C.telefone && r[C.telefone]) || '').replace(/\D/g, ''),
          contratada = String((C.contratada && r[C.contratada]) || '').replace(/\D/g, '');
        let erro = '';
        if (nome.length < 3 || nome.length > 120) erro = 'Nome inválido';
        else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 160) erro = 'E-mail inválido';
        else if (!documentoValido(cpf)) erro = 'CPF ou CNPJ inválido';
        else if (vistosCpf[cpf]) erro = 'CPF ou CNPJ repetido na linha ' + vistosCpf[cpf];
        else if (vistosEmail[email]) erro = 'E-mail repetido na linha ' + vistosEmail[email];
        else if (!papel) erro = 'Perfil não reconhecido';
        else if ((papel === 'oficineiro' || papel === 'direcao') && !esc) erro = 'Escola não encontrada';
        else if (papel === 'analista' && !cart) erro = 'Carteira não encontrada';
        else if (papel === 'oficineiro' && !jornada) erro = 'Horário: deixe em branco (jornada flexível)';
        else if (tel && (tel.length < 10 || tel.length > 11)) erro = 'Telefone inválido';
        else if (papel === 'oficineiro' && contratada && ![11, 14].includes(contratada.length))
          erro = 'CNPJ/CPF da contratada inválido';
        if (!erro) {
          vistosCpf[cpf] = i + 2;
          vistosEmail[email] = i + 2;
        }
        return {
          n: i + 2,
          nome,
          email,
          cpf,
          papel,
          escola: papel === 'oficineiro' || papel === 'direcao' ? esc : null,
          carteira: papel === 'analista' ? cart : null,
          jornada: papel === 'oficineiro' ? jornada : '',
          contratada: papel === 'oficineiro' ? contratada : '',
          tel,
          erro,
          st: erro ? 'erro' : 'pronta',
          msg: ''
        };
      });
      this.setState({ lote: { linhas, arquivo: f.name, criando: false, feito: false }, erroLote: '' });
    } catch (x) {
      this.setState({
        lote: { linhas: null, arquivo: '', criando: false, feito: false },
        erroLote: 'Não foi possível ler a planilha: ' + ((x && x.message) || 'arquivo inválido.')
      });
    }
  }

  async function criarLote() {
    const L = this.state.lote;
    if (!L || L.criando || !L.linhas) return;
    const fila = L.linhas.filter(l => l.st === 'pronta').map(l => l.n);
    if (!fila.length) return;
    const atual = n => this.state.lote.linhas.find(l => l.n === n);
    const marcar = (n, ch) =>
      new Promise(r =>
        this.setState(
          { lote: { ...this.state.lote, linhas: this.state.lote.linhas.map(l => (l.n === n ? { ...l, ...ch } : l)) } },
          r
        )
      );
    await new Promise(r => this.setState({ lote: { ...L, criando: true } }, r));
    let ok = 0,
      falhas = 0;
    for (const n of fila) {
      if (!this.state.lote) return;
      const l = atual(n);
      await marcar(n, { st: 'criando' });
      try {
        const novo = await window.FSM_AUTH.cadastrarUsuario({
          nome: l.nome,
          email: l.email,
          cpf: l.cpf,
          papel: l.papel,
          telefone: l.tel,
          escola_sigla: l.escola ? l.escola.sigla : '',
          carteira_id: l.carteira ? l.carteira.id : ''
        });
        let semContratada = false;
        if (l.papel === 'oficineiro' && novo && novo.id) {
          if (l.contratada)
            try {
              await window.FSM_AUTH.definirContratada(novo.id, l.contratada);
            } catch (x) {
              semContratada = true;
            }
        }
        ok++;
        await marcar(n, {
          st: 'criada',
          msg: semContratada ? 'CNPJ/CPF da contratada não salvo' : '',
          cpf: '',
          contratada: ''
        });
      } catch (x) {
        falhas++;
        await marcar(n, { st: 'falha', msg: Base.msgErro(x, 'Não foi possível criar.') });
      }
    }
    if (!this.state.lote) return;
    this.setState({ lote: { ...this.state.lote, criando: false, feito: true } });
    this.avisar(
      Base.plural(ok, 'conta criada', 'contas criadas') + (falhas ? ' · ' + Base.plural(falhas, 'falha', 'falhas') : '')
    );
    this.carregarContas();
  }

  function documentoValido(c) {
    const d = String(c || '').replace(/\D/g, '');
    if (d.length === 14) {
      if (/^(\d)\1{13}$/.test(d)) return false;
      const dj = n => {
        let t = 0;
        for (let i = 0; i < n; i++) t += Number(d[i]) * (((n - 1 - i) % 8) + 2);
        const r = t % 11;
        return r < 2 ? 0 : 11 - r;
      };
      return dj(12) === Number(d[12]) && dj(13) === Number(d[13]);
    }
    if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
    const dv = n => {
      let t = 0;
      for (let i = 0; i < n; i++) t += Number(d[i]) * (n + 1 - i);
      const r = (t * 10) % 11;
      return r === 10 ? 0 : r;
    };
    return dv(9) === Number(d[9]) && dv(10) === Number(d[10]);
  }

  async function criarConta() {
    const f = this.state.novaConta;
    if (!f || this.state.salvandoConta) return;
    const nome = f.nome.trim().replace(/\s+/g, ' '),
      email = f.email.trim(),
      tel = f.telefone.replace(/\D/g, '');
    let erro = '',
      campo = '';
    if (nome.length < 3) {
      erro = 'Digite o nome completo.';
      campo = 'ct-nv-nome';
    } else if (tel && (tel.length < 10 || tel.length > 11)) {
      erro = 'Telefone: digite o DDD e o número.';
      campo = 'ct-nv-tel';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      erro = 'Digite um e-mail válido.';
      campo = 'ct-nv-email';
    } else if (!documentoValido(f.cpf)) {
      erro = 'CPF ou CNPJ inválido. Confira os números.';
      campo = 'ct-nv-cpf';
    } else if (!f.papel) {
      erro = 'Escolha o perfil.';
      campo = 'ct-nv-perfil';
    } else if ((f.papel === 'oficineiro' || f.papel === 'direcao') && !f.escola) {
      erro = 'Escolha a escola de atuação.';
      campo = 'ct-nv-escola';
    } else if (f.papel === 'analista' && !f.carteira) {
      erro = 'Escolha a carteira do analista.';
      campo = 'ct-nv-carteira';
    } else if (
      f.papel === 'oficineiro' &&
      String(f.contratada || '').replace(/\D/g, '') &&
      ![11, 14].includes(String(f.contratada || '').replace(/\D/g, '').length)
    ) {
      erro = 'Informe o CNPJ (14 números) ou o CPF (11 números) da contratada, ou deixe em branco.';
      campo = 'ct-nv-contratada';
    }
    if (erro) {
      this.setState({ erroConta: erro }, () => this.focar(campo));
      return;
    }
    this.setState({ salvandoConta: true, erroConta: '' });
    try {
      const novo = await window.FSM_AUTH.cadastrarUsuario({
        nome,
        email,
        cpf: f.cpf,
        papel: f.papel,
        telefone: tel,
        escola_sigla: f.papel === 'oficineiro' || f.papel === 'direcao' ? f.escola : '',
        carteira_id: f.papel === 'analista' ? f.carteira : ''
      });
      let semContratada = false;
      if (f.papel === 'oficineiro' && novo && novo.id) {
        if (String(f.contratada || '').replace(/\D/g, ''))
          try {
            await window.FSM_AUTH.definirContratada(novo.id, f.contratada);
          } catch (x) {
            semContratada = true;
          }
      }
      this.setState({ salvandoConta: false }, () => {
        this.fecharGavetaDeConta();
        this.avisar(
          semContratada
            ? 'Usuário criado, mas o CNPJ/CPF da contratada não foi salvo · abra a conta e confira o número'
            : 'Usuário criado · ' +
                nome +
                ' ativa a conta em “Primeiro acesso”, com o CPF ou CNPJ e o código enviado ao e-mail'
        );
        this.contasMudaram();
      });
    } catch (x) {
      this.setState({
        salvandoConta: false,
        erroConta: Base.msgErro(x, 'Não foi possível criar a conta.')
      });
    }
  }

  async function ativarConta(c, ativa) {
    if (this.state.salvandoConta) return;
    this.setState({ salvandoConta: true, erroConta: '' });
    try {
      await window.FSM_AUTH.ativarConta(c.id, ativa);
      this.setState({ salvandoConta: false, confirmandoDesativacao: false }, () => {
        this.avisar(
          ativa
            ? 'Conta reativada · ' + c.nome + ' volta a entrar no sistema'
            : 'Conta desativada · ' + c.nome + ' não entra mais no sistema'
        );
        this.contasMudaram();
        this.focar('ct-det-titulo');
      });
    } catch (x) {
      this.setState({
        salvandoConta: false,
        erroConta: Base.msgErro(x, 'Não foi possível concluir.')
      });
    }
  }

  async function salvarMudanca() {
    const m = this.state.mudanca;
    if (!m || this.state.salvandoConta) return;
    let erro = '',
      campo = '';
    if (!m.escola) {
      erro = 'Escolha a nova escola.';
      campo = 'ct-mu-escola';
    } else if (!m.agora && !/^\d{4}-\d{2}-\d{2}$/.test(m.vale)) {
      erro = 'Escolha a data em que a mudança vale.';
      campo = 'ct-mu-vale';
    } else if (!m.motivo) {
      erro = 'Escolha o motivo.';
      campo = 'ct-mu-motivo';
    }
    if (erro) {
      this.setState({ erroMudanca: erro }, () => this.focar(campo));
      return;
    }
    this.setState({ salvandoConta: true, erroMudanca: '' });
    try {
      const vale = m.agora && this.state.ehAdmin ? Base.iso(new Date()) : m.vale;
      const r = await window.FSM_AUTH.alterarEscola(m.id, m.escola, vale, m.motivo);
      this.setState({ salvandoConta: false }, () => {
        this.fecharGavetaDeConta();
        this.avisar(
          (r === 'agendada' ? 'Mudança de escola agendada para ' + Base.dmyIso(vale) : 'Escola de atuação alterada') +
            ' · ' +
            m.nome +
            ' foi avisado(a)'
        );
        this.contasMudaram();
      });
    } catch (x) {
      this.setState({
        salvandoConta: false,
        erroMudanca: Base.msgErro(x, 'Não foi possível salvar.')
      });
    }
  }

  async function cancelarMudanca(c) {
    if (this.state.salvandoConta) return;
    this.setState({ salvandoConta: true, erroConta: '' });
    try {
      await window.FSM_AUTH.cancelarMudancaEscola(c.id);
      this.setState({ salvandoConta: false }, () => {
        this.avisar('Mudança de escola cancelada · ' + c.nome + ' continua na escola atual');
        this.contasMudaram();
      });
    } catch (x) {
      this.setState({
        salvandoConta: false,
        erroConta: Base.msgErro(x, 'Não foi possível cancelar.')
      });
    }
  }
  function detalharLote(loteAtual, nomesDePerfil) {
    const SITUACOES_DO_LOTE = {
      pronta: ['Pronta para criar', 'var(--texto-verde-700)'],
      erro: ['', 'var(--texto-vermelho-600)'],
      criando: ['Criando…', 'var(--texto-azul-640)'],
      criada: ['Conta criada', 'var(--texto-verde-700)'],
      falha: ['', 'var(--texto-vermelho-600)']
    };
    const linhasDoLote = loteAtual && loteAtual.linhas ? loteAtual.linhas : [];
    const prontas = linhasDoLote.filter(l => l.st === 'pronta').length,
      comErro = linhasDoLote.filter(l => l.st === 'erro').length,
      criadas = linhasDoLote.filter(l => l.st === 'criada').length,
      comFalha = linhasDoLote.filter(l => l.st === 'falha').length;
    return {
      temArquivo: !!(loteAtual && loteAtual.linhas),
      resumo:
        loteAtual && loteAtual.linhas
          ? loteAtual.arquivo +
            ' · ' +
            Base.plural(linhasDoLote.length, 'pessoa', 'pessoas') +
            ' · ' +
            Base.plural(prontas, 'pronta', 'prontas') +
            ' · ' +
            Base.plural(comErro, 'com problema', 'com problema') +
            (criadas || comFalha
              ? ' · ' +
                Base.plural(criadas, 'criada', 'criadas') +
                (comFalha ? ' · ' + Base.plural(comFalha, 'falha', 'falhas') : '')
              : '')
          : '',
      linhas: linhasDoLote.map(l => ({
        numero: String(l.n),
        nome: l.nome || '—',
        email: l.email || '—',
        documento: l.st === 'criada' ? 'apagado' : documentoMascarado(l.cpf),
        perfil: nomesDePerfil[l.papel] || '—',
        vinculo: l.escola
          ? l.escola.sigla
          : l.carteira
            ? l.carteira.id
            : l.papel === 'coordenador' || l.papel === 'gerente'
              ? 'Toda a rede'
              : '—',
        situacao:
          l.st === 'erro'
            ? l.erro
            : l.st === 'falha'
              ? 'Falhou · ' + l.msg
              : SITUACOES_DO_LOTE[l.st][0] + (l.msg ? ' · ' + l.msg : ''),
        cor: SITUACOES_DO_LOTE[l.st][1]
      })),
      podeCriar: !!(loteAtual && loteAtual.linhas && (prontas || loteAtual.criando)),
      criando: !!(loteAtual && loteAtual.criando),
      botao: loteAtual && loteAtual.criando ? 'Criando contas…' : 'Criar ' + Base.plural(prontas, 'conta', 'contas'),
      fecharTexto: loteAtual && loteAtual.feito ? 'Concluir' : 'Cancelar'
    };
  }

  function documentoMascarado(c) {
    const d = String(c || '').replace(/\D/g, '');
    if (d.length === 14) return '**.***.' + d.slice(5, 8) + '/' + d.slice(8, 12) + '-**';
    return d.length === 11 ? '***.' + d.slice(3, 6) + '.' + d.slice(6, 9) + '-**' : d ? 'inválido' : '—';
  }

  return {
    avisar,
    travarFundo,
    registrarConsulta,
    baixarModelo,
    carregarContratadas,
    salvarContratada,
    lerLote,
    criarLote,
    documentoValido,
    criarConta,
    ativarConta,
    salvarMudanca,
    cancelarMudanca,
    documentoMascarado,
    detalharLote,
    chavesDasGavetas
  };
})();
