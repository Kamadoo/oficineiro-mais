window.FSM_BASE_ACESSOS = (() => {
  const LIMITES = { arquivo: 25 * 1024 * 1024, descompactado: 150 * 1024 * 1024, linhas: 40000, entradas: 4000 };
  const TIPOS = {
    criados: 'Usuários criados',
    implementados: 'Usuários implementados',
    dias: 'Dias de acesso por usuário',
    semAcesso: 'Sem acesso'
  };
  const PERFIS = { aluno: 'A', professor: 'P', servidor: 'S' };
  const VAZIO = /^(em branco|-|n\/?a|null)?$/i;

  const chave = texto =>
    String(texto || '')
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');
  const limpo = valor =>
    String(valor == null ? '' : valor)
      .replace(/\s+/g, ' ')
      .trim();
  const preenchido = valor => !VAZIO.test(limpo(valor));
  const doisDigitos = n => (n < 10 ? '0' : '') + n;
  const isoUtc = data =>
    data.getUTCFullYear() + '-' + doisDigitos(data.getUTCMonth() + 1) + '-' + doisDigitos(data.getUTCDate());

  function dataDe(valor) {
    const texto = limpo(valor);
    if (!preenchido(texto)) return null;
    if (/^\d+(\.\d+)?$/.test(texto)) {
      const serial = Math.floor(Number(texto));
      if (serial < 20000 || serial > 80000) return null;
      return isoUtc(new Date(Date.UTC(1899, 11, 30) + serial * 86400000));
    }
    let m = texto.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return m[1] + '-' + m[2] + '-' + m[3];
    m = texto.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
    if (m) return m[3] + '-' + doisDigitos(Number(m[2])) + '-' + doisDigitos(Number(m[1]));
    return null;
  }
  const menor = (a, b) => (!a ? b : !b ? a : a < b ? a : b);
  const maior = (a, b) => (!a ? b : !b ? a : a > b ? a : b);

  function coluna(colunas, ...nomes) {
    const alvo = nomes.map(chave);
    for (const nome of alvo) {
      const achada = colunas.find(c => chave(c) === nome);
      if (achada) return achada;
    }
    return null;
  }

  function identificar(tabela) {
    const c = tabela.colunas;
    const login = coluna(c, 'login', 'des_usu_login');
    if (!login) return null;
    const base = {
      login,
      nome: coluna(c, 'nome', 'des_usu_nomecompleto'),
      perfil: coluna(c, 'perfil'),
      categoria: coluna(c, 'categoria'),
      local: coluna(c, 'local'),
      turma: coluna(c, 'turma'),
      email: coluna(c, 'email', 'des_usu_email'),
      matricula: coluna(c, 'matricula'),
      funcao: coluna(c, 'funcao')
    };
    if (coluna(c, 'Dias de Acesso'))
      return {
        tipo: 'dias',
        ...base,
        dias: coluna(c, 'Dias de Acesso'),
        primeira: coluna(c, 'PrimeiraDataAcesso_perfil', 'primeira_data_acesso'),
        ultima: coluna(c, 'UltimaDataAcesso_perfil', 'ultima_data_acesso')
      };
    if (coluna(c, 'responsavel_turma') || chave(login) === 'login')
      return {
        tipo: 'criados',
        ...base,
        ultima: coluna(c, '__UltimaDataAcesso', 'ultima_data_acesso'),
        responsavel: coluna(c, 'responsavel_turma')
      };
    if (coluna(c, 'ultima_data_acesso')) {
      const nome = String(tabela.arquivo || '');
      const faixa = Number((nome.match(/sem\W*_*acesso\D{0,3}(\d{2,3})/i) || nome.match(/(\d{2,3})/) || [])[1]) || 0;
      return {
        tipo: 'semAcesso',
        faixa,
        ...base,
        primeira: coluna(c, 'primeira_data_acesso'),
        ultima: coluna(c, 'ultima_data_acesso')
      };
    }
    if (coluna(c, 'primeira_data_acesso'))
      return { tipo: 'implementados', ...base, primeira: coluna(c, 'primeira_data_acesso') };
    return null;
  }

  async function ler(arquivos) {
    const lidos = [];
    for (const arquivo of Array.from(arquivos || [])) {
      const tabela = await window.FSM_ONB.lerTabela(arquivo, { aba: 'Export', limites: LIMITES });
      const mapa = identificar(tabela);
      if (!mapa) throw new Error('Não reconheci a planilha ' + arquivo.name + ': falta a coluna de login.');
      const linhas = tabela.linhas.filter(
        l => preenchido(l[mapa.login]) && !/^filtros aplicados/i.test(limpo(l[mapa.login]))
      );
      lidos.push({ arquivo: tabela.arquivo, mapa, linhas, total: linhas.length });
    }
    return lidos;
  }

  async function resumoDoLogin(login) {
    const bytes = new TextEncoder().encode(limpo(login).toLowerCase());
    const resumo = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    return Array.from(resumo, b => (b < 16 ? '0' : '') + b.toString(16)).join('');
  }

  function emailDe(valor) {
    const email = limpo(valor).toLowerCase();
    return email.length <= 160 && /^[^@\s]+@[^@\s]+$/.test(email) ? email : null;
  }

  function matriculaDe(p) {
    const informada = limpo(p.matricula);
    if (preenchido(informada) && /^[0-9A-Za-z.-]{1,20}$/.test(informada)) return informada;
    const doEmail = (limpo(p.email).match(/^(?:[^@]*?\.)?(\d{3,20})@/) || [])[1];
    if (doEmail) return doEmail;
    return /^\d{4,7}$/.test(limpo(p.login)) ? limpo(p.login) : null;
  }

  function semSigla(nome) {
    return limpo(nome).replace(/^[A-Za-zÀ-ú0-9]{1,8}\s*-\s*/, '');
  }

  function reconhecerUnidade(local, categoria, escolas) {
    const alvo = chave(local),
      alvoSemSigla = chave(semSigla(local));
    let achada = escolas.find(e => chave(e.nome) === alvo || chave(semSigla(e.nome)) === alvoSemSigla);
    if (achada) return { escola: achada, forma: 'nome' };
    const sigla = (limpo(local).match(/^([A-Za-zÀ-ú0-9]{1,8})\s*-\s*/) || [])[1];
    if (sigla) {
      achada = escolas.find(e => chave(e.sigla) === chave(sigla));
      if (achada) return { escola: achada, forma: 'sigla' };
    }
    const lista = escolas.map(e => ({ sig: e.sigla, n: e.nome, cs: e.carteira_id || '' }));
    const aproximada = window.FSM_ONB.matchEscola(local, lista);
    if (aproximada) {
      achada = escolas.find(e => e.sigla === aproximada.sig);
      if (achada && (!achada.carteira_id || achada.carteira_id === categoria))
        return { escola: achada, forma: 'aproximada' };
    }
    return null;
  }

  async function consolidar(lidos, opcoes) {
    const o = opcoes || {};
    const escolas = o.escolas || [];
    const carteiras = new Set((o.carteiras || []).map(c => c.id));
    const baseRef = o.baseRef || '';
    const porTipo = tipo => lidos.filter(l => l.mapa.tipo === tipo);
    const criados = porTipo('criados');
    const avisos = [];
    if (!criados.length) throw new Error('Envie a planilha de usuários criados: ela é a base de todas as pessoas.');
    const pessoas = new Map();
    const valor = (linha, campo, mapa) => (mapa[campo] ? linha[mapa[campo]] : '');
    const pessoaDe = (linha, mapa) => {
      const id = limpo(linha[mapa.login]).toLowerCase();
      let p = pessoas.get(id);
      if (!p) {
        p = { login: id, origem: mapa.tipo };
        pessoas.set(id, p);
      }
      const completar = (campo, novo) => {
        if (!p[campo] && preenchido(novo)) p[campo] = limpo(novo);
      };
      completar('nome', valor(linha, 'nome', mapa));
      completar('perfil', valor(linha, 'perfil', mapa));
      completar('categoria', valor(linha, 'categoria', mapa));
      completar('local', valor(linha, 'local', mapa));
      completar('turma', valor(linha, 'turma', mapa));
      completar('responsavel', valor(linha, 'responsavel', mapa));
      completar('email', valor(linha, 'email', mapa));
      completar('matricula', valor(linha, 'matricula', mapa));
      completar('funcao', valor(linha, 'funcao', mapa));
      p.primeiro = menor(p.primeiro, dataDe(valor(linha, 'primeira', mapa)));
      p.ultimo = maior(p.ultimo, dataDe(valor(linha, 'ultima', mapa)));
      return p;
    };
    const ordem = ['criados', 'dias', 'implementados', 'semAcesso'];
    const conferencias = [];
    ordem.forEach(tipo =>
      porTipo(tipo).forEach(l => {
        let foraDaBase = 0;
        const vistos = new Set();
        l.linhas.forEach(linha => {
          const id = limpo(linha[l.mapa.login]).toLowerCase();
          vistos.add(id);
          if (tipo !== 'criados' && !pessoas.has(id)) foraDaBase++;
          const p = pessoaDe(linha, l.mapa);
          if (tipo === 'dias') {
            const dias = Number(limpo(linha[l.mapa.dias]).replace(',', '.'));
            if (Number.isFinite(dias) && dias >= 0) p.dias = Math.max(p.dias || 0, Math.round(dias));
          }
          if (tipo === 'semAcesso') (p.faixas = p.faixas || []).push(l.mapa.faixa);
        });
        conferencias.push({
          arquivo: l.arquivo,
          tipo,
          faixa: l.mapa.faixa || 0,
          linhas: l.total,
          pessoas: vistos.size,
          foraDaBase
        });
      })
    );

    const unidades = new Map();
    const lista = [];
    let perfilIndefinido = 0;
    let semCarteira = 0;
    for (const p of pessoas.values()) {
      const tipo = PERFIS[chave(p.perfil)] || 'S';
      if (!PERFIS[chave(p.perfil)]) perfilIndefinido++;
      const categoria = carteiras.has(limpo(p.categoria).toUpperCase()) ? limpo(p.categoria).toUpperCase() : null;
      if (!categoria) semCarteira++;
      const local = preenchido(p.local) ? limpo(p.local) : 'Unidade não informada' + (categoria ? ' ' + categoria : '');
      const chaveDaUnidade = chave(local);
      let unidade = unidades.get(chaveDaUnidade);
      if (!unidade) {
        const achada = reconhecerUnidade(local, categoria, escolas);
        unidade = {
          nome: local.slice(0, 160),
          escola: achada ? achada.escola : null,
          forma: achada ? achada.forma : 'nova',
          categorias: {},
          pessoas: 0
        };
        unidades.set(chaveDaUnidade, unidade);
      }
      unidade.pessoas++;
      if (categoria) unidade.categorias[categoria] = (unidade.categorias[categoria] || 0) + 1;
      const aluno = tipo === 'A';
      const turma = aluno && preenchido(p.turma) ? limpo(p.turma).slice(0, 40) : null;
      const ano = turma ? Number((turma.match(/^(\d)/) || [])[1] || 0) : 0;
      lista.push({
        login: p.login,
        unidade,
        registro: {
          nome: limpo(p.nome || 'Sem nome').slice(0, 160),
          tipo,
          carteira: categoria,
          turma,
          ano,
          responsavel: preenchido(p.responsavel) ? limpo(p.responsavel).slice(0, 160) : null,
          email: emailDe(p.email),
          matricula: matriculaDe(p),
          funcao: !aluno && preenchido(p.funcao) ? limpo(p.funcao).slice(0, 80) : null,
          primeiro: p.primeiro || null,
          ultimo: p.ultimo || null,
          dias: p.dias == null ? null : p.dias
        },
        faixas: p.faixas || []
      });
    }

    const novas = [];
    const ganhamCarteira = [];
    const aproximadas = [];
    const divergentes = [];
    unidades.forEach(u => {
      const categorias = Object.keys(u.categorias).sort((a, b) => u.categorias[b] - u.categorias[a]);
      u.carteira = categorias[0] || null;
      if (categorias.length > 1)
        avisos.push('A unidade ' + u.nome + ' aparece em mais de uma carteira (' + categorias.join(', ') + ').');
      if (!u.escola) {
        if (u.carteira) novas.push({ nome: u.nome, carteira: u.carteira, pessoas: u.pessoas });
        return;
      }
      if (u.forma === 'aproximada') aproximadas.push({ nome: u.nome, escola: u.escola.nome, pessoas: u.pessoas });
      if (!u.escola.carteira_id && u.carteira && !ganhamCarteira.some(g => g.escola === u.escola.id))
        ganhamCarteira.push({ escola: u.escola.id, nome: u.escola.nome, carteira: u.carteira, pessoas: u.pessoas });
      else if (u.carteira && u.escola.carteira_id && u.escola.carteira_id !== u.carteira)
        divergentes.push({
          nome: u.escola.nome,
          site: u.escola.carteira_id,
          planilha: u.carteira,
          pessoas: u.pessoas
        });
    });
    const semUnidade = Array.from(unidades.values()).filter(u => !u.escola && !u.carteira);
    semUnidade.forEach(u =>
      avisos.push('A unidade ' + u.nome + ' não tem carteira conhecida: ' + u.pessoas + ' pessoa(s) ficarão de fora.')
    );
    if (perfilIndefinido)
      avisos.push(perfilIndefinido + ' pessoa(s) com perfil em branco serão contadas como Servidor.');
    if (semCarteira) avisos.push(semCarteira + ' pessoa(s) com categoria fora das carteiras do site.');

    const ultimoAcesso = lista.reduce((m, l) => maior(m, l.registro.ultimo), null);
    const depoisDaBase = baseRef ? lista.filter(l => l.registro.ultimo && l.registro.ultimo > baseRef).length : 0;
    const diasAte = data => (data ? Math.round((Date.parse(baseRef) - Date.parse(data)) / 86400000) : null);
    conferencias
      .filter(c => c.tipo === 'semAcesso' && c.faixa)
      .forEach(c => {
        const nela = lista.filter(l => l.faixas.indexOf(c.faixa) >= 0);
        c.conferem = baseRef ? nela.filter(l => (diasAte(l.registro.ultimo) || 0) >= c.faixa).length : 0;
      });
    const validas = lista.filter(l => l.unidade.escola || l.unidade.carteira);
    const contar = f => validas.reduce((n, l) => n + (f(l) ? 1 : 0), 0);
    const porCarteira = {};
    validas.forEach(l => {
      const k = l.unidade.escola ? l.unidade.escola.carteira_id || l.unidade.carteira || '—' : l.unidade.carteira;
      porCarteira[k] = (porCarteira[k] || 0) + 1;
    });
    const resumo = {
      arquivos: lidos.map(l => ({ tipo: l.mapa.tipo, faixa: l.mapa.faixa || 0, linhas: l.total })),
      pessoas: validas.length,
      alunos: contar(l => l.registro.tipo === 'A'),
      professores: contar(l => l.registro.tipo === 'P'),
      servidores: contar(l => l.registro.tipo === 'S'),
      comAcesso: contar(l => !!l.registro.ultimo),
      comDias: contar(l => l.registro.dias != null),
      comTurma: contar(l => !!l.registro.turma),
      ultimoAcesso,
      porCarteira,
      unidadesNovas: novas.length,
      unidadesComCarteira: ganhamCarteira.length,
      aproximadas: aproximadas.length,
      divergentes: divergentes.length,
      foraDaBase: semUnidade.reduce((n, u) => n + u.pessoas, 0)
    };
    const tipos = lidos.map(l => l.mapa.tipo);
    ['dias', 'implementados', 'semAcesso'].forEach(t => {
      if (tipos.indexOf(t) < 0) avisos.push('Planilha de ' + TIPOS[t].toLowerCase() + ' não enviada.');
    });
    return {
      resumo,
      avisos,
      conferencias,
      novas,
      ganhamCarteira,
      aproximadas,
      divergentes,
      depoisDaBase,
      validas
    };
  }

  async function montarEnvio(consolidado) {
    const pessoas = [];
    for (const l of consolidado.validas) {
      const r = l.registro;
      const item = { h: await resumoDoLogin(l.login), nome: r.nome, tipo: r.tipo, carteira: r.carteira, ano: r.ano };
      if (l.unidade.escola) item.escola = l.unidade.escola.id;
      else item.unidade = l.unidade.nome;
      ['turma', 'responsavel', 'primeiro', 'ultimo', 'dias', 'matricula', 'email', 'funcao'].forEach(k => {
        if (r[k] != null) item[k] = r[k];
      });
      pessoas.push(item);
    }
    const unidades = consolidado.novas
      .map(u => ({ nome: u.nome, carteira: u.carteira }))
      .concat(consolidado.ganhamCarteira.map(u => ({ escola: u.escola, carteira: u.carteira })));
    return { pessoas, unidades };
  }

  return { TIPOS, ler, identificar, consolidar, montarEnvio, resumoDoLogin, dataDe };
})();
